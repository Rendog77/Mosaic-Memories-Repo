import CoreGraphics
import Foundation
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers
import XCTest
@testable import MosaicApplePhotos

private actor ReferenceExportLoader: PhotoAssetLoading {
    let dataByID: [String: Data]

    init(dataByID: [String: Data]) {
        self.dataByID = dataByID
    }

    func thumbnail(for reference: AssetReference, maximumPixelSize: Int) throws -> Data {
        guard let data = dataByID[reference.id] else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        return data
    }
}

final class MosaicReferenceExportTests: XCTestCase {
    func testTenReferenceExportsReopenAndMatchPreviewAssignments() async throws {
        let outputDirectory = referenceOutputDirectory()
        try? FileManager.default.removeItem(at: outputDirectory)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let cases = ReferenceCase.all
        XCTAssertEqual(cases.count, 10)
        var records: [ReferenceRecord] = []

        for (index, referenceCase) in cases.enumerated() {
            let fixture = try makeFixture(referenceCase, index: index)
            let preview = try await AppleMosaicPreviewRenderer(maximumDimension: 120).render(
                project: fixture.project,
                assignment: fixture.assignment,
                loader: fixture.loader
            )
            let destination = outputDirectory.appendingPathComponent(referenceCase.fileName)
            let policy = try MosaicExportPolicy(
                format: referenceCase.format,
                longEdgePixels: 240,
                pixelsPerInch: referenceCase.pixelsPerInch
            )
            let result = try await AppleMosaicExportRenderer().export(
                project: fixture.project,
                assignment: fixture.assignment,
                loader: fixture.loader,
                policy: policy,
                to: destination
            )

            let exportData = try Data(contentsOf: destination)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(exportData as CFData, nil))
            let reopened = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            XCTAssertEqual(CGImageSourceGetType(source) as String?, referenceCase.type.identifier)
            XCTAssertEqual(reopened.width, result.width)
            XCTAssertEqual(reopened.height, result.height)
            XCTAssertEqual(reopened.colorSpace?.model, .rgb)
            XCTAssertEqual(result.bytesWritten, exportData.count)
            let horizontalDPI = try XCTUnwrap(
                properties[kCGImagePropertyDPIWidth] as? NSNumber
            ).doubleValue
            let verticalDPI = try XCTUnwrap(
                properties[kCGImagePropertyDPIHeight] as? NSNumber
            ).doubleValue
            XCTAssertEqual(
                horizontalDPI,
                Double(referenceCase.pixelsPerInch),
                accuracy: 1
            )
            XCTAssertEqual(
                verticalDPI,
                Double(referenceCase.pixelsPerInch),
                accuracy: 1
            )

            let previewPixels = try rgbaPixels(
                data: preview.data,
                width: preview.width,
                height: preview.height
            )
            let exportPixels = try rgbaPixels(
                image: reopened,
                width: result.width,
                height: result.height
            )
            var maximumChannelDelta = 0
            for tile in fixture.assignment.tiles {
                let previewColor = sampledColor(
                    pixels: previewPixels,
                    width: preview.width,
                    height: preview.height,
                    columns: referenceCase.columns,
                    rows: referenceCase.rows,
                    coordinate: tile.coordinate
                )
                let exportColor = sampledColor(
                    pixels: exportPixels,
                    width: result.width,
                    height: result.height,
                    columns: referenceCase.columns,
                    rows: referenceCase.rows,
                    coordinate: tile.coordinate
                )
                maximumChannelDelta = max(
                    maximumChannelDelta,
                    zip(previewColor, exportColor).map { pair in
                        abs(Int(pair.0) - Int(pair.1))
                    }.max() ?? 0
                )
            }
            XCTAssertLessThanOrEqual(
                maximumChannelDelta,
                referenceCase.type == .png ? 4 : 40,
                "\(referenceCase.name) did not match its preview assignment"
            )
            records.append(
                .init(
                    name: referenceCase.name,
                    fileName: referenceCase.fileName,
                    format: referenceCase.type.identifier,
                    columns: referenceCase.columns,
                    rows: referenceCase.rows,
                    likeness: referenceCase.likeness,
                    width: result.width,
                    height: result.height,
                    pixelsPerInch: result.pixelsPerInch,
                    bytesWritten: result.bytesWritten,
                    maximumPreviewChannelDelta: maximumChannelDelta
                )
            )
        }

