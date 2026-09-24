import XCTest
@testable import MosaicCore

final class MosaicProjectTests: XCTestCase {
    func testRecipeRoundTripsThroughJSON() throws {
        let source = AssetReference(id: "fixture-1", origin: .testFixture)
        let crop = try HeroCrop(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        let project = MosaicProject(
            hero: source,
            heroCrop: crop,
            sources: [source],
            sourcesConfirmed: true
        )
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(MosaicProject.self, from: data), project)
    }

    func testCropRejectsInvalidBoundsOnInitAndDecode() throws {
        XCTAssertThrowsError(try HeroCrop(x: 0.8, y: 0, width: 0.3, height: 1))
        XCTAssertThrowsError(try HeroCrop(x: .nan, y: 0, width: 1, height: 1))
        let invalid = Data(#"{"x":0.8,"y":0,"width":0.3,"height":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HeroCrop.self, from: invalid))
    }
}
