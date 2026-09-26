import CoreGraphics
import Foundation
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers

public enum MosaicExportFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)
}

public struct MosaicExportPolicy: Equatable, Sendable {
    public static let maximumLongEdgePixels = 12_000

    public let format: MosaicExportFormat
    public let longEdgePixels: Int
    public let pixelsPerInch: Int

    public init(
        format: MosaicExportFormat,
        longEdgePixels: Int = 6_000,
        pixelsPerInch: Int = 300
    ) throws {
        guard longEdgePixels > 0,
              longEdgePixels <= Self.maximumLongEdgePixels,
              (72...600).contains(pixelsPerInch) else {
            throw MosaicExportError.invalidPolicy
        }
        if case .jpeg(let quality) = format {
            guard quality.isFinite, (0...1).contains(quality) else {
                throw MosaicExportError.invalidPolicy
            }
        }
        self.format = format
        self.longEdgePixels = longEdgePixels
        self.pixelsPerInch = pixelsPerInch
    }
}

public struct MosaicExportResult: Equatable, Sendable {
    public let url: URL
    public let format: MosaicExportFormat
    public let width: Int
    public let height: Int
    public let bytesWritten: Int
    public let pixelsPerInch: Int

    public var printWidthInches: Double { Double(width) / Double(pixelsPerInch) }
    public var printHeightInches: Double { Double(height) / Double(pixelsPerInch) }
}

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

    public init(
        storageChecker: any MosaicExportStorageChecking = FileSystemMosaicExportStorageChecker()
    ) {
        self.storageChecker = storageChecker
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
        let dimensions = try plannedDimensions(
            project: project,
            assignment: assignment,
            longEdgePixels: policy.longEdgePixels
        )
        let requiredCapacity = try estimatedRequiredCapacity(
            width: dimensions.width,
            height: dimensions.height
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

        let preview = try await AppleMosaicPreviewRenderer(
            maximumDimension: policy.longEdgePixels
        ).render(
            project: project,
            assignment: assignment,
            loader: loader,
            progress: progress
        )
        try Task.checkCancellation()
        guard preview.width == dimensions.width, preview.height == dimensions.height else {
            throw MosaicExportError.renderedDimensionsDoNotMatchPlan
        }

        let data: Data
        switch policy.format {
        case .png:
            data = preview.data
        case .jpeg(let quality):
            data = try transcodeJPEG(
                preview.data,
                quality: quality,
                pixelsPerInch: policy.pixelsPerInch
            )
        }
        try Task.checkCancellation()
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw MosaicExportError.writeFailed
        }
        return MosaicExportResult(
            url: destination,
            format: policy.format,
            width: preview.width,
            height: preview.height,
            bytesWritten: data.count,
            pixelsPerInch: policy.pixelsPerInch
        )
    }

    private func plannedDimensions(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        longEdgePixels: Int
    ) throws -> (width: Int, height: Int) {
        guard project.sourcesConfirmed,
              project.recipe.columns > 0,
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
        return (
            try multiplied(columns, by: tilePixelSize),
            try multiplied(rows, by: tilePixelSize)
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

    private func transcodeJPEG(
        _ pngData: Data,
        quality: Double,
        pixelsPerInch: Int
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MosaicExportError.encodingFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MosaicExportError.encodingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: pixelsPerInch,
            kCGImagePropertyDPIHeight: pixelsPerInch,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MosaicExportError.encodingFailed
        }
        return output as Data
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

public enum MosaicExportError: Error, Equatable, Sendable {
    case invalidPolicy
    case assignmentDoesNotMatchProject
    case insufficientStorage(required: Int64, available: Int64)
    case renderedDimensionsDoNotMatchPlan
    case encodingFailed
    case writeFailed
}
