import CoreGraphics
import Foundation
import ImageIO
import XCTest
import MosaicCore
import MosaicFeatures
import MosaicPersistence
import UniformTypeIdentifiers
@testable import MosaicApplePhotos

private actor DescriptorLoaderStub: PhotoAssetLoading {
    private let dataByID: [String: Data]
    private var cropRequests: [String: HeroCrop?] = [:]

    init(dataByID: [String: Data]) {
        self.dataByID = dataByID
    }

    func thumbnail(for reference: AssetReference, maximumPixelSize: Int) throws -> Data {
        guard let data = dataByID[reference.id] else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        return data
    }

    func thumbnail(
        for reference: AssetReference,
        maximumPixelSize: Int,
        crop: HeroCrop?
    ) throws -> Data {
        cropRequests[reference.id] = crop
        guard let data = dataByID[reference.id] else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        return data
    }

    func requestedCrop(for id: String) -> HeroCrop? {
        cropRequests[id] ?? nil
    }
}

private final class DescriptorProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MosaicProgress] = []

    func append(_ progress: MosaicProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshot() -> [MosaicProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class ImageDescriptorExtractorTests: XCTestCase {
    func testSolidRedProducesExpectedCIELABDescriptor() throws {
        let data = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])

        let result = try AppleImageDescriptorExtractor().sourceDescriptor(
            for: .init(id: "red", origin: .testFixture),
            imageData: data
        )

        XCTAssertEqual(result.descriptor.components[0], 53.24, accuracy: 0.6)
        XCTAssertEqual(result.descriptor.components[1], 80.09, accuracy: 0.6)
        XCTAssertEqual(result.descriptor.components[2], 67.20, accuracy: 0.6)
    }

    func testSourceDescriptorUsesSquareCenterCrop() throws {
        let data = try makePNG(
            width: 3,
            height: 1,
            pixels: [
                (0, 0, 255, 255),
                (255, 0, 0, 255),
                (0, 0, 255, 255),
            ]
        )

        let result = try AppleImageDescriptorExtractor(sourceSampleSize: 1).sourceDescriptor(
            for: .init(id: "center", origin: .testFixture),
            imageData: data
        )

        XCTAssertEqual(result.descriptor.components[1], 80.09, accuracy: 0.6)
    }

    func testHeroGridProducesRowMajorTargetDescriptors() throws {
        let data = try makePNG(
            width: 2,
            height: 1,
            pixels: [(255, 0, 0, 255), (0, 0, 255, 255)]
        )

        let targets = try AppleImageDescriptorExtractor().targetDescriptors(
            heroImageData: data,
            columns: 2
        )

        XCTAssertEqual(targets.map(\.coordinate), [
            .init(column: 0, row: 0),
            .init(column: 1, row: 0),
        ])
        XCTAssertGreaterThan(targets[0].descriptor.components[2], 0)
        XCTAssertLessThan(targets[1].descriptor.components[2], 0)
    }

    func testBuilderLoadsCropAndReportsDescriptorProgress() async throws {
        let image = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let sources = [
            AssetReference(id: "one", origin: .testFixture),
            AssetReference(id: "two", origin: .testFixture),
        ]
        let crop = try HeroCrop(x: 0, y: 0, width: 0.5, height: 1)
        let project = MosaicProject(
            hero: hero,
            heroCrop: crop,
            sources: sources,
            sourcesConfirmed: true,
            recipe: .init(columns: 1)
        )
        let loader = DescriptorLoaderStub(dataByID: ["hero": image, "one": image, "two": image])
        let collector = DescriptorProgressCollector()

        let descriptors = try await PhotoPreviewDescriptorBuilder().descriptors(
            for: project,
            loader: loader
        ) { collector.append($0) }
        let requestedCrop = await loader.requestedCrop(for: "hero")

        XCTAssertEqual(descriptors.targets.count, 1)
        XCTAssertEqual(descriptors.sources.map(\.reference), sources)
        XCTAssertEqual(requestedCrop, crop)
        XCTAssertEqual(collector.snapshot(), [
            .init(completed: 0, total: 3),
            .init(completed: 1, total: 3),
            .init(completed: 2, total: 3),
            .init(completed: 3, total: 3),
        ])
    }

    func testServiceBuildsRenderedPreviewAndReusesCachedAssignment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let red = try makePNG(width: 1, height: 1, pixels: [(255, 0, 0, 255)])
        let blue = try makePNG(width: 1, height: 1, pixels: [(0, 0, 255, 255)])
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let source = AssetReference(id: "source", origin: .testFixture)
        let project = MosaicProject(
            hero: hero,
            sources: [source],
            sourcesConfirmed: true,
            recipe: .init(columns: 1, repeatWindow: 0)
        )
        let loader = DescriptorLoaderStub(dataByID: ["hero": red, "source": blue])
        let cache = JSONPreviewAssignmentCache(directory: directory)
        let service = ApplePhotoPreviewAssignmentService(
            loader: loader,
            generator: CachedPreviewAssignmentGenerator(cache: cache),
            renderer: .init(maximumDimension: 2)
        )

        let generated = try await service.preview(for: project)
        let cached = try await service.preview(for: project)
        var adjustedProject = project
        adjustedProject.recipe.likeness = 1
        let refreshed = try await service.renderPreview(
            for: adjustedProject,
            tiles: generated.assignment.tiles
        ) { _ in }

        XCTAssertEqual(generated.assignmentOrigin, .generatedAndCached)
        XCTAssertEqual(cached.assignmentOrigin, .cache)
        XCTAssertEqual(cached.assignment, generated.assignment)
        XCTAssertEqual(generated.image.columns, 1)
        XCTAssertEqual(generated.image.rows, 1)
        XCTAssertFalse(generated.image.data.isEmpty)
        XCTAssertEqual(refreshed.tiles, generated.assignment.tiles)
        XCTAssertNotEqual(refreshed.data, generated.image.data)
    }

    func testInvalidImageDataIsRejected() {
        XCTAssertThrowsError(
            try AppleImageDescriptorExtractor().targetDescriptors(
                heroImageData: Data("not-an-image".utf8),
                columns: 1
            )
        ) { error in
            XCTAssertEqual(error as? ImageDescriptorError, .imageDecodeFailed)
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
}
