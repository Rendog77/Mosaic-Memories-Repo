import Combine
import Foundation
import MosaicCore
import MosaicFeatures

public protocol MosaicExporting: Sendable {
    func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult
}

public struct UnavailableMosaicExporter: MosaicExporting {
    public init() {}

    public func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult {
        throw MosaicExportWorkflowError.unavailable
    }
}

public enum MosaicExportWorkflowError: Error, Equatable, Sendable {
    case unavailable
}

public enum MosaicExportViewState: Equatable, Sendable {
    case idle
    case exporting(MosaicProgress)
    case completed(MosaicExportResult)
    case cancelled
    case failed(String)
}

@MainActor
public final class MosaicExportViewModel: ObservableObject {
    @Published public private(set) var state: MosaicExportViewState = .idle

    private let exporter: any MosaicExporting
    private let fileStore: any MosaicExportFileManaging
    private var exportTask: Task<MosaicExportResult, Error>?
    private var exportID: UUID?

    public init(
        exporter: any MosaicExporting = UnavailableMosaicExporter(),
        fileStore: any MosaicExportFileManaging = MosaicExportFileStore()
    ) {
        self.exporter = exporter
        self.fileStore = fileStore
    }

    public func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy
    ) async {
        cancel(updateState: false)
        let identifier = UUID()
        exportID = identifier
        state = .exporting(.init(completed: 0, total: max(1, tiles.count + 2)))
        let exporter = self.exporter
        let fileStore = self.fileStore
        let destination: URL
        do {
            destination = try await fileStore.destination(
                for: project.id,
                format: policy.format
            )
        } catch {
            guard exportID == identifier else { return }
            exportID = nil
            state = .failed(Self.message(for: error))
            return
        }
        guard exportID == identifier else { return }
        let task = Task {
            do {
                let result = try await exporter.export(
                    project: project,
                    tiles: tiles,
                    policy: policy,
                    to: destination
                ) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.exportID == identifier else { return }
                        self?.state = .exporting(progress)
                    }
                }
                try Task.checkCancellation()
                try await fileStore.record(result, for: project)
                return result
            } catch {
                await fileStore.discardFile(at: destination)
                throw error
            }
        }
        exportTask = task

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard exportID == identifier else { return }
            exportTask = nil
            exportID = nil
            state = .completed(result)
        } catch is CancellationError {
            guard exportID == identifier else { return }
            exportTask = nil
            exportID = nil
            state = .cancelled
        } catch {
            guard exportID == identifier else { return }
            exportTask = nil
            exportID = nil
            state = .failed(Self.message(for: error))
        }
    }

    public func cancel(updateState: Bool = true) {
        exportTask?.cancel()
        exportTask = nil
        exportID = nil
        if updateState { state = .cancelled }
    }

    public func reset() {
        cancel(updateState: false)
        state = .idle
    }

    public func recover(for project: MosaicProject) async {
        guard case .idle = state else { return }
        await fileStore.purgeAbandonedFiles(
            olderThan: Date().addingTimeInterval(-24 * 60 * 60)
        )
        await fileStore.purgeExpiredExports(
            olderThan: Date().addingTimeInterval(-7 * 24 * 60 * 60)
        )
        guard case .idle = state else { return }
        if let result = await fileStore.recover(for: project),
           case .idle = state {
            state = .completed(result)
        }
    }

    public func discardExport(for projectID: UUID) async {
        cancel(updateState: false)
        await fileStore.discardExport(for: projectID)
        state = .idle
    }

    private static func message(for error: Error) -> String {
        if let exportError = error as? MosaicExportError,
           case .insufficientStorage = exportError {
            return "There is not enough free storage to create this image. Free some space and try again."
        }
        if error as? MosaicExportWorkflowError == .unavailable {
            return "High-quality export is unavailable on this device."
        }
        return "The high-quality image could not be created. Check that the selected photos are available, then try again."
    }
}
