import Combine
import Foundation
import MosaicCore

public enum MosaicPreviewGenerationStage: String, Equatable, Sendable {
    case preparing
    case analyzingPhotos
    case arrangingTiles
    case renderingMosaic

    public var title: String {
        switch self {
        case .preparing: return "Preparing preview"
        case .analyzingPhotos: return "Analyzing photos"
        case .arrangingTiles: return "Arranging tiles"
        case .renderingMosaic: return "Rendering mosaic"
        }
    }
}

public struct MosaicPreviewGenerationStatus: Equatable, Sendable {
    public let stage: MosaicPreviewGenerationStage
    public let completed: Int
    public let total: Int

    public init(stage: MosaicPreviewGenerationStage, completed: Int, total: Int) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct MosaicPreviewOutput: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let columns: Int
    public let rows: Int
    public let tiles: [MosaicAssignedTile]

    public init(
        data: Data,
        width: Int,
        height: Int,
        columns: Int,
        rows: Int,
        tiles: [MosaicAssignedTile]
    ) {
        self.data = data
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.tiles = tiles
    }

    public var isValid: Bool {
        guard !data.isEmpty, width > 0, height > 0, columns > 0, rows > 0 else {
            return false
        }
        let (expectedCount, overflow) = columns.multipliedReportingOverflow(by: rows)
        guard !overflow, tiles.count == expectedCount else { return false }
        guard tiles.allSatisfy({
            $0.coordinate.column >= 0 && $0.coordinate.column < columns &&
                $0.coordinate.row >= 0 && $0.coordinate.row < rows
        }) else {
            return false
        }
        return Set(tiles.map(\.coordinate)).count == tiles.count
    }

    public func tile(normalizedX: Double, normalizedY: Double) -> MosaicAssignedTile? {
        guard normalizedX.isFinite, normalizedY.isFinite,
              normalizedX >= 0, normalizedX < 1,
              normalizedY >= 0, normalizedY < 1,
              columns > 0, rows > 0 else {
            return nil
        }
        let coordinate = TileCoordinate(
            column: min(columns - 1, Int(normalizedX * Double(columns))),
            row: min(rows - 1, Int(normalizedY * Double(rows)))
        )
        return tiles.first { $0.coordinate == coordinate }
    }
}

public protocol MosaicPreviewGenerating: Sendable {
    func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput

    func renderPreview(
        for project: MosaicProject,
        tiles: [MosaicAssignedTile],
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput
}

public extension MosaicPreviewGenerating {
    func renderPreview(
        for project: MosaicProject,
        tiles: [MosaicAssignedTile],
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        try await generatePreview(for: project, progress: progress)
    }
}

public struct UnavailableMosaicPreviewGenerator: MosaicPreviewGenerating {
    public init() {}

    public func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        throw MosaicPreviewGenerationError.unavailable
    }
}

public enum MosaicPreviewGenerationError: Error, Equatable, Sendable {
    case unavailable
}

public enum MosaicPreviewViewState: Equatable, Sendable {
    case idle
    case loading(MosaicPreviewGenerationStatus)
    case loaded(MosaicPreviewOutput)
    case cancelled
    case failed(String)
}

@MainActor
public final class MosaicPreviewViewModel: ObservableObject {
    @Published public private(set) var state: MosaicPreviewViewState = .idle
    @Published public private(set) var refreshStatus: MosaicPreviewGenerationStatus?
    @Published public private(set) var refreshMessage: String?

    private let generator: any MosaicPreviewGenerating
    private var generationTask: Task<MosaicPreviewOutput, Error>?
    private var generationID: UUID?

    public init(generator: any MosaicPreviewGenerating = UnavailableMosaicPreviewGenerator()) {
        self.generator = generator
    }

    public func load(project: MosaicProject) async {
        cancelActiveGeneration(updateState: false)
        refreshMessage = nil
        let identifier = UUID()
        generationID = identifier
        state = .loading(.init(stage: .preparing, completed: 0, total: 1))
        let generator = self.generator
        let task = Task {
            try await generator.generatePreview(for: project) { [weak self] progress in
                Task { @MainActor in
                    guard self?.generationID == identifier else { return }
                    self?.state = .loading(progress)
                }
            }
        }
        generationTask = task

        do {
            let output = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generationID == identifier else { return }
            generationTask = nil
            generationID = nil
            if !output.isValid {
                state = .failed(
                    "The generated preview image was invalid. Please try creating it again."
                )
            } else {
                state = .loaded(output)
            }
        } catch is CancellationError {
            guard generationID == identifier else { return }
            generationTask = nil
            generationID = nil
            state = .cancelled
        } catch {
            guard generationID == identifier else { return }
            generationTask = nil
            generationID = nil
            state = .failed(Self.message(for: error))
        }
    }

    @discardableResult
    public func rerender(
        project: MosaicProject,
        tiles requestedTiles: [MosaicAssignedTile]? = nil
    ) async -> Bool {
        guard case .loaded(let existingOutput) = state else { return false }
        let tiles = requestedTiles ?? existingOutput.tiles
        cancelActiveGeneration(updateState: false)
        let identifier = UUID()
        generationID = identifier
        refreshMessage = nil
        refreshStatus = .init(stage: .renderingMosaic, completed: 0, total: 1)
        let generator = self.generator
        let task = Task {
            try await generator.renderPreview(
                for: project,
                tiles: tiles
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.generationID == identifier else { return }
                    self?.refreshStatus = progress
                }
            }
        }
        generationTask = task

        do {
            let output = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generationID == identifier else { return false }
            generationTask = nil
            generationID = nil
            refreshStatus = nil
            guard output.isValid, output.tiles == tiles else {
                refreshMessage = "The updated preview was invalid. Your previous preview is still available."
                return false
            }
            state = .loaded(output)
            return true
        } catch is CancellationError {
            guard generationID == identifier else { return false }
            generationTask = nil
            generationID = nil
            refreshStatus = nil
            return false
        } catch {
            guard generationID == identifier else { return false }
            generationTask = nil
            generationID = nil
            refreshStatus = nil
            refreshMessage = "The edited preview could not be updated. Your previous preview is still available."
            return false
        }
    }

    public func cancel() {
        cancelActiveGeneration(updateState: true)
    }

    private func cancelActiveGeneration(updateState: Bool) {
        let wasLoading: Bool
        if case .loading = state { wasLoading = true } else { wasLoading = false }
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
        refreshStatus = nil
        if updateState && wasLoading {
            state = .cancelled
        }
    }

    private static func message(for error: Error) -> String {
        if error is MosaicPreviewGenerationError {
            return "Preview generation is not available in this build."
        }
        return "Your mosaic preview could not be created. Check that the selected photos are available and try again."
    }
}
