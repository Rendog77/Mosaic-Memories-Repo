import Foundation
import MosaicPersistence

public struct MosaicAppEnvironment: Sendable {
    public let projectStore: JSONProjectStore
    public let assetStore: PhotosPickerAssetStore

    public init(applicationSupportDirectory: URL) {
        let root = applicationSupportDirectory.appendingPathComponent("MosaicMemories", isDirectory: true)
        projectStore = JSONProjectStore(directory: root.appendingPathComponent("Projects", isDirectory: true))
        assetStore = PhotosPickerAssetStore(directory: root.appendingPathComponent("SelectedPhotos", isDirectory: true))
    }

    public static func production(fileManager: FileManager = .default) -> MosaicAppEnvironment {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return MosaicAppEnvironment(applicationSupportDirectory: applicationSupport)
    }
}
