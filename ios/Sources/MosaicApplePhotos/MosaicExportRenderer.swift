import CoreGraphics
import Darwin
import Foundation
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers

public protocol MosaicExportStorageChecking: Sendable {
    func availableCapacity(at destination: URL) throws -> Int64?
}

public struct FileSystemMosaicExportStorageChecker: MosaicExportStorageChecking {
    public init() {}

    public func availableCapacity(at destination: URL) throws -> Int64? {
        let parent = destination.deletingLastPathComponent()
        return try parent.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
    }
}

public struct AppleMosaicExportRenderer: Sendable {
    private let storageChecker: any MosaicExportStorageChecking
    private let sourceCacheLimit: Int

    public init(
        storageChecker: any MosaicExportStorageChecking = FileSystemMosaicExportStorageChecker(),
        sourceCacheLimit: Int = 32
    ) {
        precondition(sourceCacheLimit > 0)
        self.storageChecker = storageChecker
        self.sourceCacheLimit = sourceCacheLimit
    }

    public func export(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        loader: any PhotoAssetLoading,
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void = { _ in }
    ) async throws -> MosaicExportResult {
        try Task.checkCancellation()
        let layout = try plannedLayout(
            project: project,
            assignment: assignment,
            longEdgePixels: policy.longEdgePixels
        )
        let requiredCapacity = try estimatedRequiredCapacity(
            width: layout.width,
            height: layout.height
        )
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw MosaicExportError.writeFailed
        }
        if let availableCapacity = try storageChecker.availableCapacity(at: destination),
           availableCapacity < requiredCapacity {
            throw MosaicExportError.insufficientStorage(
                required: requiredCapacity,
                available: availableCapacity
            )
        }

