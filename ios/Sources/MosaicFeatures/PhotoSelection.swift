import Foundation
import MosaicCore

public enum PhotoAccessMode: String, Codable, Sendable {
    case selectedPhotos
    case smartLibrary
}

public struct SourceSelectionRequest: Equatable, Sendable {
    public let minimumCount: Int
    public let maximumCount: Int
    public let accessMode: PhotoAccessMode

    public init(minimumCount: Int = 100, maximumCount: Int = 1_000, accessMode: PhotoAccessMode = .selectedPhotos) {
        precondition(minimumCount >= 0)
        precondition(maximumCount >= minimumCount)
        self.minimumCount = minimumCount
        self.maximumCount = maximumCount
        self.accessMode = accessMode
    }
}

public protocol HeroPhotoSelecting: Sendable {
    func selectHero() async throws -> AssetReference?
}

public protocol SourcePhotosSelecting: Sendable {
    func selectSources(request: SourceSelectionRequest) async throws -> [AssetReference]
}

public protocol PhotoAssetLoading: Sendable {
    func thumbnail(for reference: AssetReference, maximumPixelSize: Int) async throws -> Data
    func thumbnail(for reference: AssetReference, maximumPixelSize: Int, crop: HeroCrop?) async throws -> Data
}

public extension PhotoAssetLoading {
    func thumbnail(for reference: AssetReference, maximumPixelSize: Int, crop: HeroCrop?) async throws -> Data {
        try await thumbnail(for: reference, maximumPixelSize: maximumPixelSize)
    }
}

public enum PhotoSelectionError: Error, Equatable, Sendable {
    case permissionDenied
    case selectionCancelled
    case assetUnavailable(String)
    case iCloudDownloadFailed(String)
    case transferFailed(String)
    case unsupportedFormat(String)
    case invalidDimensions(String)
    case imageTooLarge(String)
}

public struct UnavailablePhotoSelector: HeroPhotoSelecting, SourcePhotosSelecting {
    public init() {}

    public func selectHero() async throws -> AssetReference? {
        throw PhotoSelectionError.assetUnavailable("Photo picker is not connected")
    }

    public func selectSources(request: SourceSelectionRequest) async throws -> [AssetReference] {
        throw PhotoSelectionError.assetUnavailable("Photo picker is not connected")
    }
}

public struct UnavailablePhotoAssetLoader: PhotoAssetLoading {
    public init() {}

    public func thumbnail(for reference: AssetReference, maximumPixelSize: Int) async throws -> Data {
        throw PhotoSelectionError.assetUnavailable(reference.id)
    }
}
