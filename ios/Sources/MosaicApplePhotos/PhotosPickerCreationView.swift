#if os(iOS)
import Foundation
import MosaicAppUI
import MosaicFeatures
import PhotosUI
import SwiftUI

extension PhotosPickerAssetStore {
    public func importSelection(_ items: [PhotosPickerItem]) async throws -> [AssetReference] {
        var importedData: [Data] = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoSelectionError.assetUnavailable(item.itemIdentifier ?? "selected-photo")
                }
                importedData.append(data)
            } catch let error as PhotoSelectionError {
                throw error
            } catch {
                throw PhotoSelectionError.transferFailed(item.itemIdentifier ?? "selected-photo")
            }
        }
        return try registerImportedData(importedData)
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
            onClose: onClose
        )
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
                let references = try await assetStore.importSelection([heroItem])
                if let reference = references.first {
                    await session.selectHero(reference)
                }
                importMessage = nil
            } catch {
                importMessage = "The selected hero photo could not be imported. Please try again."
            }
            self.heroItem = nil
        }
        .task(id: sourceItems) {
            guard !sourceItems.isEmpty else { return }
            do {
                let references = try await assetStore.importSelection(sourceItems)
                if session.workflow.step == .sourceReview {
                    try await session.addSources(references)
                } else {
                    await session.reviewSources(references)
                }
                importMessage = nil
            } catch {
                importMessage = "One or more selected photos could not be imported. Please try again."
            }
            sourceItems = []
        }
        .overlay(alignment: .bottom) {
            if let importMessage {
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
}
#endif
