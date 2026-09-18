import XCTest
import MosaicCore
@testable import MosaicFeatures

final class CreationWorkflowTests: XCTestCase {
    func testHeroAdvancesToMemorySelection() {
        var workflow = CreationWorkflow()
        workflow.selectHero(.init(id: "hero", origin: .testFixture))
        XCTAssertEqual(workflow.step, .memories)
    }

    func testChangingHeroClearsItsCrop() throws {
        var workflow = CreationWorkflow()
        workflow.selectHero(.init(id: "first", origin: .testFixture))
        let crop = try HeroCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        workflow.setHeroCrop(crop)
        XCTAssertEqual(workflow.project.heroCrop, crop)

        workflow.selectHero(.init(id: "second", origin: .testFixture))
        XCTAssertNil(workflow.project.heroCrop)
    }

    func testTooFewSourcesCannotAdvance() {
        var workflow = CreationWorkflow()
        XCTAssertThrowsError(try workflow.confirmSources([], minimum: 100))
    }

    func testSourcesAreReviewedBeforeConfirmation() throws {
        var workflow = CreationWorkflow()
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        workflow.reviewSources(sources)
        XCTAssertEqual(workflow.step, .sourceReview)
        try workflow.confirmReviewedSources()
        XCTAssertEqual(workflow.step, .preview)
    }

    func testBlankProjectNameFallsBackToUntitled() {
        var workflow = CreationWorkflow(project: MosaicProject(title: "Original"))
        workflow.renameProject(to: "   ")
        XCTAssertEqual(workflow.project.title, "Untitled Mosaic")
    }

    func testRemovingSourceReturnsToReviewAndUpdatesReadiness() throws {
        var workflow = CreationWorkflow()
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        try workflow.confirmSources(sources)
        XCTAssertEqual(workflow.sourceReadiness(), .ready(count: 100))

        XCTAssertTrue(workflow.removeSource(id: "source-0"))
        XCTAssertEqual(workflow.step, .sourceReview)
        XCTAssertEqual(workflow.sourceReadiness(), .needsMore(required: 100, actual: 99))
        XCTAssertFalse(workflow.removeSource(id: "missing"))
    }
}
