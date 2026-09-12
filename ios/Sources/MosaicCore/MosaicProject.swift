import Foundation

public struct MosaicProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var schemaVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    public var hero: AssetReference?
    public var sources: [AssetReference]
    public var recipe: MosaicRecipe

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = MosaicProject.currentSchemaVersion,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "Untitled Mosaic",
        hero: AssetReference? = nil,
        sources: [AssetReference] = [],
        recipe: MosaicRecipe = .init()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.hero = hero
        self.sources = sources
        self.recipe = recipe
    }
}

public struct AssetReference: Codable, Equatable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case photoPicker
        case photoLibrary
        case importedFile
        case testFixture
    }

    public let id: String
    public let origin: Origin

    public init(id: String, origin: Origin) {
        self.id = id
        self.origin = origin
    }
}

public struct MosaicRecipe: Codable, Equatable, Sendable {
    public static let currentEngineVersion = 1

    public var engineVersion: Int
    public var columns: Int
    public var likeness: Double
    public var repeatWindow: Int
    public var replacements: [TileCoordinate: AssetReference]

    public init(
        engineVersion: Int = MosaicRecipe.currentEngineVersion,
        columns: Int = 50,
        likeness: Double = 0.5,
        repeatWindow: Int = 8,
        replacements: [TileCoordinate: AssetReference] = [:]
    ) {
        self.engineVersion = engineVersion
        self.columns = columns
        self.likeness = likeness
        self.repeatWindow = repeatWindow
        self.replacements = replacements
    }
}

public struct TileCoordinate: Codable, Equatable, Hashable, Sendable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}