        let rawURL = temporaryURL(beside: destination, suffix: "rgba")
        let encodedURL = temporaryURL(beside: destination, suffix: "encoded")
        defer {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: encodedURL)
        }
        let raster = try FileBackedExportRaster(
            url: rawURL,
            width: layout.width,
            height: layout.height
        )
        let total = layout.tiles.count + 2
        progress(.init(completed: 0, total: total))
        try await render(
            project: project,
            layout: layout,
            loader: loader,
            raster: raster,
            totalProgress: total,
            progress: progress
        )
        try Task.checkCancellation()
        try encode(
            raster: raster,
            policy: policy,
            to: encodedURL
        )
        try Task.checkCancellation()
        try publish(encodedURL, to: destination)
        progress(.init(completed: total, total: total))
        let bytesWritten = try fileSize(at: destination)
        return MosaicExportResult(
            url: destination,
            format: policy.format,
            width: layout.width,
            height: layout.height,
            bytesWritten: bytesWritten,
            pixelsPerInch: policy.pixelsPerInch
        )
    }

    private func plannedLayout(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        longEdgePixels: Int
    ) throws -> ExportLayout {
        guard let hero = project.hero,
              project.sourcesConfirmed,
              project.recipe.columns > 0,
              project.recipe.likeness.isFinite,
              (0...1).contains(project.recipe.likeness),
              assignment.engineVersion == project.recipe.engineVersion,
              !assignment.tiles.isEmpty else {
            throw MosaicExportError.assignmentDoesNotMatchProject
        }
        let permittedSources = Set(project.sources)
        let columns = try incremented(assignment.tiles.map(\.coordinate.column).max()!)
        let rows = try incremented(assignment.tiles.map(\.coordinate.row).max()!)
        let coordinates = Set(assignment.tiles.map(\.coordinate))
        let expectedTileCount = try multiplied(columns, by: rows)
        guard columns == project.recipe.columns,
              max(columns, rows) <= longEdgePixels,
              coordinates.count == assignment.tiles.count,
              expectedTileCount == assignment.tiles.count,
              assignment.tiles.allSatisfy({
                  $0.coordinate.column >= 0 && $0.coordinate.row >= 0 &&
                      permittedSources.contains($0.source)
              }) else {
            throw MosaicExportError.assignmentDoesNotMatchProject
        }
        let tilePixelSize = max(1, longEdgePixels / max(columns, rows))
        return ExportLayout(
            hero: hero,
            tilePixelSize: tilePixelSize,
            width: try multiplied(columns, by: tilePixelSize),
            height: try multiplied(rows, by: tilePixelSize),
            tiles: assignment.tiles.sorted {
                ($0.coordinate.row, $0.coordinate.column) <
                    ($1.coordinate.row, $1.coordinate.column)
            }
        )
    }

    private func estimatedRequiredCapacity(width: Int, height: Int) throws -> Int64 {
        let pixels = try multiplied(width, by: height)
        let bytes = try multiplied(pixels, by: 8)
        let overhead = 16 * 1_024 * 1_024
        let (required, overflow) = Int64(bytes).addingReportingOverflow(Int64(overhead))
        guard !overflow else { throw MosaicExportError.invalidPolicy }
        return required
    }

    private func render(
        project: MosaicProject,
        layout: ExportLayout,
        loader: any PhotoAssetLoading,
        raster: FileBackedExportRaster,
        totalProgress: Int,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws {
        try Task.checkCancellation()
        let heroData = try await loader.thumbnail(
            for: layout.hero,
            maximumPixelSize: max(layout.width, layout.height),
            crop: project.heroCrop
        )
        let heroImage = try decode(
            heroData,
            maximumPixelSize: max(layout.width, layout.height)
        )
        progress(.init(completed: 1, total: totalProgress))

        let context = raster.context
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        context.translateBy(x: 0, y: CGFloat(layout.height))
        context.scaleBy(x: 1, y: -1)

        var sourceImages: [AssetReference: CGImage] = [:]
        var sourceOrder: [AssetReference] = []
        let sourceMaximumPixelSize = try multiplied(layout.tilePixelSize, by: 2)
        for (index, tile) in layout.tiles.enumerated() {
            if index.isMultiple(of: 8) { await Task.yield() }
            try Task.checkCancellation()
            let sourceImage: CGImage
            if let cached = sourceImages[tile.source] {
                sourceImage = cached
                sourceOrder.removeAll { $0 == tile.source }
                sourceOrder.append(tile.source)
            } else {
                let data = try await loader.thumbnail(
                    for: tile.source,
                    maximumPixelSize: sourceMaximumPixelSize
                )
                sourceImage = try squareCrop(
                    decode(data, maximumPixelSize: sourceMaximumPixelSize)
                )
                if sourceOrder.count == sourceCacheLimit,
                   let evicted = sourceOrder.first {
                    sourceOrder.removeFirst()
                    sourceImages[evicted] = nil
                }
                sourceImages[tile.source] = sourceImage
                sourceOrder.append(tile.source)
            }
            context.draw(
                sourceImage,
                in: CGRect(
                    x: tile.coordinate.column * layout.tilePixelSize,
                    y: tile.coordinate.row * layout.tilePixelSize,
                    width: layout.tilePixelSize,
                    height: layout.tilePixelSize
                )
            )
            progress(.init(completed: index + 2, total: totalProgress))
        }

        if project.recipe.likeness > 0 {
            context.saveGState()
            context.setAlpha(CGFloat(project.recipe.likeness))
            context.draw(
                heroImage,
                in: CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
            )
            context.restoreGState()
        }
    }

    private func encode(
        raster: FileBackedExportRaster,
        policy: MosaicExportPolicy,
        to url: URL
    ) throws {
        guard let image = raster.context.makeImage() else {
            throw MosaicExportError.encodingFailed
        }
        let type: UTType
        let quality: Double?
        switch policy.format {
        case .png:
            type = .png
            quality = nil
        case .jpeg(let value):
            type = .jpeg
            quality = value
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw MosaicExportError.encodingFailed
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: policy.pixelsPerInch,
            kCGImagePropertyDPIHeight: policy.pixelsPerInch,
        ]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MosaicExportError.encodingFailed
        }
    }

    private func decode(_ data: Data, maximumPixelSize: Int) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  ] as CFDictionary
              ) else {
            throw MosaicExportError.imageDecodeFailed
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
            throw MosaicExportError.rasterizationFailed
        }
        return cropped
    }

    private func publish(_ temporaryURL: URL, to destination: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: temporaryURL
                )
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            }
        } catch {
            throw MosaicExportError.writeFailed
        }
    }

    private func fileSize(at url: URL) throws -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else { throw MosaicExportError.writeFailed }
            return size
        } catch let error as MosaicExportError {
            throw error
        } catch {
            throw MosaicExportError.writeFailed
        }
    }

    private func temporaryURL(beside destination: URL, suffix: String) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".mosaic-\(UUID().uuidString).\(suffix)"
        )
    }

    private func multiplied(_ lhs: Int, by rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw MosaicExportError.invalidPolicy }
        return value
    }

    private func incremented(_ value: Int) throws -> Int {
        let (result, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw MosaicExportError.assignmentDoesNotMatchProject }
        return result
    }
}

private struct ExportLayout: Sendable {
    let hero: AssetReference
    let tilePixelSize: Int
    let width: Int
    let height: Int
    let tiles: [MosaicAssignedTile]
}

private final class FileBackedExportRaster: @unchecked Sendable {
    private var backingContext: CGContext?
    var context: CGContext { backingContext! }
    private let pointer: UnsafeMutableRawPointer
    private let byteCount: Int
    private let url: URL

    init(url: URL, width: Int, height: Int) throws {
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, countOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !countOverflow, byteCount > 0 else {
            throw MosaicExportError.invalidPolicy
        }
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw MosaicExportError.writeFailed }
        defer { Darwin.close(descriptor) }
        guard Darwin.ftruncate(descriptor, off_t(byteCount)) == 0 else {
            throw MosaicExportError.writeFailed
        }
        let pointer = Darwin.mmap(
            nil,
            byteCount,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            descriptor,
            0
        )
        guard pointer != MAP_FAILED, let pointer else {
            throw MosaicExportError.writeFailed
        }
        guard let context = CGContext(
            data: pointer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Darwin.munmap(pointer, byteCount)
            throw MosaicExportError.rasterizationFailed
        }
        self.backingContext = context
        self.pointer = pointer
        self.byteCount = byteCount
        self.url = url
    }

    deinit {
        backingContext = nil
        Darwin.munmap(pointer, byteCount)
        try? FileManager.default.removeItem(at: url)
    }
}
