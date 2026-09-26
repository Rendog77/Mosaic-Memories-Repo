import Foundation
import MosaicPersistence

public struct MosaicAppEnvironment: Sendable {
    public let projectStore: JSONProjectStore
    public let assetStore: PhotosPickerAssetStore
    public let previewCache: JSONPreviewAssignmentCache
    public let previewGenerator: CachedPreviewAssignmentGenerator
    public let previewService: ApplePhotoPreviewAssignmentService
    public let exportService: ApplePhotoMosaicExportService

    public init(applicationSupportDirectory: URL) {
        let root = applicationSupportDirectory.appendingPathComponent("MosaicMemories", isDirectory: true)
        projectStore = JSONProjectStore(directory: root.appendingPathComponent("Projects", isDirectory: true))
        let assetStore = PhotosPickerAssetStore(
            directory: root.appendingPathComponent("SelectedPhotos", isDirectory: true)
        )
        self.assetStore = assetStore
        let previewCache = JSONPreviewAssignmentCache(
            directory: root.appendingPathComponent("PreviewAssignments", isDirectory: true)
        )
        self.previewCache = previewCache
        let previewGenerator = CachedPreviewAssignmentGenerator(cache: previewCache)
        self.previewGenerator = previewGenerator
        previewService = ApplePhotoPreviewAssignmentService(
            loader: assetStore,
            generator: previewGenerator
        )
        exportService = ApplePhotoMosaicExportService(loader: assetStore)
    }

    public static func production(fileManager: FileManager = .default) -> MosaicAppEnvironment {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return MosaicAppEnvironment(applicationSupportDirectory: applicationSupport)
    }
}
