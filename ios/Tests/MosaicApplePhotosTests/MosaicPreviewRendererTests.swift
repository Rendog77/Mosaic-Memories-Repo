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

final class MosaicPreviewRendererTests: XCTestCase {
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
