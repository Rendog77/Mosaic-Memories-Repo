import Foundation
import XCTest
import MosaicCore
@testable import MosaicPersistence

private enum PreviewCacheStubError: Error {
    case saveFailed
}

private actor PreviewCacheStub: PreviewAssignmentCaching {
    private var loaded: MosaicPreviewAssignment?
    private let shouldFailSave: Bool
    private var saved: MosaicPreviewAssignment?
    private var removalCount = 0

    init(loaded: MosaicPreviewAssignment? = nil, shouldFailSave: Bool = false) {
        self.loaded = loaded
        self.shouldFailSave = shouldFailSave
    }

    func load(for project: MosaicProject) -> MosaicPreviewAssignment? {
        loaded
    }

    func save(_ assignment: MosaicPreviewAssignment, for project: MosaicProject) throws {
        if shouldFailSave { throw PreviewCacheStubError.saveFailed }
        saved = assignment
        loaded = assignment
    }

    func remove(for projectID: UUID) {
        removalCount += 1
        loaded = nil
    }

    func snapshot() -> (saved: MosaicPreviewAssignment?, removalCount: Int) {
        (saved, removalCount)
    }
}

private final class CoordinatorProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MosaicProgress] = []

    func append(_ progress: MosaicProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshot() -> [MosaicProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class CachedPreviewAssignmentGeneratorTests: XCTestCase {
    func testCacheHitSkipsGenerationAndReportsCompletion() async throws {
        let fixture = try makeFixture(targetCount: 2)
        let cached = try MosaicPreviewAssigner().assign(
            targets: fixture.targets,
            sources: fixture.sources,
            repeatWindow: fixture.project.recipe.repeatWindow
        )
        let cache = PreviewCacheStub(loaded: cached)
        let collector = CoordinatorProgressCollector()

        let result = try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
            for: fixture.project,
            targets: fixture.targets,
            sources: fixture.sources
        ) { collector.append($0) }

        XCTAssertEqual(result, .init(assignment: cached, origin: .cache))
        XCTAssertEqual(collector.snapshot(), [.init(completed: 2, total: 2)])
        let snapshot = await cache.snapshot()
        XCTAssertNil(snapshot.saved)
    }

    func testCacheMissGeneratesAndStoresCompletedAssignment() async throws {
        let fixture = try makeFixture(targetCount: 3)
        let cache = PreviewCacheStub()
        let collector = CoordinatorProgressCollector()

        let result = try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
            for: fixture.project,
            targets: fixture.targets,
            sources: fixture.sources
        ) { collector.append($0) }

        XCTAssertEqual(result.origin, .generatedAndCached)
        XCTAssertEqual(result.assignment.tiles.count, 3)
        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot.saved, result.assignment)
        XCTAssertEqual(collector.snapshot().last, .init(completed: 3, total: 3))
    }

    func testInvalidCacheEntryIsRemovedAndRegenerated() async throws {
        let fixture = try makeFixture(targetCount: 2)
        let incomplete = MosaicPreviewAssignment(
            engineVersion: fixture.project.recipe.engineVersion,
            tiles: [.init(coordinate: .init(column: 0, row: 0), source: fixture.project.sources[0])]
        )
        let cache = PreviewCacheStub(loaded: incomplete)

        let result = try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
            for: fixture.project,
            targets: fixture.targets,
            sources: fixture.sources
        )

        XCTAssertEqual(result.origin, .generatedAndCached)
        XCTAssertEqual(result.assignment.tiles.count, 2)
        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot.removalCount, 1)
        XCTAssertEqual(snapshot.saved, result.assignment)
    }

    func testCacheWriteFailureDoesNotDiscardGeneratedPreview() async throws {
        let fixture = try makeFixture(targetCount: 1)
        let cache = PreviewCacheStub(shouldFailSave: true)

        let result = try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
            for: fixture.project,
            targets: fixture.targets,
            sources: fixture.sources
        )

        XCTAssertEqual(result.origin, .generatedWithoutCache)
        XCTAssertEqual(result.assignment.tiles.count, 1)
    }

    func testSourceDescriptorsMustMatchConfirmedProjectSources() async throws {
        let fixture = try makeFixture(targetCount: 1)
        let cache = PreviewCacheStub()

        do {
            _ = try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
                for: fixture.project,
                targets: fixture.targets,
                sources: Array(fixture.sources.prefix(1))
            )
            XCTFail("Expected source-set validation failure")
        } catch let error as PreviewAssignmentGenerationError {
            XCTAssertEqual(error, .sourcesDoNotMatchProject)
        }
    }

    func testCancellationDoesNotWritePartialAssignment() async throws {
        let fixture = try makeFixture(targetCount: 100)
        let cache = PreviewCacheStub()
        let task = Task {
            try await CachedPreviewAssignmentGenerator(cache: cache).assignment(
                for: fixture.project,
                targets: fixture.targets,
                sources: fixture.sources
            ) { progress in
                if progress.completed == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected generation cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let snapshot = await cache.snapshot()
        XCTAssertNil(snapshot.saved)
    }

    private func makeFixture(
        targetCount: Int
    ) throws -> (
        project: MosaicProject,
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor]
    ) {
        let references = [
            AssetReference(id: "dark", origin: .testFixture),
            AssetReference(id: "light", origin: .testFixture),
        ]
        let project = MosaicProject(
            hero: .init(id: "hero", origin: .testFixture),
            sources: references,
            sourcesConfirmed: true,
            recipe: .init(repeatWindow: 1)
        )
        let sources = [
            MosaicSourceDescriptor(
                reference: references[0],
                descriptor: try MosaicDescriptor(components: [0])
            ),
            MosaicSourceDescriptor(
                reference: references[1],
                descriptor: try MosaicDescriptor(components: [100])
            ),
        ]
        let targets = try (0..<targetCount).map {
            MosaicTargetDescriptor(
                coordinate: .init(column: $0, row: 0),
                descriptor: try MosaicDescriptor(components: [Double($0 % 2) * 100])
            )
        }
        return (project, targets, sources)
    }
}
