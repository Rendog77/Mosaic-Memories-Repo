import MosaicCore
import MosaicFeatures
import MosaicPersistence
import SwiftUI

public struct MosaicRootView: View {
    private let store: any ProjectStoring
    private let heroSelector: any HeroPhotoSelecting
    private let sourceSelector: any SourcePhotosSelecting
    private let assetLoader: any PhotoAssetLoading
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(
        store: any ProjectStoring,
        heroSelector: any HeroPhotoSelecting = UnavailablePhotoSelector(),
        sourceSelector: any SourcePhotosSelecting = UnavailablePhotoSelector(),
        assetLoader: any PhotoAssetLoading = UnavailablePhotoAssetLoader()
    ) {
        self.store = store
        self.heroSelector = heroSelector
        self.sourceSelector = sourceSelector
        self.assetLoader = assetLoader
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                MosaicCreationView(session: creationSession, assetLoader: assetLoader, onClose: {
                    self.creationSession = nil
                    Task { await librarySession.refresh() }
                })
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
