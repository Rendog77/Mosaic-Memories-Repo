import XCTest
import MosaicCore
@testable import MosaicFeatures

private struct FakeHeroSelector: HeroPhotoSelecting {
    let result: Result<AssetReference?, PhotoSelectionError>

    func selectHero() async throws -> AssetReference? {
        try result.get()
    }
}

private struct FakeSourceSelector: SourcePhotosSelecting {
    let result: Result<[AssetReference], PhotoSelectionError>

    func selectSources(request: SourceSelectionRequest) async throws -> [AssetReference] {
        try result.get()
    }
}

final class PhotoSelectionTests: XCTestCase {
    func testHeroSelectionCanBeCancelledWithoutInventingAnAsset() async throws {
        let selector = FakeHeroSelector(result: .success(nil))
        let result = try await selector.selectHero()
        XCTAssertNil(result)
    }

    func testPermissionDenialRemainsARecoverableTypedError() async {
        let selector = FakeSourceSelector(result: .failure(.permissionDenied))
        do {
            _ = try await selector.selectSources(request: .init())
            XCTFail("Expected permission denial")
        } catch let error as PhotoSelectionError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

