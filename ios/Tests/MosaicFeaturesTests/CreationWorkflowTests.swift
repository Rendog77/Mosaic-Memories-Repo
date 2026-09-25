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

    func testReplacingHeroKeepsSelectedSourcesInReview() {
        var workflow = CreationWorkflow()
        workflow.selectHero(.init(id: "old", origin: .testFixture))
        let source = AssetReference(id: "source", origin: .testFixture)
        workflow.reviewSources([source])

        workflow.selectHero(.init(id: "new", origin: .testFixture))

        XCTAssertEqual(workflow.step, .sourceReview)
        XCTAssertEqual(workflow.project.sources, [source])
    }

    func testCropPresetsHaveValidGeometryAndOriginalResets() {
        for preset in HeroCropPreset.allCases {
            XCTAssertEqual(HeroCropPreset.selected(for: preset.crop), preset)
            if preset != .original {
                XCTAssertNotNil(preset.crop)
            }
        }
        var workflow = CreationWorkflow()
        workflow.selectHero(.init(id: "hero", origin: .testFixture))
        workflow.setHeroCrop(HeroCropPreset.center.crop)
        XCTAssertEqual(workflow.project.heroCrop, HeroCropPreset.center.crop)
        workflow.setHeroCrop(HeroCropPreset.original.crop)
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
        XCTAssertFalse(workflow.project.sourcesConfirmed)
        try workflow.confirmReviewedSources()
        XCTAssertEqual(workflow.step, .preview)
        XCTAssertTrue(workflow.project.sourcesConfirmed)
    }

    func testBlankProjectNameFallsBackToUntitled() {
        var workflow = CreationWorkflow(project: MosaicProject(title: "Original"))
        workflow.renameProject(to: "   ")
        XCTAssertEqual(workflow.project.title, "Untitled Mosaic")
    }

    func testLikenessIsValidatedAndUpdatesRecipe() throws {
        var workflow = CreationWorkflow()

        try workflow.setLikeness(0.8)

        XCTAssertEqual(workflow.project.recipe.likeness, 0.8)
        XCTAssertThrowsError(try workflow.setLikeness(-0.1))
        XCTAssertThrowsError(try workflow.setLikeness(1.1))
        XCTAssertThrowsError(try workflow.setLikeness(.nan))
        XCTAssertEqual(workflow.project.recipe.likeness, 0.8)
    }

    func testRemovingSourceReturnsToReviewAndUpdatesReadiness() throws {
        var workflow = CreationWorkflow()
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        try workflow.confirmSources(sources)
        XCTAssertEqual(workflow.sourceReadiness(), .ready(count: 100))

        XCTAssertTrue(workflow.removeSource(id: "source-0"))
        XCTAssertEqual(workflow.step, .sourceReview)
        XCTAssertFalse(workflow.project.sourcesConfirmed)
        XCTAssertEqual(workflow.sourceReadiness(), .needsMore(required: 100, actual: 99))
        XCTAssertFalse(workflow.removeSource(id: "missing"))
    }
}
