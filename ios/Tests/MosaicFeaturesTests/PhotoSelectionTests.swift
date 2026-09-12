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

    func testValidatorRejectsSelectionOverMaximumWithoutTruncating() {
        let references = (0..<4).map { AssetReference(id: "source-\($0)", origin: .photoPicker) }
        let request = SourceSelectionRequest(minimumCount: 1, maximumCount: 3)

        XCTAssertThrowsError(try SourceSelectionValidator().validate(references, for: request)) { error in
            XCTAssertEqual(error as? SourceSelectionValidationError, .tooManySources(maximum: 3, actual: 4))
        }
    }

    func testValidatorRejectsDuplicateIdentifiers() {
        let references = [
            AssetReference(id: "same-photo", origin: .photoPicker),
            AssetReference(id: "same-photo", origin: .photoPicker),
        ]

        XCTAssertThrowsError(try SourceSelectionValidator().validate(references, for: .init())) { error in
            XCTAssertEqual(error as? SourceSelectionValidationError, .duplicateReferences(["same-photo"]))
        }
    }

    func testValidatorEnforcesAccessModeOrigins() {
        let libraryAsset = AssetReference(id: "library-photo", origin: .photoLibrary)
        let selectedRequest = SourceSelectionRequest(accessMode: .selectedPhotos)

        XCTAssertThrowsError(try SourceSelectionValidator().validate([libraryAsset], for: selectedRequest)) { error in
            XCTAssertEqual(
                error as? SourceSelectionValidationError,
                .unexpectedOrigin(.photoLibrary, accessMode: .selectedPhotos)
            )
        }
    }

    func testValidatorAllowsFixtureOriginsForDeterministicTests() throws {
        let fixture = AssetReference(id: "fixture", origin: .testFixture)
        XCTAssertEqual(
            try SourceSelectionValidator().validate([fixture], for: .init()),
            [fixture]
        )
    }
}
