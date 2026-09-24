#if os(iOS)
import Foundation
import MosaicAppUI
import MosaicCore
import MosaicFeatures
import PhotosUI
import SwiftUI

private enum PendingImportRetry {
    case hero(PhotosPickerItem)
    case sources([PhotosPickerItem])
}

private final class PhotoTransferProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var monitor: Task<Void, Never>?
    private var progress: Progress?
    private var isStopped = false

    func start(
        progress: Progress,
        report: @escaping @Sendable (Double) async -> Void
    ) {
        let monitor = Task {
            var lastPercentage = -1
            while !Task.isCancelled {
                let rawFraction = progress.fractionCompleted
                let fraction = rawFraction.isFinite ? min(1, max(0, rawFraction)) : 0
                let percentage = Int((fraction * 100).rounded(.down))
                if percentage != lastPercentage {
                    lastPercentage = percentage
                    await report(fraction)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        lock.lock()
        self.progress = progress
        if isStopped {
            lock.unlock()
            monitor.cancel()
            progress.cancel()
        } else {
            self.monitor = monitor
            lock.unlock()
        }
    }

    func stop(cancelTransfer: Bool = false) {
        lock.lock()
        isStopped = true
        let monitor = self.monitor
        let progress = self.progress
        self.monitor = nil
        lock.unlock()
        monitor?.cancel()
        if cancelTransfer {
            progress?.cancel()
        }
    }
}

private func loadPickerData(
    from item: PhotosPickerItem,
    identifier: String,
    relay: PhotoTransferProgressRelay,
    report: @escaping @Sendable (Double) async -> Void
) async throws -> Data {
    let result: Result<Data, Error> = await withCheckedContinuation {
        (continuation: CheckedContinuation<Result<Data, Error>, Never>) in
        let progress: Progress = item.loadTransferable(type: Data.self) {
            (transferResult: Result<Data?, Error>) in
            relay.stop()
            switch transferResult {
            case .success(let data?):
                continuation.resume(returning: .success(data))
            case .success(nil):
                continuation.resume(
                    returning: .failure(PhotoSelectionError.assetUnavailable(identifier))
                )
            case .failure(let error):
                continuation.resume(returning: .failure(error))
            }
        }
        relay.start(progress: progress, report: report)
    }
    return try result.get()
}

extension PhotosPickerAssetStore {
    public func importSelection(
        _ items: [PhotosPickerItem],
        onProgress: @escaping @Sendable (PhotoImportProgress) async -> Void = { _ in }
    ) async throws -> [AssetReference] {
        guard !items.isEmpty else { return [] }
        var references: [AssetReference] = []
        await onProgress(.init(completedCount: 0, totalCount: items.count))
        do {
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                let identifier = item.itemIdentifier ?? "selected-photo"
                let data: Data
                do {
                    data = try await loadData(
                        from: item,
                        identifier: identifier,
                        completedCount: index,
                        totalCount: items.count,
                        onProgress: onProgress
                    )
                } catch let error as PhotoSelectionError {
                    throw error
                } catch {
                    throw PhotoTransferErrorClassifier().classify(error, identifier: identifier)
                }
                try Task.checkCancellation()
                references.append(
                    try registerImportedData(
                        data,
                        sourceIdentifier: identifier
                    )
                )
                await onProgress(.init(completedCount: index + 1, totalCount: items.count))
                try Task.checkCancellation()
            }
            return references
        } catch is CancellationError {
            discardCachedAssets(references)
            throw PhotoSelectionError.selectionCancelled
        } catch let error as PhotoSelectionError {
            discardCachedAssets(references)
            throw error
        } catch {
            discardCachedAssets(references)
            throw PhotoTransferErrorClassifier().classify(error, identifier: "selected-photo")
        }
    }

    private func loadData(
        from item: PhotosPickerItem,
        identifier: String,
        completedCount: Int,
        totalCount: Int,
        onProgress: @escaping @Sendable (PhotoImportProgress) async -> Void
    ) async throws -> Data {
        let relay = PhotoTransferProgressRelay()
        return try await withTaskCancellationHandler {
            let data = try await loadPickerData(
                from: item,
                identifier: identifier,
                relay: relay
            ) { fraction in
                await onProgress(
                    .init(
                        completedCount: completedCount,
                        totalCount: totalCount,
                        currentItemFractionCompleted: fraction
                    )
                )
            }
            try Task.checkCancellation()
            return data
        } onCancel: {
            relay.stop(cancelTransfer: true)
        }
    }
}

public struct PhotosPickerCreationView: View {
    @ObservedObject private var session: CreationSession
    private let assetStore: PhotosPickerAssetStore
    private let onClose: () -> Void

    @State private var isChoosingHero = false
    @State private var isChoosingSources = false
    @State private var heroItem: PhotosPickerItem?
    @State private var sourceItems: [PhotosPickerItem] = []
    @State private var importMessage: String?
    @State private var importProgress: PhotoImportProgress?
    @State private var pendingRetry: PendingImportRetry?

    public init(
        session: CreationSession,
        assetStore: PhotosPickerAssetStore,
        onClose: @escaping () -> Void = {}
    ) {
        self.session = session
        self.assetStore = assetStore
        self.onClose = onClose
    }

    public var body: some View {
        MosaicCreationView(
            session: session,
            assetLoader: assetStore,
            onChooseHero: beginHeroSelection,
            onChooseSources: beginSourceSelection,
            onRemoveSource: { reference in
                await assetStore.discardCachedAssets([reference])
            },
            onClose: onClose
        )
        .disabled(importProgress != nil)
        .photosPicker(
            isPresented: $isChoosingHero,
            selection: $heroItem,
            matching: .images,
            preferredItemEncoding: .current
        )
        .photosPicker(
            isPresented: $isChoosingSources,
            selection: $sourceItems,
            maxSelectionCount: 1_000,
            matching: .images,
            preferredItemEncoding: .current
        )
        .task(id: heroItem) {
            guard let heroItem else { return }
            do {
                let previousHero = session.workflow.project.hero
                let references = try await importItems([heroItem])
                if let reference = references.first {
                    await session.selectHero(reference)
                }
                if let previousHero, previousHero.origin == .photoPicker {
                    await assetStore.discardCachedAssets([previousHero])
                }
                pendingRetry = nil
                importMessage = nil
            } catch let error as PhotoSelectionError where error == .selectionCancelled {
                pendingRetry = nil
                importMessage = nil
            } catch let error as PhotoSelectionError {
                pendingRetry = PhotoImportRetryPolicy().shouldOfferRetry(for: error) ? .hero(heroItem) : nil
                importMessage = message(for: error, selectionName: "hero photo")
            } catch {
                pendingRetry = .hero(heroItem)
                importMessage = "The selected hero photo could not be imported. Please try again."
            }
            self.heroItem = nil
        }
        .task(id: sourceItems) {
            guard !sourceItems.isEmpty else { return }
            var importedReferences: [AssetReference] = []
            do {
                importedReferences = try await importItems(sourceItems)
                if session.workflow.step == .sourceReview {
                    try await session.addSources(importedReferences)
                } else {
                    await session.reviewSources(importedReferences)
                }
                pendingRetry = nil
                importMessage = nil
            } catch let error as PhotoSelectionError where error == .selectionCancelled {
                await assetStore.discardCachedAssets(importedReferences)
                pendingRetry = nil
                importMessage = nil
            } catch let error as PhotoSelectionError {
                await assetStore.discardCachedAssets(importedReferences)
                pendingRetry = PhotoImportRetryPolicy().shouldOfferRetry(for: error) ? .sources(sourceItems) : nil
                importMessage = message(for: error, selectionName: "photo")
            } catch {
                await assetStore.discardCachedAssets(importedReferences)
                pendingRetry = .sources(sourceItems)
                importMessage = "One or more selected photos could not be imported. Please try again."
            }
            sourceItems = []
        }
        .overlay(alignment: .bottom) {
            if let importProgress {
                VStack(spacing: 8) {
                    ProgressView(value: importProgress.fractionCompleted)
                        .frame(maxWidth: 280)
                    Text(importProgressDescription(importProgress))
                        .font(.footnote)
                    Button("Cancel import", role: .cancel, action: cancelImport)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importing photos")
                .accessibilityValue(importProgressDescription(importProgress))
            } else if let importMessage {
                VStack(spacing: 8) {
                    Text(importMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    if pendingRetry != nil {
                        Button("Retry import", action: retryImport)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Notice: \(importMessage)")
            }
        }
    }

    private func importItems(_ items: [PhotosPickerItem]) async throws -> [AssetReference] {
        defer { importProgress = nil }
        let references = try await assetStore.importSelection(items) { progress in
            await MainActor.run {
                importProgress = progress
            }
        }
        do {
            try Task.checkCancellation()
            return references
        } catch {
            await assetStore.discardCachedAssets(references)
            throw PhotoSelectionError.selectionCancelled
        }
    }

    private func importProgressDescription(_ progress: PhotoImportProgress) -> String {
        if let itemNumber = progress.currentItemNumber,
           let percentage = progress.currentItemPercentage {
            return "Loading photo \(itemNumber) of \(progress.totalCount) — \(percentage)%"
        }
        return "Imported \(progress.completedCount) of \(progress.totalCount) photos"
    }

    private func cancelImport() {
        heroItem = nil
        sourceItems = []
        pendingRetry = nil
        importMessage = nil
    }

    private func beginHeroSelection() {
        pendingRetry = nil
        importMessage = nil
        isChoosingHero = true
    }

    private func beginSourceSelection() {
        pendingRetry = nil
        importMessage = nil
        isChoosingSources = true
    }

    private func retryImport() {
        let retry = pendingRetry
        pendingRetry = nil
        importMessage = nil
        switch retry {
        case .hero(let item):
            heroItem = item
        case .sources(let items):
            sourceItems = items
        case nil:
            break
        }
    }

    private func message(for error: PhotoSelectionError, selectionName: String) -> String {
        switch error {
        case .unsupportedFormat:
            return "The selected \(selectionName) is not in a supported image format. Choose another and try again."
        case .invalidDimensions:
            return "The selected \(selectionName) has invalid dimensions. Choose another and try again."
        case .imageTooLarge:
            return "The selected \(selectionName) is too large to process safely. Choose a smaller image and try again."
        case .assetUnavailable:
            return "The selected \(selectionName) is unavailable. Choose another and try again."
        case .iCloudDownloadFailed:
            return "The selected \(selectionName) could not be downloaded from iCloud. Check your connection and retry."
        case .permissionDenied:
            return "Photo access was denied. Selected photos can be chosen without full-library access."
        case .selectionCancelled:
            return ""
        case .transferFailed:
            return "The selected \(selectionName) could not be imported. Please try again."
        }
    }
}
#endif
