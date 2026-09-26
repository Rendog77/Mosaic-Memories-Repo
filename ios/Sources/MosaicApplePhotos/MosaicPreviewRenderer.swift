import CoreGraphics
import Foundation
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers

public struct MosaicPreviewImage: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let columns: Int
    public let rows: Int

    public init(data: Data, width: Int, height: Int, columns: Int, rows: Int) {
        self.data = data
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
    }
}

public struct AppleMosaicPreviewRenderer: Sendable {
    public let maximumDimension: Int

    public init(maximumDimension: Int = 1_600) {
        precondition(maximumDimension > 0)
        self.maximumDimension = maximumDimension
    }

    public func render(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        loader: any PhotoAssetLoading,
        progress: @escaping @Sendable (MosaicProgress) -> Void = { _ in }
    ) async throws -> MosaicPreviewImage {
        let layout = try validate(project: project, assignment: assignment)
        let tilePixelSize = max(1, maximumDimension / max(layout.columns, layout.rows))
        let width = try multiplied(layout.columns, by: tilePixelSize)
        let height = try multiplied(layout.rows, by: tilePixelSize)
        let sourceMaximumPixelSize = try multiplied(tilePixelSize, by: 2)
        let sources = Array(Set(assignment.tiles.map(\.source))).sorted {
            sourceKey($0) < sourceKey($1)
        }
        let total = 2 + sources.count + assignment.tiles.count
        progress(.init(completed: 0, total: total))

        try Task.checkCancellation()
        let heroData = try await loader.thumbnail(
            for: layout.hero,
            maximumPixelSize: maximumDimension,
            crop: project.heroCrop
        )
        let heroImage = try decode(heroData)
        progress(.init(completed: 1, total: total))

        var sourceImages: [AssetReference: CGImage] = [:]
        sourceImages.reserveCapacity(sources.count)
        for (index, source) in sources.enumerated() {
            if index.isMultiple(of: 8) { await Task.yield() }
            try Task.checkCancellation()
            let data = try await loader.thumbnail(
                for: source,
                maximumPixelSize: sourceMaximumPixelSize
            )
            sourceImages[source] = try squareCrop(decode(data))
            progress(.init(completed: index + 2, total: total))
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MosaicPreviewRenderingError.rasterizationFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let orderedTiles = assignment.tiles.sorted {
            ($0.coordinate.row, $0.coordinate.column) <
                ($1.coordinate.row, $1.coordinate.column)
        }
        for (index, tile) in orderedTiles.enumerated() {
            if index.isMultiple(of: 32) { await Task.yield() }
            try Task.checkCancellation()
            guard let sourceImage = sourceImages[tile.source] else {
                throw MosaicPreviewRenderingError.missingSourceImage(tile.source.id)
            }
            let rectangle = CGRect(
                x: tile.coordinate.column * tilePixelSize,
                y: tile.coordinate.row * tilePixelSize,
                width: tilePixelSize,
                height: tilePixelSize
            )
            context.draw(sourceImage, in: rectangle)
            progress(.init(completed: sources.count + index + 2, total: total))
        }

        if project.recipe.likeness > 0 {
            context.saveGState()
            context.setAlpha(CGFloat(project.recipe.likeness))
            context.draw(heroImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
        }
        try Task.checkCancellation()
        guard let image = context.makeImage() else {
            throw MosaicPreviewRenderingError.rasterizationFailed
        }
        let data = try encodePNG(image)
        progress(.init(completed: total, total: total))
        return .init(
            data: data,
            width: width,
            height: height,
            columns: layout.columns,
            rows: layout.rows
        )
    }

    private func validate(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment
    ) throws -> (hero: AssetReference, columns: Int, rows: Int) {
        guard let hero = project.hero else {
            throw MosaicPreviewRenderingError.missingHero
        }
        guard project.sourcesConfirmed,
              project.recipe.columns > 0,
              project.recipe.likeness.isFinite,
              (0...1).contains(project.recipe.likeness) else {
            throw MosaicPreviewRenderingError.invalidRecipe
        }
        let permittedSources = Set(project.sources)
        guard assignment.engineVersion == project.recipe.engineVersion,
              !assignment.tiles.isEmpty,
              assignment.tiles.allSatisfy({ permittedSources.contains($0.source) }),
              assignment.tiles.allSatisfy({
                  $0.coordinate.column >= 0 && $0.coordinate.row >= 0
              }) else {
            throw MosaicPreviewRenderingError.assignmentDoesNotMatchProject
        }
        let columns = try incremented(assignment.tiles.map(\.coordinate.column).max()!)
        let rows = try incremented(assignment.tiles.map(\.coordinate.row).max()!)
        let coordinates = Set(assignment.tiles.map(\.coordinate))
        let expectedTileCount = try multiplied(columns, by: rows)
        guard columns == project.recipe.columns,
              max(columns, rows) <= maximumDimension,
              coordinates.count == assignment.tiles.count,
              expectedTileCount == assignment.tiles.count else {
            throw MosaicPreviewRenderingError.assignmentDoesNotMatchProject
        }
        return (hero, columns, rows)
    }

    private func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                  ] as CFDictionary
              ) else {
            throw MosaicPreviewRenderingError.imageDecodeFailed
        }
        return image
    }

    private func squareCrop(_ image: CGImage) throws -> CGImage {
        let side = min(image.width, image.height)
        let rectangle = CGRect(
            x: CGFloat(image.width - side) / 2,
            y: CGFloat(image.height - side) / 2,
            width: CGFloat(side),
            height: CGFloat(side)
        )
        guard let cropped = image.cropping(to: rectangle) else {
            throw MosaicPreviewRenderingError.rasterizationFailed
        }
        return cropped
    }

    private func encodePNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw MosaicPreviewRenderingError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MosaicPreviewRenderingError.encodingFailed
        }
        return output as Data
    }

    private func multiplied(_ lhs: Int, by rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw MosaicPreviewRenderingError.invalidRecipe }
        return value
    }

    private func incremented(_ value: Int) throws -> Int {
        let (result, overflow) = value.addingReportingOverflow(1)
        guard !overflow else {
            throw MosaicPreviewRenderingError.assignmentDoesNotMatchProject
        }
        return result
    }

    private func sourceKey(_ reference: AssetReference) -> String {
        "\(reference.origin.rawValue):\(reference.id)"
    }
}

public enum MosaicPreviewRenderingError: Error, Equatable, Sendable {
    case missingHero
    case invalidRecipe
    case assignmentDoesNotMatchProject
    case imageDecodeFailed
    case missingSourceImage(String)
    case rasterizationFailed
    case encodingFailed
}
