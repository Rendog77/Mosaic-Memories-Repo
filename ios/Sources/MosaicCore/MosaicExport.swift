import Foundation

public enum MosaicExportFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
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

    public init(
        url: URL,
        format: MosaicExportFormat,
        width: Int,
        height: Int,
        bytesWritten: Int,
        pixelsPerInch: Int
    ) {
        self.url = url
        self.format = format
        self.width = width
        self.height = height
        self.bytesWritten = bytesWritten
        self.pixelsPerInch = pixelsPerInch
    }

    public var printWidthInches: Double { Double(width) / Double(pixelsPerInch) }
    public var printHeightInches: Double { Double(height) / Double(pixelsPerInch) }
}

public enum MosaicExportError: Error, Equatable, Sendable {
    case invalidPolicy
    case assignmentDoesNotMatchProject
    case insufficientStorage(required: Int64, available: Int64)
    case imageDecodeFailed
    case rasterizationFailed
    case encodingFailed
    case writeFailed
}
