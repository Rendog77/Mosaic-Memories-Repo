import Foundation

public struct MosaicProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

public struct MosaicRender: Equatable, Sendable {
    public let projectID: UUID
    public let engineVersion: Int
    public let width: Int
    public let height: Int

    public init(projectID: UUID, engineVersion: Int, width: Int, height: Int) {
        self.projectID = projectID
        self.engineVersion = engineVersion
        self.width = width
        self.height = height
    }
}

public protocol MosaicGenerating: Sendable {
    func preview(
        project: MosaicProject,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicRender
}

