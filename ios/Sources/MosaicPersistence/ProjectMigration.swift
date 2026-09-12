import Foundation
import MosaicCore

public protocol ProjectMigrating: Sendable {
    func migrate(data: Data) throws -> Data
}

public struct DefaultProjectMigrator: ProjectMigrating {
    public init() {}

    public func migrate(data: Data) throws -> Data {
        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectStoreError.invalidDocument
        }

        var version = document["schemaVersion"] as? Int ?? 0
        guard version <= MosaicProject.currentSchemaVersion else {
            throw ProjectStoreError.unsupportedSchema(version)
        }

        while version < MosaicProject.currentSchemaVersion {
            switch version {
            case 0:
                document = try migrateVersionZeroToOne(document)
                version = 1
            default:
                throw ProjectStoreError.noMigrationPath(
                    from: version,
                    to: MosaicProject.currentSchemaVersion
                )
            }
        }

        guard JSONSerialization.isValidJSONObject(document) else {
            throw ProjectStoreError.invalidDocument
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func migrateVersionZeroToOne(_ original: [String: Any]) throws -> [String: Any] {
        var document = original
        guard var recipe = document["recipe"] as? [String: Any] else {
            throw ProjectStoreError.invalidDocument
        }
        document["schemaVersion"] = 1
        recipe["engineVersion"] = recipe["engineVersion"] ?? 1
        recipe["replacements"] = recipe["replacements"] ?? []
        document["recipe"] = recipe
        return document
    }
}

