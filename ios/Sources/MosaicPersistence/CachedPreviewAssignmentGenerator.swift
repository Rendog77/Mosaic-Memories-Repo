import Foundation
import MosaicCore

public enum PreviewAssignmentOrigin: Equatable, Sendable {
    case cache
    case generatedAndCached
    case generatedWithoutCache
}

public struct PreviewAssignmentResult: Equatable, Sendable {
    public let assignment: MosaicPreviewAssignment
    public let origin: PreviewAssignmentOrigin

    public init(assignment: MosaicPreviewAssignment, origin: PreviewAssignmentOrigin) {
        self.assignment = assignment
        self.origin = origin
    }
}

public struct CachedPreviewAssignmentGenerator: Sendable {
    private let cache: any PreviewAssignmentCaching
    private let assigner: MosaicPreviewAssigner

    public init(
        cache: any PreviewAssignmentCaching,
        assigner: MosaicPreviewAssigner = .init()
    ) {
        self.cache = cache
        self.assigner = assigner
    }

    public func assignment(
        for project: MosaicProject,
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor],
        progress: @escaping @Sendable (MosaicProgress) -> Void = { _ in }
    ) async throws -> PreviewAssignmentResult {
        try Task.checkCancellation()
        try assigner.validate(
            targets: targets,
            sources: sources,
            repeatWindow: project.recipe.repeatWindow
        )
        guard Set(sources.map(\.reference)) == Set(project.sources) else {
            throw PreviewAssignmentGenerationError.sourcesDoNotMatchProject
        }

        if let cached = await cache.load(for: project) {
            try Task.checkCancellation()
            if matchesInputs(cached, project: project, targets: targets, sources: sources) {
                progress(.init(completed: targets.count, total: targets.count))
                return .init(assignment: cached, origin: .cache)
            }
            try? await cache.remove(for: project.id)
        }

        let generated = try await assigner.assign(
            targets: targets,
            sources: sources,
            repeatWindow: project.recipe.repeatWindow,
            engineVersion: project.recipe.engineVersion,
            progress: progress
        )
        try Task.checkCancellation()

        do {
            try await cache.save(generated, for: project)
        } catch {
            if Task.isCancelled {
                try? await cache.remove(for: project.id)
                throw CancellationError()
            }
            return .init(assignment: generated, origin: .generatedWithoutCache)
        }

        do {
            try Task.checkCancellation()
        } catch {
            try? await cache.remove(for: project.id)
            throw error
        }
        return .init(assignment: generated, origin: .generatedAndCached)
    }

    private func matchesInputs(
        _ assignment: MosaicPreviewAssignment,
        project: MosaicProject,
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor]
    ) -> Bool {
        guard assignment.engineVersion == project.recipe.engineVersion else { return false }
        let expectedCoordinates = Set(targets.map(\.coordinate))
        let assignedCoordinates = assignment.tiles.map(\.coordinate)
        guard assignedCoordinates.count == expectedCoordinates.count,
              Set(assignedCoordinates) == expectedCoordinates else {
            return false
        }
        let availableSources = Set(sources.map(\.reference))
        return assignment.tiles.allSatisfy { availableSources.contains($0.source) }
    }
}

public enum PreviewAssignmentGenerationError: Error, Equatable, Sendable {
    case sourcesDoNotMatchProject
}
