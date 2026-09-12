import Foundation
import MosaicCore

public protocol ProjectStoring: Sendable {
    func load(id: UUID) async throws -> MosaicProject?
    func save(_ project: MosaicProject) async throws
    func delete(id: UUID) async throws
    func list() async throws -> [MosaicProject]
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
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decoder.decode(MosaicProject.self, from: Data(contentsOf: $0)) }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

public enum ProjectStoreError: Error, Equatable {
    case unsupportedSchema(Int)
}
