import MosaicCore
import MosaicFeatures
import MosaicPersistence
import SwiftUI

public struct MosaicRootView: View {
    private let store: any ProjectStoring
    private let heroSelector: any HeroPhotoSelecting
    private let sourceSelector: any SourcePhotosSelecting
    private let assetLoader: any PhotoAssetLoading
    private let previewGenerator: any MosaicPreviewGenerating
    private let exporter: any MosaicExporting
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(
        store: any ProjectStoring,
        heroSelector: any HeroPhotoSelecting = UnavailablePhotoSelector(),
        sourceSelector: any SourcePhotosSelecting = UnavailablePhotoSelector(),
        assetLoader: any PhotoAssetLoading = UnavailablePhotoAssetLoader(),
        previewGenerator: any MosaicPreviewGenerating = UnavailableMosaicPreviewGenerator(),
        exporter: any MosaicExporting = UnavailableMosaicExporter()
    ) {
        self.store = store
        self.heroSelector = heroSelector
        self.sourceSelector = sourceSelector
        self.assetLoader = assetLoader
        self.previewGenerator = previewGenerator
        self.exporter = exporter
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                MosaicCreationView(
                    session: creationSession,
                    assetLoader: assetLoader,
                    previewGenerator: previewGenerator,
                    exporter: exporter,
                    onClose: {
                        self.creationSession = nil
                        Task { await librarySession.refresh() }
                    }
                )
            } else {
                ProjectLibraryView(
                    session: librarySession,
                    onNewProject: {
                        creationSession = CreationSession(
                            store: store,
                            heroSelector: heroSelector,
                            sourceSelector: sourceSelector
                        )
                    },
                    onContinueProject: { project in
                        creationSession = CreationSession(
                            store: store,
                            heroSelector: heroSelector,
                            sourceSelector: sourceSelector,
                            project: project
                        )
                    }
                )
            }
        }
    }
}
