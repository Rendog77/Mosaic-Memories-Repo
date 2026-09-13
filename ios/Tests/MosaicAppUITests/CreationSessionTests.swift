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

private actor RecordingAnalytics: AnalyticsRecording {
    private var events: [AnalyticsEvent] = []

    func record(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func capturedEvents() -> [AnalyticsEvent] {
        events
    }
}

@MainActor
final class CreationSessionTests: XCTestCase {
    func testSessionAutosavesAndRestoresWorkflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProjectStore(directory: directory)
        let session = CreationSession(store: store)

        await session.selectHero(.init(id: "hero", origin: .testFixture))
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        await session.reviewSources(sources)
        await session.confirmSources()

        let restored = CreationSession(store: store)
        await restored.restoreMostRecentProject()

        XCTAssertEqual(restored.workflow.project, session.workflow.project)
        XCTAssertEqual(restored.workflow.step, .preview)
    }

    func testInsufficientSourcesProduceHelpfulMessage() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = CreationSession(store: JSONProjectStore(directory: directory))
        await session.reviewSources([])
        await session.confirmSources()
        XCTAssertEqual(session.message, "Choose at least 100 photos. You currently have 0.")
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
}
