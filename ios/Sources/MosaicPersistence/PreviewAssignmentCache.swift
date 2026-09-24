import Foundation
import MosaicCore

public protocol PreviewAssignmentCaching: Sendable {
    func load(for project: MosaicProject) async -> MosaicPreviewAssignment?
    func save(_ assignment: MosaicPreviewAssignment, for project: MosaicProject) async throws
    func remove(for projectID: UUID) async throws
}

public actor JSONPreviewAssignmentCache: PreviewAssignmentCaching {
    private static let documentVersion = 1

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(for project: MosaicProject) -> MosaicPreviewAssignment? {
        let url = fileURL(for: project.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let document = try decoder.decode(
                CachedPreviewAssignment.self,
                from: Data(contentsOf: url)
            )
            guard document.version == Self.documentVersion,
                  document.key == CacheKey(project: project),
                  Self.matchesProject(document.assignment, project: project) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return document.assignment
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func save(
        _ assignment: MosaicPreviewAssignment,
        for project: MosaicProject
    ) throws {
        guard Self.matchesProject(assignment, project: project) else {
            throw PreviewAssignmentCacheError.assignmentDoesNotMatchProject
        }
        let document = CachedPreviewAssignment(
            version: Self.documentVersion,
            key: CacheKey(project: project),
            assignment: assignment
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: fileURL(for: project.id), options: .atomic)
    }

    public func remove(for projectID: UUID) throws {
        let url = fileURL(for: projectID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for projectID: UUID) -> URL {
        directory
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("preview.json")
    }

    private static func matchesProject(
        _ assignment: MosaicPreviewAssignment,
        project: MosaicProject
    ) -> Bool {
        guard assignment.engineVersion == project.recipe.engineVersion else { return false }
        let permittedSources = Set(project.sources + Array(project.recipe.replacements.values))
        guard assignment.tiles.allSatisfy({ permittedSources.contains($0.source) }) else {
            return false
        }
        let coordinates = assignment.tiles.map(\.coordinate)
        return Set(coordinates).count == coordinates.count
    }
}

public enum PreviewAssignmentCacheError: Error, Equatable, Sendable {
    case assignmentDoesNotMatchProject
}

private struct CachedPreviewAssignment: Codable {
    let version: Int
    let key: CacheKey
    let assignment: MosaicPreviewAssignment
}

private struct CacheKey: Codable, Equatable {
    let projectID: UUID
    let hero: AssetReference?
    let heroCrop: HeroCrop?
    let sources: [AssetReference]
    let recipe: MosaicRecipe

    init(project: MosaicProject) {
        projectID = project.id
        hero = project.hero
        heroCrop = project.heroCrop
        sources = project.sources.sorted {
            ($0.origin.rawValue, $0.id) < ($1.origin.rawValue, $1.id)
        }
        recipe = project.recipe
    }
}
