import Foundation
import CoreGraphics
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers

public actor PhotosPickerAssetStore: PhotoAssetLoading {
    private let directory: URL
    private let validationPolicy: PhotoImportValidationPolicy

    public init(
        directory: URL,
        validationPolicy: PhotoImportValidationPolicy = .init()
    ) {
        self.directory = directory
        self.validationPolicy = validationPolicy
    }

    public func registerImportedData(
        _ data: Data,
        sourceIdentifier: String = "selected-photo"
    ) throws -> AssetReference {
        guard !data.isEmpty else {
            throw PhotoSelectionError.assetUnavailable(sourceIdentifier)
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else {
            throw PhotoSelectionError.unsupportedFormat(sourceIdentifier)
        }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            throw PhotoSelectionError.invalidDimensions(sourceIdentifier)
        }
        try validationPolicy.validate(width: width, height: height, identifier: sourceIdentifier)
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
        try thumbnail(for: reference, maximumPixelSize: maximumPixelSize, crop: nil)
    }

    public func thumbnail(
        for reference: AssetReference,
        maximumPixelSize: Int,
        crop: HeroCrop?
    ) throws -> Data {
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
        return try Self.downsample(data: Data(contentsOf: url), maximumPixelSize: maximumPixelSize, crop: crop)
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

    public func discardCachedAssets(_ references: [AssetReference]) {
        for reference in references where reference.origin == .photoPicker {
            try? removeCachedAsset(reference)
        }
    }

    private func fileURL(for identifier: String) -> URL {
        directory.appendingPathComponent(identifier).appendingPathExtension("asset")
    }

    private static func downsample(data: Data, maximumPixelSize: Int, crop: HeroCrop?) throws -> Data {
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

        let renderedImage: CGImage
        if let crop {
            let left = min(image.width - 1, Int((Double(image.width) * crop.x).rounded(.down)))
            let top = min(image.height - 1, Int((Double(image.height) * crop.y).rounded(.down)))
            let right = min(image.width, Int((Double(image.width) * (crop.x + crop.width)).rounded(.up)))
            let bottom = min(image.height, Int((Double(image.height) * (crop.y + crop.height)).rounded(.up)))
            let rectangle = CGRect(
                x: CGFloat(left),
                y: CGFloat(top),
                width: CGFloat(max(1, right - left)),
                height: CGFloat(max(1, bottom - top))
            )
            guard let cropped = image.cropping(to: rectangle),
                  cropped.width == Int(rectangle.width),
                  cropped.height == Int(rectangle.height) else {
                throw PhotoSelectionError.assetUnavailable("thumbnail-crop")
            }
            guard let context = CGContext(
                data: nil,
                width: cropped.width,
                height: cropped.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw PhotoSelectionError.assetUnavailable("thumbnail-crop")
            }
            context.draw(
                cropped,
                in: CGRect(x: 0, y: 0, width: CGFloat(cropped.width), height: CGFloat(cropped.height))
            )
            guard let rasterized = context.makeImage() else {
                throw PhotoSelectionError.assetUnavailable("thumbnail-crop")
            }
            renderedImage = rasterized
        } else {
            renderedImage = image
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
        CGImageDestinationAddImage(destination, renderedImage, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoSelectionError.assetUnavailable("thumbnail-encode")
        }
        return output as Data
    }
}
