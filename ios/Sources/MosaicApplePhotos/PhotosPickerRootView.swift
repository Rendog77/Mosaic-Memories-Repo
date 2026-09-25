#if os(iOS)
import MosaicAppUI
import MosaicPersistence
import SwiftUI

public struct PhotosPickerRootView: View {
    private let store: any ProjectStoring
    private let assetStore: PhotosPickerAssetStore
    private let previewGenerator: any MosaicPreviewGenerating
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(
        store: any ProjectStoring,
        assetStore: PhotosPickerAssetStore,
        previewGenerator: any MosaicPreviewGenerating = UnavailableMosaicPreviewGenerator()
    ) {
        self.store = store
        self.assetStore = assetStore
        self.previewGenerator = previewGenerator
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                PhotosPickerCreationView(
                    session: creationSession,
                    assetStore: assetStore,
                    previewGenerator: previewGenerator
                ) {
                    self.creationSession = nil
                    Task { await librarySession.refresh() }
                }
            } else {
                ProjectLibraryView(
                    session: librarySession,
                    onNewProject: {
                        creationSession = CreationSession(store: store, assetChecker: assetStore)
                    },
                    onContinueProject: { project in
                        creationSession = CreationSession(store: store, assetChecker: assetStore, project: project)
                    }
                )
            }
        }
    }
}
#endif
