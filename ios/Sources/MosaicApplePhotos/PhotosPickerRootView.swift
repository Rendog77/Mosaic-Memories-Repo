#if os(iOS)
import MosaicAppUI
import MosaicPersistence
import SwiftUI

public struct PhotosPickerRootView: View {
    private let store: any ProjectStoring
    private let assetStore: PhotosPickerAssetStore
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(store: any ProjectStoring, assetStore: PhotosPickerAssetStore) {
        self.store = store
        self.assetStore = assetStore
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                PhotosPickerCreationView(session: creationSession, assetStore: assetStore) {
                    self.creationSession = nil
                    Task { await librarySession.refresh() }
                }
            } else {
                ProjectLibraryView(
                    session: librarySession,
                    onNewProject: {
                        creationSession = CreationSession(store: store)
                    },
                    onContinueProject: { project in
                        creationSession = CreationSession(store: store, project: project)
                    }
                )
            }
        }
    }
}
#endif
