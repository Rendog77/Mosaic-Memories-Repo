import Foundation

public struct MosaicProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 3

    public let id: UUID
    public var schemaVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    public var hero: AssetReference?
    public var heroCrop: HeroCrop?
    public var sources: [AssetReference]
    public var sourcesConfirmed: Bool
    public var recipe: MosaicRecipe

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = MosaicProject.currentSchemaVersion,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "Untitled Mosaic",
        hero: AssetReference? = nil,
        heroCrop: HeroCrop? = nil,
        sources: [AssetReference] = [],
        sourcesConfirmed: Bool = false,
        recipe: MosaicRecipe = .init()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.hero = hero
        self.heroCrop = heroCrop
        self.sources = sources
        self.sourcesConfirmed = sourcesConfirmed
        self.recipe = recipe
    }
}

public struct HeroCrop: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1 else {
            throw HeroCropError.invalidBounds
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: values.decode(Double.self, forKey: .x),
            y: values.decode(Double.self, forKey: .y),
            width: values.decode(Double.self, forKey: .width),
            height: values.decode(Double.self, forKey: .height)
        )
    }
}

public enum HeroCropError: Error, Equatable, Sendable {
    case invalidBounds
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
