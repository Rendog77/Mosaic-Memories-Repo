import CoreGraphics
import Foundation
import ImageIO
import XCTest
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers
@testable import MosaicApplePhotos

private actor PreviewRendererLoaderStub: PhotoAssetLoading {
    private let dataByID: [String: Data]
    private var requestCounts: [String: Int] = [:]

    init(dataByID: [String: Data]) {
        self.dataByID = dataByID
    }

    func thumbnail(for reference: AssetReference, maximumPixelSize: Int) throws -> Data {
        requestCounts[reference.id, default: 0] += 1
        guard let data = dataByID[reference.id] else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        return data
    }

    func requestCount(for id: String) -> Int {
        requestCounts[id, default: 0]
    }

    func totalRequestCount() -> Int {
        requestCounts.values.reduce(0, +)
    }
}

private final class RenderProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MosaicProgress] = []

    func append(_ value: MosaicProgress) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [MosaicProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private struct ExportStorageCheckerStub: MosaicExportStorageChecking {
    let capacity: Int64?

    func availableCapacity(at destination: URL) throws -> Int64? {
        capacity
    }
}

final class MosaicPreviewRendererTests: XCTestCase {
    func testHighResolutionPNGExportReusesAssignmentAndWritesAtomically() async throws {
        let fixture = try makeExportFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("mosaic.png")
        let collector = RenderProgressCollector()
        let policy = try MosaicExportPolicy(
            format: .png,
            longEdgePixels: 20,
            pixelsPerInch: 200
        )

        let result = try await AppleMosaicExportRenderer(
            storageChecker: ExportStorageCheckerStub(capacity: Int64.max)
        ).export(
            project: fixture.project,
            assignment: fixture.assignment,
            loader: fixture.loader,
            policy: policy,
            to: destination
        ) { collector.append($0) }

        let data = try Data(contentsOf: destination)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(result.url, destination)
        XCTAssertEqual(result.format, .png)
        XCTAssertEqual(result.width, 20)
        XCTAssertEqual(result.height, 10)
        XCTAssertEqual(result.bytesWritten, data.count)
        XCTAssertEqual(result.printWidthInches, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(result.printHeightInches, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 10)
        XCTAssertEqual(collector.snapshot().last?.completed, collector.snapshot().last?.total)
        let heroRequests = await fixture.loader.requestCount(for: "export-hero")
        let redRequests = await fixture.loader.requestCount(for: "export-red")
        let blueRequests = await fixture.loader.requestCount(for: "export-blue")
        XCTAssertEqual(heroRequests, 1)
        XCTAssertEqual(redRequests, 1)
        XCTAssertEqual(blueRequests, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [
            "mosaic.png",
        ])
    }

    func testJPEGExportEmbedsPolicyAndProducesExpectedType() async throws {
        let fixture = try makeExportFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("mosaic.jpg")
        let policy = try MosaicExportPolicy(
            format: .jpeg(quality: 0.82),
            longEdgePixels: 24,
            pixelsPerInch: 300
        )

        let result = try await AppleMosaicExportRenderer(
            storageChecker: ExportStorageCheckerStub(capacity: Int64.max)
        ).export(
            project: fixture.project,
            assignment: fixture.assignment,
            loader: fixture.loader,
            policy: policy,
            to: destination
        )

        let data = try Data(contentsOf: destination)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let imageType = CGImageSourceGetType(imageSource) as String?
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(imageType, UTType.jpeg.identifier)
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
        XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.intValue, 300)
        XCTAssertEqual(result.format, .jpeg(quality: 0.82))
        XCTAssertEqual(result.width, 24)
        XCTAssertEqual(result.height, 12)
        XCTAssertGreaterThan(result.bytesWritten, 0)
    }

    func testExportRejectsInsufficientStorageBeforeLoadingAssets() async throws {
        let fixture = try makeExportFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("mosaic.png")
        let policy = try MosaicExportPolicy(format: .png, longEdgePixels: 20)

        do {
            _ = try await AppleMosaicExportRenderer(
                storageChecker: ExportStorageCheckerStub(capacity: 0)
            ).export(
                project: fixture.project,
                assignment: fixture.assignment,
                loader: fixture.loader,
                policy: policy,
                to: destination
            )
            XCTFail("Expected storage preflight failure")
        } catch let error as MosaicExportError {
            guard case .insufficientStorage(let required, let available) = error else {
                return XCTFail("Unexpected export error: \(error)")
            }
            XCTAssertGreaterThan(required, 0)
            XCTAssertEqual(available, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let requestCount = await fixture.loader.totalRequestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testCancelledExportDoesNotPublishDestination() async throws {
        let fixture = try makeExportFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("mosaic.png")
        let policy = try MosaicExportPolicy(format: .png, longEdgePixels: 20)
        let renderer = AppleMosaicExportRenderer(
            storageChecker: ExportStorageCheckerStub(capacity: Int64.max)
        )
        let task = Task {
            try await renderer.export(
                project: fixture.project,
                assignment: fixture.assignment,
                loader: fixture.loader,
                policy: policy,
                to: destination
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected export cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRendererCompositesAssignedTilesAtBoundedDimensions() async throws {
        let red = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])
        let blue = try makePNG(width: 1, height: 1, pixels: [(0, 0, 255, 255)])
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let redSource = AssetReference(id: "red", origin: .testFixture)
        let blueSource = AssetReference(id: "blue", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [redSource, blueSource],
            sourcesConfirmed: true,
            recipe: .init(columns: 2, likeness: 0, repeatWindow: 0)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [
                .init(coordinate: .init(column: 0, row: 0), source: redSource),
                .init(coordinate: .init(column: 1, row: 0), source: blueSource),
            ]
        )
        let loader = PreviewRendererLoaderStub(
            dataByID: ["hero": red, "red": red, "blue": blue]
        )

        let preview = try await AppleMosaicPreviewRenderer(maximumDimension: 4).render(
            project: project,
            assignment: assignment,
            loader: loader
        )
        let pixels = try rgbaPixels(preview.data, width: preview.width, height: preview.height)

        XCTAssertEqual(preview.width, 4)
        XCTAssertEqual(preview.height, 2)
        XCTAssertEqual(preview.columns, 2)
        XCTAssertEqual(preview.rows, 1)
        XCTAssertGreaterThan(pixels[0], 240)
        XCTAssertLessThan(pixels[2], 15)
        let rightPixel = (preview.width - 1) * 4
        XCTAssertLessThan(pixels[rightPixel], 15)
        XCTAssertGreaterThan(pixels[rightPixel + 2], 240)
    }

    func testRendererCenterCropsAndLoadsRepeatedSourceOnce() async throws {
        let wide = try makePNG(
            width: 3,
            height: 1,
            pixels: [(0, 0, 255, 255), (255, 0, 0, 255), (0, 0, 255, 255)]
        )
        let heroData = try makePNG(width: 2, height: 1, pixels: [
            (255, 255, 255, 255), (255, 255, 255, 255),
        ])
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let source = AssetReference(id: "source", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [source],
            sourcesConfirmed: true,
            recipe: .init(columns: 2, likeness: 0, repeatWindow: 0)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [
                .init(coordinate: .init(column: 0, row: 0), source: source),
                .init(coordinate: .init(column: 1, row: 0), source: source),
            ]
        )
        let loader = PreviewRendererLoaderStub(dataByID: ["hero": heroData, "source": wide])
        let collector = RenderProgressCollector()

        let preview = try await AppleMosaicPreviewRenderer(maximumDimension: 4).render(
            project: project,
            assignment: assignment,
            loader: loader
        ) { collector.append($0) }
        let pixels = try rgbaPixels(preview.data, width: preview.width, height: preview.height)
        let sourceRequests = await loader.requestCount(for: "source")

        XCTAssertEqual(sourceRequests, 1)
        XCTAssertGreaterThan(pixels[0], 240)
        XCTAssertLessThan(pixels[2], 15)
        XCTAssertEqual(collector.snapshot(), [
            .init(completed: 0, total: 5),
            .init(completed: 1, total: 5),
            .init(completed: 2, total: 5),
            .init(completed: 3, total: 5),
            .init(completed: 4, total: 5),
            .init(completed: 5, total: 5),
        ])
    }

    func testFullLikenessUsesHeroImage() async throws {
        let red = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])
        let blue = try makePNG(width: 1, height: 1, pixels: [(0, 0, 255, 255)])
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let source = AssetReference(id: "source", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [source],
            sourcesConfirmed: true,
            recipe: .init(columns: 1, likeness: 1, repeatWindow: 0)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [.init(coordinate: .init(column: 0, row: 0), source: source)]
        )
        let loader = PreviewRendererLoaderStub(dataByID: ["hero": red, "source": blue])

        let preview = try await AppleMosaicPreviewRenderer(maximumDimension: 2).render(
            project: project,
            assignment: assignment,
            loader: loader
        )
        let pixels = try rgbaPixels(preview.data, width: preview.width, height: preview.height)

        XCTAssertGreaterThan(pixels[0], 240)
        XCTAssertLessThan(pixels[2], 15)
    }

    func testIncompleteAssignmentIsRejectedBeforeLoadingAssets() async throws {
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let source = AssetReference(id: "source", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [source],
            sourcesConfirmed: true,
            recipe: .init(columns: 2, likeness: 0, repeatWindow: 0)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [.init(coordinate: .init(column: 1, row: 0), source: source)]
        )
        let loader = PreviewRendererLoaderStub(dataByID: [:])

        do {
            _ = try await AppleMosaicPreviewRenderer().render(
                project: project,
                assignment: assignment,
                loader: loader
            )
            XCTFail("Expected incomplete assignment rejection")
        } catch let error as MosaicPreviewRenderingError {
            XCTAssertEqual(error, .assignmentDoesNotMatchProject)
        }
    }

    private func makeExportFixture() throws -> (
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        loader: PreviewRendererLoaderStub
    ) {
        let red = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])
        let blue = try makePNG(width: 1, height: 1, pixels: [(0, 0, 255, 255)])
        let hero = AssetReference(id: "export-hero", origin: .testFixture)
        let redSource = AssetReference(id: "export-red", origin: .testFixture)
        let blueSource = AssetReference(id: "export-blue", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [redSource, blueSource],
            sourcesConfirmed: true,
            recipe: .init(columns: 2, likeness: 0.5, repeatWindow: 1)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [
                .init(coordinate: .init(column: 0, row: 0), source: redSource),
                .init(coordinate: .init(column: 1, row: 0), source: blueSource),
            ]
        )
        let loader = PreviewRendererLoaderStub(
            dataByID: [
                hero.id: red,
                redSource.id: red,
                blueSource.id: blue,
            ]
        )
        return (project, assignment, loader)
    }

    private func makePNG(
        width: Int,
        height: Int,
        pixels: [(UInt8, UInt8, UInt8, UInt8)]
    ) throws -> Data {
        XCTAssertEqual(pixels.count, width * height)
        let bytes = pixels.flatMap { [$0.0, $0.1, $0.2, $0.3] }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
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

    private func rgbaPixels(_ data: Data, width: Int, height: Int) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered)
        return pixels
    }
}
