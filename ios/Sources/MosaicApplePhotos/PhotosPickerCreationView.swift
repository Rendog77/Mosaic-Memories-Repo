#if os(iOS)
import Foundation
import MosaicAppUI
import MosaicCore
import MosaicFeatures
import PhotosUI
import SwiftUI

extension PhotosPickerAssetStore {
    public func importSelection(
        _ items: [PhotosPickerItem],
        onProgress: @Sendable (PhotoImportProgress) async -> Void = { _ in }
    ) async throws -> [AssetReference] {
        guard !items.isEmpty else { return [] }
        var references: [AssetReference] = []
        await onProgress(.init(completedCount: 0, totalCount: items.count))
        do {
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoSelectionError.assetUnavailable(item.itemIdentifier ?? "selected-photo")
                }
                try Task.checkCancellation()
                references.append(
                    try registerImportedData(
                        data,
                        sourceIdentifier: item.itemIdentifier ?? "selected-photo"
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
            throw PhotoSelectionError.transferFailed("selected-photo")
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
            onChooseHero: { isChoosingHero = true },
            onChooseSources: { isChoosingSources = true },
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
                importMessage = nil
            } catch let error as PhotoSelectionError where error == .selectionCancelled {
                importMessage = nil
            } catch let error as PhotoSelectionError {
                importMessage = message(for: error, selectionName: "hero photo")
            } catch {
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
                importMessage = nil
            } catch let error as PhotoSelectionError where error == .selectionCancelled {
                await assetStore.discardCachedAssets(importedReferences)
                importMessage = nil
            } catch let error as PhotoSelectionError {
                await assetStore.discardCachedAssets(importedReferences)
                importMessage = message(for: error, selectionName: "photo")
            } catch {
                await assetStore.discardCachedAssets(importedReferences)
                importMessage = "One or more selected photos could not be imported. Please try again."
            }
            sourceItems = []
        }
        .overlay(alignment: .bottom) {
            if let importProgress {
                VStack(spacing: 8) {
                    ProgressView(value: importProgress.fractionCompleted)
                        .frame(maxWidth: 280)
                    Text("Importing \(importProgress.completedCount) of \(importProgress.totalCount) photos")
                        .font(.footnote)
                    Button("Cancel import", role: .cancel, action: cancelImport)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importing photos")
                .accessibilityValue("\(importProgress.completedCount) of \(importProgress.totalCount)")
            } else if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.regularMaterial, in: Capsule())
                    .padding()
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

    private func cancelImport() {
        heroItem = nil
        sourceItems = []
        importMessage = nil
    }

    private func message(for error: PhotoSelectionError, selectionName: String) -> String {
        switch error {
        case .unsupportedFormat:
            return "The selected \(selectionName) is not in a supported image format. Choose another and try again."
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
