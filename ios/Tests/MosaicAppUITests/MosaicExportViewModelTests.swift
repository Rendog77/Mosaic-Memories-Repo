import Foundation
import MosaicCore
import XCTest
@testable import MosaicAppUI

private actor RecordingExporter: MosaicExporting {
    private(set) var receivedTiles: [MosaicAssignedTile] = []
    private(set) var receivedPolicy: MosaicExportPolicy?

    func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult {
        receivedTiles = tiles
        receivedPolicy = policy
        progress(.init(completed: 1, total: 3))
        await Task.yield()
        progress(.init(completed: 3, total: 3))
        return .init(
            url: destination,
            format: policy.format,
            width: 6_000,
            height: 4_000,
            bytesWritten: 1_024,
            pixelsPerInch: policy.pixelsPerInch
        )
    }

    func snapshot() -> ([MosaicAssignedTile], MosaicExportPolicy?) {
        (receivedTiles, receivedPolicy)
    }
}

private struct FailingExporter: MosaicExporting {
    let error: MosaicExportError

    func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult {
        throw error
    }
}

private actor CancellableExporter: MosaicExporting {
    private(set) var started = false
    private(set) var observedCancellation = false

    func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult {
        started = true
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            throw MosaicExportError.writeFailed
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func hasStarted() -> Bool { started }
    func wasCancelled() -> Bool { observedCancellation }
}

final class MosaicExportViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulExportForwardsEditedAssignmentAndPublishesResult() async throws {
        let exporter = RecordingExporter()
        let model = MosaicExportViewModel(exporter: exporter)
        let tile = MosaicAssignedTile(
            coordinate: .init(column: 0, row: 0),
            source: .init(id: "replacement", origin: .testFixture)
        )
        let policy = try MosaicExportPolicy(format: .jpeg(quality: 0.9), longEdgePixels: 6_000)
        let destination = URL(fileURLWithPath: "/tmp/mosaic.jpg")

        await model.export(project: .init(), tiles: [tile], policy: policy, to: destination)
        let snapshot = await exporter.snapshot()

        XCTAssertEqual(snapshot.0, [tile])
        XCTAssertEqual(snapshot.1, policy)
        guard case .completed(let result) = model.state else {
            return XCTFail("Expected completed export state")
        }
        XCTAssertEqual(result.url, destination)
        XCTAssertEqual(result.width, 6_000)
    }

    @MainActor
    func testInsufficientStoragePublishesActionableMessage() async throws {
        let model = MosaicExportViewModel(
            exporter: FailingExporter(error: .insufficientStorage(required: 10, available: 1))
        )

        await model.export(
            project: .init(),
            tiles: [],
            policy: try MosaicExportPolicy(format: .png),
            to: URL(fileURLWithPath: "/tmp/mosaic.png")
        )

        guard case .failed(let message) = model.state else {
            return XCTFail("Expected failed export state")
        }
        XCTAssertTrue(message.contains("free storage"))
        XCTAssertTrue(message.contains("try again"))
    }

    @MainActor
    func testCancelStopsActiveExport() async throws {
        let exporter = CancellableExporter()
        let model = MosaicExportViewModel(exporter: exporter)
        let task = Task {
            await model.export(
                project: .init(),
                tiles: [],
                policy: try! MosaicExportPolicy(format: .png),
                to: URL(fileURLWithPath: "/tmp/mosaic.png")
            )
        }
        while !(await exporter.hasStarted()) { await Task.yield() }

        model.cancel()
        await task.value
        let wasCancelled = await exporter.wasCancelled()

        XCTAssertEqual(model.state, .cancelled)
        XCTAssertTrue(wasCancelled)
    }
}
