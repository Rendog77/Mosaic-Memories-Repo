import Foundation
import MosaicCore

public enum CreationStep: Int, CaseIterable, Codable, Sendable {
    case hero
    case memories
    case sourceReview
    case preview
    case edit
    case export
}

public enum SourceSetReadiness: Equatable, Sendable {
    case needsMore(required: Int, actual: Int)
    case ready(count: Int)
}

public struct CreationWorkflow: Equatable, Sendable {
    public private(set) var project: MosaicProject
    public private(set) var step: CreationStep

    public init(project: MosaicProject = .init(), step: CreationStep = .hero) {
        self.project = project
        self.step = step
    }

    public mutating func selectHero(_ hero: AssetReference) {
        project.hero = hero
        touch()
        step = .memories
    }

    public mutating func confirmSources(_ sources: [AssetReference], minimum: Int = 100) throws {
        reviewSources(sources)
        try confirmReviewedSources(minimum: minimum)
    }

    public mutating func reviewSources(_ sources: [AssetReference]) {
        project.sources = sources
        touch()
        step = .sourceReview
    }

    @discardableResult
    public mutating func removeSource(id: String) -> Bool {
        let originalCount = project.sources.count
        project.sources.removeAll { $0.id == id }
        guard project.sources.count != originalCount else { return false }
        touch()
        step = .sourceReview
        return true
    }

    public func sourceReadiness(minimum: Int = 100) -> SourceSetReadiness {
        if project.sources.count < minimum {
            return .needsMore(required: minimum, actual: project.sources.count)
        }
        return .ready(count: project.sources.count)
    }

    public mutating func confirmReviewedSources(minimum: Int = 100) throws {
        let sources = project.sources
        guard sources.count >= minimum else {
            throw CreationWorkflowError.insufficientSources(required: minimum, actual: sources.count)
        }
        touch()
        step = .preview
    }

    public mutating func move(to step: CreationStep) {
        self.step = step
    }

    public mutating func renameProject(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        project.title = trimmed.isEmpty ? "Untitled Mosaic" : trimmed
        touch()
    }

    private mutating func touch() {
        project.updatedAt = Date()
    }
}

public enum CreationWorkflowError: Error, Equatable {
    case insufficientSources(required: Int, actual: Int)
}
