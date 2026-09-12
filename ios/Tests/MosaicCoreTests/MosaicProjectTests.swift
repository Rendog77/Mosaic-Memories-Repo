import XCTest
@testable import MosaicCore

final class MosaicProjectTests: XCTestCase {
    func testRecipeRoundTripsThroughJSON() throws {
        let source = AssetReference(id: "fixture-1", origin: .testFixture)
        let project = MosaicProject(hero: source, sources: [source])
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(MosaicProject.self, from: data), project)
    }
}

