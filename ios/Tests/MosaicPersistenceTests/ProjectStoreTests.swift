import Foundation
import XCTest
import MosaicCore
@testable import MosaicPersistence

final class ProjectStoreTests: XCTestCase {
    func testSaveLoadListAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProjectStore(directory: directory)
        let project = MosaicProject(title: "Luna")

        try await store.save(project)
        let loaded = try await store.load(id: project.id)
        let projects = try await store.list()
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(projects, [project])
        XCTAssertEqual(loaded?.createdAt.timeIntervalSinceReferenceDate, project.createdAt.timeIntervalSinceReferenceDate)
        XCTAssertEqual(loaded?.updatedAt.timeIntervalSinceReferenceDate, project.updatedAt.timeIntervalSinceReferenceDate)
        try await store.delete(id: project.id)
        let deleted = try await store.load(id: project.id)
        XCTAssertNil(deleted)
    }

    func testCatalogReportsCorruptAndFutureProjects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let future = MosaicProject(schemaVersion: MosaicProject.currentSchemaVersion + 1, title: "From the future")
        try JSONEncoder().encode(future).write(to: directory.appendingPathComponent("future.json"))
        let valid = MosaicProject(title: "Valid")
        let store = JSONProjectStore(directory: directory)
        try await store.save(valid)

        let catalog = try await store.catalog()

        XCTAssertEqual(catalog.projects, [valid])
        XCTAssertEqual(catalog.unreadableProjectCount, 2)
    }

    func testInMemoryStoreSupportsPreviewAndTests() async throws {
        let project = MosaicProject(title: "Preview")
        let store = InMemoryProjectStore()
        try await store.save(project)
        let loaded = try await store.load(id: project.id)
        let catalog = try await store.catalog()
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(catalog, ProjectCatalog(projects: [project]))
    }

    func testVersionZeroProjectMigratesBeforeDecoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = MosaicProject(title: "Legacy memory")
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["schemaVersion"] = nil
        var recipe = try XCTUnwrap(legacy["recipe"] as? [String: Any])
        recipe["engineVersion"] = nil
        recipe["replacements"] = nil
        legacy["recipe"] = recipe
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let file = directory.appendingPathComponent(original.id.uuidString).appendingPathExtension("json")
        try legacyData.write(to: file)

        let store = JSONProjectStore(directory: directory)
        let migrated = try await store.load(id: original.id)

        XCTAssertEqual(migrated, original)
        XCTAssertEqual(migrated?.schemaVersion, 2)
        XCTAssertEqual(migrated?.recipe.engineVersion, 1)
    }

    func testVersionOneProjectMigratesWithoutCrop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = MosaicProject(title: "Before crop")
        let encoded = try JSONEncoder().encode(original)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        document["schemaVersion"] = 1
        document["heroCrop"] = nil
        let file = directory.appendingPathComponent(original.id.uuidString).appendingPathExtension("json")
        try JSONSerialization.data(withJSONObject: document).write(to: file)

        let migrated = try await JSONProjectStore(directory: directory).load(id: original.id)

        XCTAssertEqual(migrated, original)
        XCTAssertNil(migrated?.heroCrop)
    }

    func testMigratorRejectsFutureSchema() throws {
        let future = MosaicProject(schemaVersion: MosaicProject.currentSchemaVersion + 1)
        let data = try JSONEncoder().encode(future)
        XCTAssertThrowsError(try DefaultProjectMigrator().migrate(data: data)) { error in
            XCTAssertEqual(
                error as? ProjectStoreError,
                .unsupportedSchema(MosaicProject.currentSchemaVersion + 1)
            )
        }
    }
}
