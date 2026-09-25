import Foundation
import XCTest
import MosaicCore
@testable import MosaicAppUI

private struct SuccessfulPreviewGenerator: MosaicPreviewGenerating {
    let output: MosaicPreviewOutput

    func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        progress(.init(stage: .analyzingPhotos, completed: 1, total: 2))
        await Task.yield()
        progress(.init(stage: .renderingMosaic, completed: 2, total: 2))
        return output
    }
}

private struct FailingPreviewGenerator: MosaicPreviewGenerating {
    struct Failure: Error {}

    func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        throw Failure()
    }
}

private actor CancellablePreviewGenerator: MosaicPreviewGenerating {
    private(set) var started = false
    private(set) var observedCancellation = false

    func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        started = true
        progress(.init(stage: .analyzingPhotos, completed: 0, total: 10))
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return .init(data: Data(), width: 1, height: 1, columns: 1, rows: 1, tiles: [])
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func wasCancelled() -> Bool {
        observedCancellation
    }

    func hasStarted() -> Bool {
        started
    }
}

final class MosaicPreviewViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulLoadPublishesRenderedOutput() async {
        let source = AssetReference(id: "source", origin: .testFixture)
        let output = MosaicPreviewOutput(
            data: Data([1, 2, 3]),
            width: 640,
            height: 480,
            columns: 1,
            rows: 1,
            tiles: [.init(coordinate: .init(column: 0, row: 0), source: source)]
        )
        let model = MosaicPreviewViewModel(generator: SuccessfulPreviewGenerator(output: output))

        await model.load(project: .init())

        XCTAssertEqual(model.state, .loaded(output))
    }

    @MainActor
    func testFailurePublishesActionableRetryMessage() async {
        let model = MosaicPreviewViewModel(generator: FailingPreviewGenerator())

        await model.load(project: .init())

        guard case .failed(let message) = model.state else {
            return XCTFail("Expected failed preview state")
        }
        XCTAssertTrue(message.contains("try again"))
    }

    @MainActor
    func testCancelStopsActiveGeneration() async {
        let generator = CancellablePreviewGenerator()
        let model = MosaicPreviewViewModel(generator: generator)
        let loadTask = Task { await model.load(project: .init()) }
        while !(await generator.hasStarted()) {
            await Task.yield()
        }

        model.cancel()
        await loadTask.value
        let wasCancelled = await generator.wasCancelled()

        XCTAssertEqual(model.state, .cancelled)
        XCTAssertTrue(wasCancelled)
    }

    func testProgressFractionIsClampedAndHandlesEmptyTotals() {
        XCTAssertEqual(
            MosaicPreviewGenerationStatus(
                stage: .preparing,
                completed: 1,
                total: 0
            ).fractionCompleted,
            0
        )
        XCTAssertEqual(
            MosaicPreviewGenerationStatus(
                stage: .renderingMosaic,
                completed: 12,
                total: 10
            ).fractionCompleted,
            1
        )
    }

    func testNormalizedPointMapsToAssignedTile() {
        let left = AssetReference(id: "left", origin: .testFixture)
        let right = AssetReference(id: "right", origin: .testFixture)
        let output = MosaicPreviewOutput(
            data: Data([1]),
            width: 200,
            height: 100,
            columns: 2,
            rows: 1,
            tiles: [
                .init(coordinate: .init(column: 0, row: 0), source: left),
                .init(coordinate: .init(column: 1, row: 0), source: right),
            ]
        )

        XCTAssertEqual(output.tile(normalizedX: 0.1, normalizedY: 0.5)?.source, left)
        XCTAssertEqual(output.tile(normalizedX: 0.9, normalizedY: 0.5)?.source, right)
        XCTAssertNil(output.tile(normalizedX: 1, normalizedY: 0.5))
        XCTAssertNil(output.tile(normalizedX: -0.1, normalizedY: 0.5))
    }
}
