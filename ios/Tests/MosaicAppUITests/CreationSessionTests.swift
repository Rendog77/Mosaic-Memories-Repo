import Foundation
import XCTest
import MosaicCore
import MosaicFeatures
import MosaicPersistence
import MosaicPrivacy
@testable import MosaicAppUI

private struct HeroSelectorStub: HeroPhotoSelecting {
    let result: Result<AssetReference?, PhotoSelectionError>

    func selectHero() async throws -> AssetReference? {
        try result.get()
    }
}

private struct SourceSelectorStub: SourcePhotosSelecting {
    let result: Result<[AssetReference], PhotoSelectionError>

    func selectSources(request: SourceSelectionRequest) async throws -> [AssetReference] {
        try result.get()
    }
}

private struct MissingAssetChecker: PhotoAssetChecking {
    let missingIDs: Set<String>

    func isAvailable(_ reference: AssetReference) async -> Bool {
        !missingIDs.contains(reference.id)
    }
}

private actor RecordingAnalytics: AnalyticsRecording {
    private var events: [AnalyticsEvent] = []

    func record(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func capturedEvents() -> [AnalyticsEvent] {
        events
    }
}

private actor SaveFailingProjectStore: ProjectStoring {
    struct Failure: Error {}

    func load(id: UUID) throws -> MosaicProject? { nil }
    func save(_ project: MosaicProject) throws { throw Failure() }
    func delete(id: UUID) throws {}
    func list() throws -> [MosaicProject] { [] }
    func catalog() throws -> ProjectCatalog { ProjectCatalog(projects: []) }
}

@MainActor
final class CreationSessionTests: XCTestCase {
    func testSessionAutosavesAndRestoresWorkflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProjectStore(directory: directory)
        let session = CreationSession(store: store)

        await session.selectHero(.init(id: "hero", origin: .testFixture))
        let crop = try HeroCrop(x: 0.1, y: 0.2, width: 0.8, height: 0.7)
        await session.setHeroCrop(crop)
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        await session.reviewSources(sources)
        await session.confirmSources()

        let restored = CreationSession(store: store)
        await restored.restoreMostRecentProject()

        XCTAssertEqual(restored.workflow.project, session.workflow.project)
        XCTAssertEqual(restored.workflow.project.heroCrop, crop)
        XCTAssertEqual(restored.workflow.step, .preview)
    }

    func testPartialSourceReviewResumesWithoutBypassingConfirmation() async throws {
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store)
        await session.selectHero(.init(id: "hero", origin: .testFixture))
        await session.reviewSources([
            .init(id: "source-1", origin: .testFixture),
            .init(id: "source-2", origin: .testFixture),
        ])

        let restored = CreationSession(store: store)
        await restored.restoreMostRecentProject()

        XCTAssertEqual(restored.workflow.step, .sourceReview)
        XCTAssertFalse(restored.workflow.project.sourcesConfirmed)
        XCTAssertEqual(restored.sourceReadiness(), .needsMore(required: 100, actual: 2))
    }

    func testInsufficientSourcesProduceHelpfulMessage() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = CreationSession(store: JSONProjectStore(directory: directory))
        await session.reviewSources([])
        await session.confirmSources()
        XCTAssertEqual(session.message, "Choose at least 100 photos. You currently have 0.")
    }

    func testMissingSourceBlocksConfirmationAndIsMarkedForRemoval() async {
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let sources = [
            AssetReference(id: "available", origin: .testFixture),
            AssetReference(id: "missing", origin: .testFixture),
        ]
        let session = CreationSession(
            store: InMemoryProjectStore(),
            assetChecker: MissingAssetChecker(missingIDs: ["missing"])
        )
        await session.selectHero(hero)
        await session.reviewSources(sources)

        await session.confirmSources(minimum: 1)

        XCTAssertEqual(session.workflow.step, .sourceReview)
        XCTAssertEqual(session.missingAssetIDs, ["missing"])
        XCTAssertEqual(session.message, "1 selected photo is no longer available. Remove the marked photos or select them again.")
        XCTAssertFalse(session.isCheckingAssets)

        await session.removeSource(id: "missing")
        XCTAssertTrue(session.missingAssetIDs.isEmpty)
        await session.confirmSources(minimum: 1)
        XCTAssertEqual(session.workflow.step, .preview)
    }

    func testMissingHeroBlocksConfirmation() async {
        let session = CreationSession(
            store: InMemoryProjectStore(),
            assetChecker: MissingAssetChecker(missingIDs: ["hero"])
        )
        await session.selectHero(.init(id: "hero", origin: .testFixture))
        await session.reviewSources([.init(id: "source", origin: .testFixture)])

        await session.confirmSources(minimum: 1)

        XCTAssertEqual(session.workflow.step, .sourceReview)
        XCTAssertEqual(session.message, "Your hero photo is no longer available. Choose it again before creating a mosaic.")
        XCTAssertTrue(session.isHeroMissing)
        await session.selectHero(.init(id: "replacement", origin: .testFixture))
        XCTAssertFalse(session.isHeroMissing)
        XCTAssertEqual(session.workflow.step, .sourceReview)
    }

    func testInjectedSelectorsAdvanceTheWorkflow() async {
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        let session = CreationSession(
            store: InMemoryProjectStore(),
            heroSelector: HeroSelectorStub(result: .success(hero)),
            sourceSelector: SourceSelectorStub(result: .success(sources))
        )

        await session.requestHeroSelection()
        XCTAssertEqual(session.workflow.step, .memories)
        await session.requestSourceSelection()
        XCTAssertEqual(session.workflow.step, .sourceReview)
        XCTAssertEqual(session.workflow.project.sources.count, 100)
    }

    func testPickerCancellationLeavesWorkflowUnchanged() async {
        let session = CreationSession(
            store: InMemoryProjectStore(),
            heroSelector: HeroSelectorStub(result: .success(nil))
        )

        await session.requestHeroSelection()

        XCTAssertEqual(session.workflow.step, .hero)
        XCTAssertEqual(session.photoSelectionState, .cancelled)
        XCTAssertNil(session.message)
    }

    func testPermissionDenialExplainsSelectedPhotosFallback() async {
        let session = CreationSession(
            store: InMemoryProjectStore(),
            sourceSelector: SourceSelectorStub(result: .failure(.permissionDenied))
        )

        await session.requestSourceSelection()

        XCTAssertEqual(session.photoSelectionState, .failed(.permissionDenied))
        XCTAssertEqual(
            session.message,
            "Photo access was denied. You can still choose selected photos without granting full-library access."
        )
    }

    func testICloudFailureProvidesRetryGuidance() async {
        let session = CreationSession(
            store: InMemoryProjectStore(),
            sourceSelector: SourceSelectorStub(result: .failure(.iCloudDownloadFailed("source-1")))
        )

        await session.requestSourceSelection()

        XCTAssertEqual(session.photoSelectionState, .failed(.iCloudDownloadFailed("source-1")))
        XCTAssertEqual(session.message, "A photo could not be downloaded from iCloud. Check your connection and try again.")
    }

    func testUnsupportedFormatProvidesReplacementGuidance() async {
        let session = CreationSession(
            store: InMemoryProjectStore(),
            heroSelector: HeroSelectorStub(result: .failure(.unsupportedFormat("hero-item")))
        )

        await session.requestHeroSelection()

        XCTAssertEqual(session.photoSelectionState, .failed(.unsupportedFormat("hero-item")))
        XCTAssertEqual(
            session.message,
            "A selected file is not a supported image. Choose another photo and try again."
        )
    }

    func testOversizedSelectionIsRejectedRatherThanSilentlyTruncated() async {
        let sources = (0..<4).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        let session = CreationSession(
            store: InMemoryProjectStore(),
            sourceSelector: SourceSelectorStub(result: .success(sources))
        )

        await session.requestSourceSelection(
            request: .init(minimumCount: 1, maximumCount: 3)
        )

        XCTAssertEqual(session.photoSelectionState, .invalidSources(.tooManySources(maximum: 3, actual: 4)))
        XCTAssertEqual(session.workflow.project.sources, [])
        XCTAssertEqual(session.message, "Choose no more than 3 photos. You selected 4.")
    }

    func testCreationFlowRecordsOnlyCoarseAnalytics() async {
        let recorder = RecordingAnalytics()
        let session = CreationSession(store: InMemoryProjectStore(), analytics: recorder)
        let sources = (0..<100).map { AssetReference(id: "private-source-\($0)", origin: .testFixture) }

        await session.startNewProject()
        await session.selectHero(.init(id: "private-hero-name.jpg", origin: .testFixture))
        await session.reviewSources(sources)
        await session.confirmSources()
        await session.move(to: .edit)
        let events = await recorder.capturedEvents()

        XCTAssertEqual(events.map(\.name), [.projectStarted, .heroSelected, .sourceSetConfirmed, .previewCompleted])
        XCTAssertEqual(events[2].fields[.sourceCountBucket], "100_249")
        XCTAssertFalse(events.description.contains("private-hero-name.jpg"))
        XCTAssertFalse(events.description.contains("private-source-"))
        for event in events {
            XCTAssertNoThrow(try AnalyticsEventValidator().validate(event))
        }
    }

    func testAddingAndRemovingSourcesPersistsCombinedReviewSet() async throws {
        let initial = (0..<60).map { AssetReference(id: "initial-\($0)", origin: .testFixture) }
        let additional = (0..<40).map { AssetReference(id: "additional-\($0)", origin: .testFixture) }
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store)

        await session.reviewSources(initial)
        try await session.addSources(additional)
        XCTAssertEqual(session.sourceReadiness(), .ready(count: 100))
        await session.removeSource(id: "initial-0")
        XCTAssertEqual(session.sourceReadiness(), .needsMore(required: 100, actual: 99))

        let saved = try await store.load(id: session.workflow.project.id)
        XCTAssertEqual(saved?.sources.count, 99)
    }

    func testAddingDuplicateSourceDoesNotModifyProject() async {
        let source = AssetReference(id: "duplicate", origin: .testFixture)
        let session = CreationSession(store: InMemoryProjectStore())
        await session.reviewSources([source])

        do {
            try await session.addSources([source])
            XCTFail("Expected duplicate validation failure")
        } catch let error as SourceSelectionValidationError {
            XCTAssertEqual(error, .duplicateReferences(["duplicate"]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(session.workflow.project.sources, [source])
    }

    func testSourceRemovalRollsBackWhenPersistenceFails() async {
        let source = AssetReference(id: "keep-me", origin: .photoPicker)
        let project = MosaicProject(sources: [source])
        let session = CreationSession(
            store: SaveFailingProjectStore(),
            project: project,
            step: .sourceReview
        )

        let removed = await session.removeSource(id: source.id)

        XCTAssertFalse(removed)
        XCTAssertEqual(session.workflow.project.sources, [source])
        XCTAssertEqual(session.message, "Changes could not be saved. Please try again.")
    }

    func testSourceConfirmationRollsBackWhenPersistenceFails() async {
        let source = AssetReference(id: "keep-in-review", origin: .testFixture)
        let project = MosaicProject(
            hero: .init(id: "hero", origin: .testFixture),
            sources: [source]
        )
        let session = CreationSession(
            store: SaveFailingProjectStore(),
            project: project,
            step: .sourceReview
        )

        await session.confirmSources(minimum: 1)

        XCTAssertEqual(session.workflow.step, .sourceReview)
        XCTAssertFalse(session.workflow.project.sourcesConfirmed)
        XCTAssertEqual(session.message, "Changes could not be saved. Please try again.")
    }

    func testCropChangeRollsBackWhenPersistenceFails() async {
        let hero = AssetReference(id: "hero", origin: .testFixture)
        let project = MosaicProject(hero: hero)
        let session = CreationSession(store: SaveFailingProjectStore(), project: project)

        await session.setHeroCrop(HeroCropPreset.center.crop)

        XCTAssertNil(session.workflow.project.heroCrop)
        XCTAssertEqual(session.message, "Changes could not be saved. Please try again.")
    }

    func testLikenessChangePersists() async {
        let project = MosaicProject(recipe: .init(likeness: 0.5))
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store, project: project, step: .edit)

        let changed = await session.setLikeness(0.75)
        let saved = try? await store.load(id: project.id)

        XCTAssertTrue(changed)
        XCTAssertEqual(session.workflow.project.recipe.likeness, 0.75)
        XCTAssertEqual(saved?.recipe.likeness, 0.75)
        XCTAssertTrue(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
    }

    func testLikenessChangeRollsBackWhenPersistenceFails() async {
        let project = MosaicProject(recipe: .init(likeness: 0.5))
        let session = CreationSession(
            store: SaveFailingProjectStore(),
            project: project,
            step: .edit
        )

        let changed = await session.setLikeness(0.75)

        XCTAssertFalse(changed)
        XCTAssertEqual(session.workflow.project.recipe.likeness, 0.5)
        XCTAssertEqual(session.message, "Changes could not be saved. Please try again.")
    }

    func testTileReplacementPersistsAndCanBeUndone() async {
        let original = AssetReference(id: "original", origin: .testFixture)
        let replacement = AssetReference(id: "replacement", origin: .testFixture)
        let coordinate = TileCoordinate(column: 0, row: 0)
        let project = MosaicProject(
            sources: [original, replacement],
            sourcesConfirmed: true,
            recipe: .init(columns: 1)
        )
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store, project: project, step: .edit)

        let replaced = await session.replaceTile(
            at: coordinate,
            with: replacement,
            replacing: original
        )
        let savedReplacement = try? await store.load(id: project.id)
        let undone = await session.undoLastEdit()
        let savedUndo = try? await store.load(id: project.id)

        XCTAssertTrue(replaced)
        XCTAssertEqual(savedReplacement?.recipe.replacements[coordinate], replacement)
        XCTAssertEqual(
            undone,
            .tileReplacement(.init(coordinate: coordinate, source: original))
        )
        XCTAssertNil(savedUndo?.recipe.replacements[coordinate])
        XCTAssertFalse(session.canUndoEdit)
        XCTAssertTrue(session.canRedoEdit)

        let redone = await session.redoLastEdit()
        let savedRedo = try? await store.load(id: project.id)

        XCTAssertEqual(
            redone,
            .tileReplacement(.init(coordinate: coordinate, source: replacement))
        )
        XCTAssertEqual(savedRedo?.recipe.replacements[coordinate], replacement)
        XCTAssertTrue(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
    }

    func testTileReplacementRollsBackWhenPersistenceFails() async {
        let original = AssetReference(id: "original", origin: .testFixture)
        let replacement = AssetReference(id: "replacement", origin: .testFixture)
        let coordinate = TileCoordinate(column: 0, row: 0)
        let project = MosaicProject(
            sources: [original, replacement],
            sourcesConfirmed: true,
            recipe: .init(columns: 1)
        )
        let session = CreationSession(
            store: SaveFailingProjectStore(),
            project: project,
            step: .edit
        )

        let replaced = await session.replaceTile(
            at: coordinate,
            with: replacement,
            replacing: original
        )

        XCTAssertFalse(replaced)
        XCTAssertNil(session.workflow.project.recipe.replacements[coordinate])
        XCTAssertFalse(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
    }

    func testLikenessAndReplacementShareOrderedUndoRedoHistory() async {
        let original = AssetReference(id: "original", origin: .testFixture)
        let replacement = AssetReference(id: "replacement", origin: .testFixture)
        let coordinate = TileCoordinate(column: 0, row: 0)
        let project = MosaicProject(
            sources: [original, replacement],
            sourcesConfirmed: true,
            recipe: .init(columns: 1, likeness: 0.5)
        )
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store, project: project, step: .edit)

        let changedLikeness = await session.setLikeness(0.8)
        let replaced = await session.replaceTile(
            at: coordinate,
            with: replacement,
            replacing: original
        )
        XCTAssertTrue(changedLikeness)
        XCTAssertTrue(replaced)

        let firstUndo = await session.undoLastEdit()
        let secondUndo = await session.undoLastEdit()
        XCTAssertEqual(
            firstUndo,
            .tileReplacement(.init(coordinate: coordinate, source: original))
        )
        XCTAssertEqual(secondUndo, .likeness(0.5))
        XCTAssertFalse(session.canUndoEdit)
        XCTAssertTrue(session.canRedoEdit)

        let firstRedo = await session.redoLastEdit()
        let secondRedo = await session.redoLastEdit()
        XCTAssertEqual(firstRedo, .likeness(0.8))
        XCTAssertEqual(
            secondRedo,
            .tileReplacement(.init(coordinate: coordinate, source: replacement))
        )

        let saved = try? await store.load(id: project.id)
        XCTAssertEqual(saved?.recipe.likeness, 0.8)
        XCTAssertEqual(saved?.recipe.replacements[coordinate], replacement)
        XCTAssertTrue(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
    }

    func testRollingBackANewEditDoesNotLeaveRedoHistory() async {
        let project = MosaicProject(recipe: .init(likeness: 0.5))
        let store = InMemoryProjectStore()
        let session = CreationSession(store: store, project: project, step: .edit)

        let changed = await session.setLikeness(0.8)
        let rolledBack = await session.rollbackLastEdit()
        let saved = try? await store.load(id: project.id)

        XCTAssertTrue(changed)
        XCTAssertEqual(rolledBack, .likeness(0.5))
        XCTAssertEqual(saved?.recipe.likeness, 0.5)
        XCTAssertFalse(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
    }
}
