import Foundation
import MosaicCore
import XCTest
@testable import MosaicAppUI

final class MosaicExportFileStoreTests: XCTestCase {
    func testRecordedExportRecoversOnlyForUnchangedProject() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let project = MosaicProject(updatedAt: Date(timeIntervalSince1970: 1_000))
        let result = try await fixture.makeResult(projectID: project.id, byte: 1)

        try await fixture.store.record(result, for: project)
        let recovered = await fixture.store.recover(for: project)

        XCTAssertEqual(recovered, result)

        var editedProject = project
        editedProject.updatedAt = project.updatedAt.addingTimeInterval(1)
        let staleRecovery = await fixture.store.recover(for: editedProject)

        XCTAssertNil(staleRecovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testRecordingReplacementDeletesSupersededFileAfterPublish() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let project = MosaicProject()
        let first = try await fixture.makeResult(projectID: project.id, byte: 1)
        try await fixture.store.record(first, for: project)
        let second = try await fixture.makeResult(projectID: project.id, byte: 2)

        try await fixture.store.record(second, for: project)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        let recovered = await fixture.store.recover(for: project)
        XCTAssertEqual(recovered, second)
    }

    func testPurgeRemovesOldOrphanButPreservesRecordedExport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let project = MosaicProject()
        let recorded = try await fixture.makeResult(projectID: project.id, byte: 1)
        try await fixture.store.record(recorded, for: project)
        let orphan = try await fixture.store.destination(for: UUID(), format: .png)
        try Data([9]).write(to: orphan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: orphan.path
        )

        await fixture.store.purgeAbandonedFiles(olderThan: Date(timeIntervalSince1970: 2))

        XCTAssertTrue(FileManager.default.fileExists(atPath: recorded.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testDiscardRefusesFileOutsideManagedDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).png")
        try Data([1]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        await fixture.store.discardFile(at: outside)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testExpiredRecordedExportAndManifestAreRemoved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let project = MosaicProject()
        let result = try await fixture.makeResult(projectID: project.id, byte: 3)
        try await fixture.store.record(result, for: project)

        await fixture.store.purgeExpiredExports(olderThan: Date().addingTimeInterval(1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path))
        let recovered = await fixture.store.recover(for: project)
        XCTAssertNil(recovered)
    }
}

private struct Fixture {
    let directory: URL
    let store: MosaicExportFileStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = MosaicExportFileStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeResult(projectID: UUID, byte: UInt8) async throws -> MosaicExportResult {
        let url = try await store.destination(for: projectID, format: .png)
        let data = Data(repeating: byte, count: 32)
        try data.write(to: url)
        return MosaicExportResult(
            url: url,
            format: .png,
            width: 4,
            height: 2,
            bytesWritten: data.count,
            pixelsPerInch: 300
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
