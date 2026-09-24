import Foundation
import MosaicPersistence

public struct MosaicAppEnvironment: Sendable {
    public let projectStore: JSONProjectStore
    public let assetStore: PhotosPickerAssetStore
    public let previewCache: JSONPreviewAssignmentCache
    public let previewGenerator: CachedPreviewAssignmentGenerator

    public init(applicationSupportDirectory: URL) {
        let root = applicationSupportDirectory.appendingPathComponent("MosaicMemories", isDirectory: true)
        projectStore = JSONProjectStore(directory: root.appendingPathComponent("Projects", isDirectory: true))
        assetStore = PhotosPickerAssetStore(directory: root.appendingPathComponent("SelectedPhotos", isDirectory: true))
        let previewCache = JSONPreviewAssignmentCache(
            directory: root.appendingPathComponent("PreviewAssignments", isDirectory: true)
        )
        self.previewCache = previewCache
        previewGenerator = CachedPreviewAssignmentGenerator(cache: previewCache)
    }

    public static func production(fileManager: FileManager = .default) -> MosaicAppEnvironment {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return MosaicAppEnvironment(applicationSupportDirectory: applicationSupport)
    }
}
