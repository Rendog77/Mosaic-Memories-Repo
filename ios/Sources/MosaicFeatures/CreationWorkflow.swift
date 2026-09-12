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
        guard sources.count >= minimum else {
            throw CreationWorkflowError.insufficientSources(required: minimum, actual: sources.count)
        }
        project.sources = sources
        touch()
        step = .preview
    }

    public mutating func move(to step: CreationStep) {
        self.step = step
    }

    private mutating func touch() {
        project.updatedAt = Date()
    }
}

public enum CreationWorkflowError: Error, Equatable {
    case insufficientSources(required: Int, actual: Int)
}

