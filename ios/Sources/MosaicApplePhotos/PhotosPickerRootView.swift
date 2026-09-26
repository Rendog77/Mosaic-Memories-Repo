#if os(iOS)
import MosaicAppUI
import MosaicPersistence
import SwiftUI

public struct PhotosPickerRootView: View {
    private let store: any ProjectStoring
    private let assetStore: PhotosPickerAssetStore
    private let previewGenerator: any MosaicPreviewGenerating
    private let exporter: any MosaicExporting
    @StateObject private var librarySession: ProjectLibrarySession
    @State private var creationSession: CreationSession?

    public init(
        store: any ProjectStoring,
        assetStore: PhotosPickerAssetStore,
        previewGenerator: any MosaicPreviewGenerating = UnavailableMosaicPreviewGenerator(),
        exporter: any MosaicExporting = UnavailableMosaicExporter()
    ) {
        self.store = store
        self.assetStore = assetStore
        self.previewGenerator = previewGenerator
        self.exporter = exporter
        _librarySession = StateObject(wrappedValue: ProjectLibrarySession(store: store))
    }

    public var body: some View {
        Group {
            if let creationSession {
                PhotosPickerCreationView(
                    session: creationSession,
                    assetStore: assetStore,
                    previewGenerator: previewGenerator,
                    exporter: exporter
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
