import Foundation
import XCTest
import MosaicCore
import MosaicFeatures
@testable import MosaicAppUI

private actor ThumbnailLoaderStub: PhotoAssetLoading {
    private var results: [String: [Result<Data, PhotoSelectionError>]]
    private(set) var requestedPixelSizes: [Int] = []

    init(results: [String: [Result<Data, PhotoSelectionError>]]) {
        self.results = results
    }

    func thumbnail(for reference: AssetReference, maximumPixelSize: Int) async throws -> Data {
        requestedPixelSizes.append(maximumPixelSize)
        guard var queue = results[reference.id], !queue.isEmpty else {
            throw PhotoSelectionError.assetUnavailable(reference.id)
        }
        let result = queue.removeFirst()
        results[reference.id] = queue
        return try result.get()
    }
}

@MainActor
final class PhotoThumbnailModelsTests: XCTestCase {
    func testHeroThumbnailLoadsThroughBoundedLoader() async {
        let data = Data([1, 2, 3])
        let loader = ThumbnailLoaderStub(results: ["hero": [.success(data)]])
        let model = HeroPhotoViewModel(loader: loader)

        await model.load(.init(id: "hero", origin: .testFixture), maximumPixelSize: 640)
        let requestedSizes = await loader.requestedPixelSizes

        XCTAssertEqual(model.thumbnailState, .loaded(data))
        XCTAssertEqual(requestedSizes, [640])
    }

    func testEmptyThumbnailIsTreatedAsUnavailable() async {
        let loader = ThumbnailLoaderStub(results: ["hero": [.success(Data())]])
        let model = HeroPhotoViewModel(loader: loader)

        await model.load(.init(id: "hero", origin: .testFixture))

        XCTAssertEqual(model.thumbnailState, .failed(.assetUnavailable("hero")))
    }

    func testSourceReviewRetriesOnlyFailedThumbnails() async {
        let recovered = Data([9])
        let loader = ThumbnailLoaderStub(results: [
            "one": [.failure(.iCloudDownloadFailed("one")), .success(recovered)],
            "two": [.success(Data([2]))],
        ])
        let references = [
            AssetReference(id: "one", origin: .testFixture),
            AssetReference(id: "two", origin: .testFixture),
        ]
        let model = SourceReviewViewModel(references: references, loader: loader)

        await model.loadFirst(2)
        XCTAssertEqual(model.items[0].state, .failed(.iCloudDownloadFailed("one")))
        XCTAssertEqual(model.items[1].state, .loaded(Data([2])))
        await model.retryFailed()

        XCTAssertEqual(model.items[0].state, .loaded(recovered))
        XCTAssertEqual(model.items[1].state, .loaded(Data([2])))
    }

    func testUnknownSourceIdentifierDoesNothing() async {
        let loader = ThumbnailLoaderStub(results: [:])
        let model = SourceReviewViewModel(references: [], loader: loader)
        await model.loadThumbnail(for: "missing")
        XCTAssertTrue(model.items.isEmpty)
    }
}