        let report = ReferenceReport(
            schemaVersion: 1,
            generatedAt: Date(),
            cases: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("reference-export-report.json"),
            options: .atomic
        )
        XCTAssertEqual(records.count, 10)
    }

    private func referenceOutputDirectory() -> URL {
        if let configured = ProcessInfo.processInfo.environment["MOSAIC_REFERENCE_EXPORT_DIR"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaicReferenceExports", isDirectory: true)
    }

    private func makeFixture(
        _ referenceCase: ReferenceCase,
        index: Int
    ) throws -> (
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        loader: ReferenceExportLoader
    ) {
        let palette: [(String, (UInt8, UInt8, UInt8, UInt8))] = [
            ("coral", (235, 72, 72, 255)),
            ("teal", (32, 170, 155, 255)),
            ("blue", (55, 105, 220, 255)),
            ("gold", (240, 184, 45, 255)),
            ("violet", (150, 75, 200, 255)),
        ]
        let hero = AssetReference(id: "reference-hero-\(index)", origin: .testFixture)
        let sources = palette.enumerated().map {
            AssetReference(id: "reference-\(index)-\($0.element.0)", origin: .testFixture)
        }
        let project = MosaicProject(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            title: referenceCase.name,
            hero: hero,
            sources: sources,
            sourcesConfirmed: true,
            recipe: .init(
                columns: referenceCase.columns,
                likeness: referenceCase.likeness,
                repeatWindow: 1
            )
        )
        var tiles: [MosaicAssignedTile] = []
        for row in 0..<referenceCase.rows {
            for column in 0..<referenceCase.columns {
                let sourceIndex = (row * referenceCase.columns + column + index) % sources.count
                tiles.append(
                    .init(
                        coordinate: .init(column: column, row: row),
                        source: sources[sourceIndex]
                    )
                )
            }
        }
        var dataByID: [String: Data] = [
            hero.id: try solidPNG(color: (118, 126, 134, 255)),
        ]
        for (source, color) in zip(sources, palette.map { $0.1 }) {
            dataByID[source.id] = try solidPNG(color: color)
        }
        return (
            project,
            .init(engineVersion: project.recipe.engineVersion, tiles: tiles),
            ReferenceExportLoader(dataByID: dataByID)
        )
    }

    private func solidPNG(color: (UInt8, UInt8, UInt8, UInt8)) throws -> Data {
        let width = 16
        let height = 16
        let bytes = Array(repeating: [color.0, color.1, color.2, color.3], count: width * height)
            .flatMap { $0 }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func rgbaPixels(data: Data, width: Int, height: Int) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try rgbaPixels(image: image, width: width, height: height)
    }

    private func rgbaPixels(image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw ReferenceExportError.pixelDecodeFailed }
        return pixels
    }

    private func sampledColor(
        pixels: [UInt8],
        width: Int,
        height: Int,
        columns: Int,
        rows: Int,
        coordinate: TileCoordinate
    ) -> [UInt8] {
        let x = min(width - 1, (coordinate.column * width / columns) + (width / columns / 2))
        let y = min(height - 1, (coordinate.row * height / rows) + (height / rows / 2))
        let offset = (y * width + x) * 4
        return Array(pixels[offset..<(offset + 3)])
    }
}

private struct ReferenceCase {
    let name: String
    let columns: Int
    let rows: Int
    let likeness: Double
    let format: MosaicExportFormat
    let pixelsPerInch: Int

    var type: UTType {
        switch format {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var fileName: String {
        "\(name).\(format.fileExtension)"
    }

    static let all: [ReferenceCase] = [
        .init(name: "01-square-png", columns: 1, rows: 1, likeness: 0, format: .png, pixelsPerInch: 300),
        .init(name: "02-landscape-png", columns: 3, rows: 2, likeness: 0.1, format: .png, pixelsPerInch: 240),
        .init(name: "03-portrait-png", columns: 2, rows: 3, likeness: 0.2, format: .png, pixelsPerInch: 360),
        .init(name: "04-wide-png", columns: 4, rows: 1, likeness: 0.15, format: .png, pixelsPerInch: 300),
        .init(name: "05-tall-png", columns: 1, rows: 4, likeness: 0.05, format: .png, pixelsPerInch: 200),
        .init(name: "06-square-jpeg", columns: 3, rows: 3, likeness: 0, format: .jpeg(quality: 0.9), pixelsPerInch: 300),
        .init(name: "07-landscape-jpeg", columns: 4, rows: 3, likeness: 0.1, format: .jpeg(quality: 0.88), pixelsPerInch: 240),
        .init(name: "08-portrait-jpeg", columns: 3, rows: 4, likeness: 0.2, format: .jpeg(quality: 0.92), pixelsPerInch: 360),
        .init(name: "09-banner-jpeg", columns: 5, rows: 2, likeness: 0.15, format: .jpeg(quality: 0.85), pixelsPerInch: 300),
        .init(name: "10-grid-jpeg", columns: 5, rows: 4, likeness: 0.05, format: .jpeg(quality: 0.95), pixelsPerInch: 300),
    ]
}

private struct ReferenceReport: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let cases: [ReferenceRecord]
}

private struct ReferenceRecord: Encodable {
    let name: String
    let fileName: String
    let format: String
    let columns: Int
    let rows: Int
    let likeness: Double
    let width: Int
    let height: Int
    let pixelsPerInch: Int
    let bytesWritten: Int
    let maximumPreviewChannelDelta: Int
}

private enum ReferenceExportError: Error {
    case pixelDecodeFailed
}
