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
}
