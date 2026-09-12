import XCTest
import MosaicCore
@testable import MosaicFeatures

final class CreationWorkflowTests: XCTestCase {
    func testHeroAdvancesToMemorySelection() {
        var workflow = CreationWorkflow()
        workflow.selectHero(.init(id: "hero", origin: .testFixture))
        XCTAssertEqual(workflow.step, .memories)
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
}
