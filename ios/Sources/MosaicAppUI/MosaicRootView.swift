import MosaicCore
import MosaicPersistence
import SwiftUI

public struct MosaicRootView: View {
    private let store: any ProjectStoring
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(store: any ProjectStoring) {
        self.store = store
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                MosaicCreationView(session: creationSession) {
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

