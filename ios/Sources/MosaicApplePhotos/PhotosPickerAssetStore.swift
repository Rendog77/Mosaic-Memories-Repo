import Foundation
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers

public actor PhotosPickerAssetStore: PhotoAssetLoading {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func registerImportedData(_ data: Data) throws -> AssetReference {
        guard !data.isEmpty else {
            throw PhotoSelectionError.assetUnavailable("selected-photo")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        try data.write(to: fileURL(for: identifier), options: .atomic)
        return AssetReference(id: identifier, origin: .photoPicker)
    }

    public func registerImportedData(_ items: [Data]) throws -> [AssetReference] {
        var references: [AssetReference] = []
        do {
            for data in items {
                references.append(try registerImportedData(data))
            }
            return references
        } catch {
            for reference in references {
                try? removeCachedAsset(reference)
            }
            throw error
        }
    }

    public func thumbnail(for reference: AssetReference, maximumPixelSize: Int) throws -> Data {
        guard
            reference.origin == .photoPicker,
            UUID(uuidString: reference.id) != nil,
            maximumPixelSize > 0
        else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        let url = fileURL(for: reference.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        return try Self.downsample(data: Data(contentsOf: url), maximumPixelSize: maximumPixelSize)
    }

    public func removeCachedAsset(_ reference: AssetReference) throws {
        guard UUID(uuidString: reference.id) != nil else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        let url = fileURL(for: reference.id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for identifier: String) -> URL {
        directory.appendingPathComponent(identifier).appendingPathExtension("asset")
    }

    private static func downsample(data: Data, maximumPixelSize: Int) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                ] as CFDictionary
            )
        else {
            throw PhotoSelectionError.assetUnavailable("thumbnail-decode")
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoSelectionError.assetUnavailable("thumbnail-encode")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoSelectionError.assetUnavailable("thumbnail-encode")
        }
        return output as Data
    }
}
