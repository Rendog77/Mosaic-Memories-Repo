import Foundation
import MosaicCore

public protocol ProjectStoring: Sendable {
    func load(id: UUID) async throws -> MosaicProject?
    func save(_ project: MosaicProject) async throws
    func delete(id: UUID) async throws
    func list() async throws -> [MosaicProject]
    func catalog() async throws -> ProjectCatalog
}

public struct ProjectCatalog: Equatable, Sendable {
    public let projects: [MosaicProject]
    public let unreadableProjectCount: Int

    public init(projects: [MosaicProject], unreadableProjectCount: Int = 0) {
        self.projects = projects
        self.unreadableProjectCount = unreadableProjectCount
    }
}

public actor JSONProjectStore: ProjectStoring {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(id: UUID) throws -> MosaicProject? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let project = try decoder.decode(MosaicProject.self, from: Data(contentsOf: url))
        guard project.schemaVersion <= MosaicProject.currentSchemaVersion else {
            throw ProjectStoreError.unsupportedSchema(project.schemaVersion)
        }
        return project
    }

    public func save(_ project: MosaicProject) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(project).write(to: fileURL(for: project.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func list() throws -> [MosaicProject] {
        try catalog().projects
    }

    public func catalog() throws -> ProjectCatalog {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ProjectCatalog(projects: [])
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        var projects: [MosaicProject] = []
        var unreadableProjectCount = 0
        for file in files {
            do {
                let project = try decoder.decode(MosaicProject.self, from: Data(contentsOf: file))
                guard project.schemaVersion <= MosaicProject.currentSchemaVersion else {
                    unreadableProjectCount += 1
                    continue
                }
                projects.append(project)
            } catch {
                unreadableProjectCount += 1
            }
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
        return ProjectCatalog(projects: projects, unreadableProjectCount: unreadableProjectCount)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

public enum ProjectStoreError: Error, Equatable {
    case unsupportedSchema(Int)
}

public actor InMemoryProjectStore: ProjectStoring {
    private var projects: [UUID: MosaicProject]

    public init(projects: [MosaicProject] = []) {
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    public func load(id: UUID) -> MosaicProject? {
        projects[id]
    }

    public func save(_ project: MosaicProject) {
        projects[project.id] = project
    }

    public func delete(id: UUID) {
        projects[id] = nil
    }

    public func list() -> [MosaicProject] {
        sortedProjects()
    }

    public func catalog() -> ProjectCatalog {
        ProjectCatalog(projects: sortedProjects())
    }

    private func sortedProjects() -> [MosaicProject] {
        projects.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
