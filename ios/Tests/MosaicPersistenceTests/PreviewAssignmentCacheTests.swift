import Foundation
import XCTest
import MosaicCore
@testable import MosaicPersistence

final class PreviewAssignmentCacheTests: XCTestCase {
    func testNonArtworkChangesAndSourceOrderingDoNotInvalidateAssignment() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        var project = makeProject()
        let assignment = makeAssignment(for: project)

        try await cache.save(assignment, for: project)
        project.title = "Renamed without changing the artwork"
        project.updatedAt = Date()
        project.sources.reverse()
        let loaded = await cache.load(for: project)

        XCTAssertEqual(loaded, assignment)
    }

    func testLikenessChangeReusesCachedAssignment() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        var project = makeProject()
        try await cache.save(makeAssignment(for: project), for: project)

        project.recipe.likeness = 0.9
        let loaded = await cache.load(for: project)

        XCTAssertEqual(loaded, makeAssignment(for: project))
    }

    func testAssignmentRecipeChangeInvalidatesAndRemovesCachedAssignment() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        var project = makeProject()
        try await cache.save(makeAssignment(for: project), for: project)

        project.recipe.repeatWindow += 1
        let loaded = await cache.load(for: project)

        XCTAssertNil(loaded)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    func testCorruptAndIncompatibleFilesRecoverAsCacheMisses() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        let project = makeProject()
        let file = cacheFile(in: directory, projectID: project.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: file)
        let corruptLoad = await cache.load(for: project)

        XCTAssertNil(corruptLoad)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try await cache.save(makeAssignment(for: project), for: project)
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        )
        document["version"] = 99
        try JSONSerialization.data(withJSONObject: document).write(to: file, options: .atomic)
        let incompatibleLoad = await cache.load(for: project)

        XCTAssertNil(incompatibleLoad)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMismatchedAssignmentIsNotCached() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        let project = makeProject()
        let unknown = AssetReference(id: "unknown", origin: .testFixture)
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [.init(coordinate: .init(column: 0, row: 0), source: unknown)]
        )

        do {
            try await cache.save(assignment, for: project)
            XCTFail("Expected mismatched assignment rejection")
        } catch let error as PreviewAssignmentCacheError {
            XCTAssertEqual(error, .assignmentDoesNotMatchProject)
        }
    }

    func testExplicitRemovalIsIdempotent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONPreviewAssignmentCache(directory: directory)
        let project = makeProject()
        try await cache.save(makeAssignment(for: project), for: project)

        try await cache.remove(for: project.id)
        try await cache.remove(for: project.id)
        let loaded = await cache.load(for: project)

        XCTAssertNil(loaded)
    }

    private func makeProject() -> MosaicProject {
        return MosaicProject(
            hero: .init(id: "hero", origin: .testFixture),
            sources: [
                .init(id: "source-b", origin: .testFixture),
                .init(id: "source-a", origin: .testFixture),
            ],
            sourcesConfirmed: true
        )
    }

    private func makeAssignment(for project: MosaicProject) -> MosaicPreviewAssignment {
        MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: [
                .init(
                    coordinate: .init(column: 0, row: 0),
                    source: project.sources[0]
                ),
            ]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func cacheFile(in directory: URL, projectID: UUID) -> URL {
        directory
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("preview.json")
    }
}
