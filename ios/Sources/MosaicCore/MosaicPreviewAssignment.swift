import Foundation

public struct MosaicDescriptor: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let components: [Double]

    public init(
        version: Int = MosaicDescriptor.currentVersion,
        components: [Double]
    ) throws {
        guard version == Self.currentVersion else {
            throw MosaicAssignmentError.unsupportedDescriptorVersion(version)
        }
        guard !components.isEmpty else {
            throw MosaicAssignmentError.emptyDescriptor
        }
        guard components.allSatisfy(\.isFinite) else {
            throw MosaicAssignmentError.nonFiniteDescriptor
        }
        self.version = version
        self.components = components
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case components
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: values.decode(Int.self, forKey: .version),
            components: values.decode([Double].self, forKey: .components)
        )
    }
}

public struct MosaicSourceDescriptor: Codable, Equatable, Sendable {
    public let reference: AssetReference
    public let descriptor: MosaicDescriptor

    public init(reference: AssetReference, descriptor: MosaicDescriptor) {
        self.reference = reference
        self.descriptor = descriptor
    }
}

public struct MosaicTargetDescriptor: Codable, Equatable, Sendable {
    public let coordinate: TileCoordinate
    public let descriptor: MosaicDescriptor

    public init(coordinate: TileCoordinate, descriptor: MosaicDescriptor) {
        self.coordinate = coordinate
        self.descriptor = descriptor
    }
}

public struct MosaicAssignedTile: Codable, Equatable, Sendable {
    public let coordinate: TileCoordinate
    public let source: AssetReference

    public init(coordinate: TileCoordinate, source: AssetReference) {
        self.coordinate = coordinate
        self.source = source
    }
}

public struct MosaicPreviewAssignment: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let engineVersion: Int
    public let descriptorVersion: Int
    public let tiles: [MosaicAssignedTile]

    public init(
        engineVersion: Int,
        tiles: [MosaicAssignedTile]
    ) {
        self.version = Self.currentVersion
        self.engineVersion = engineVersion
        self.descriptorVersion = MosaicDescriptor.currentVersion
        self.tiles = tiles
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case engineVersion
        case descriptorVersion
        case tiles
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw MosaicAssignmentError.unsupportedAssignmentVersion(version)
        }
        let descriptorVersion = try values.decode(Int.self, forKey: .descriptorVersion)
        guard descriptorVersion == MosaicDescriptor.currentVersion else {
            throw MosaicAssignmentError.unsupportedDescriptorVersion(descriptorVersion)
        }
        self.version = version
        self.engineVersion = try values.decode(Int.self, forKey: .engineVersion)
        self.descriptorVersion = descriptorVersion
        self.tiles = try values.decode([MosaicAssignedTile].self, forKey: .tiles)
    }
}

public struct MosaicPreviewAssigner: Sendable {
    public init() {}

    public func assign(
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor],
        repeatWindow: Int,
        engineVersion: Int = MosaicRecipe.currentEngineVersion
    ) throws -> MosaicPreviewAssignment {
        let prepared = try prepare(
            targets: targets,
            sources: sources,
            repeatWindow: repeatWindow
        )
        var recentSources: [AssetReference] = []
        var tiles: [MosaicAssignedTile] = []
        tiles.reserveCapacity(prepared.targets.count)

        for target in prepared.targets {
            let selected = selectSource(
                for: target,
                from: prepared.sources,
                recentSources: recentSources,
                repeatWindow: repeatWindow
            )
            tiles.append(.init(coordinate: target.coordinate, source: selected.reference))
            recentSources.append(selected.reference)
        }

        return MosaicPreviewAssignment(
            engineVersion: engineVersion,
            tiles: tiles
        )
    }

    public func assign(
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor],
        repeatWindow: Int,
        engineVersion: Int = MosaicRecipe.currentEngineVersion,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicPreviewAssignment {
        try Task.checkCancellation()
        let prepared = try prepare(
            targets: targets,
            sources: sources,
            repeatWindow: repeatWindow
        )
        progress(.init(completed: 0, total: prepared.targets.count))
        var recentSources: [AssetReference] = []
        var tiles: [MosaicAssignedTile] = []
        tiles.reserveCapacity(prepared.targets.count)

        for (index, target) in prepared.targets.enumerated() {
            if index.isMultiple(of: 32) {
                await Task.yield()
            }
            try Task.checkCancellation()
            let selected = selectSource(
                for: target,
                from: prepared.sources,
                recentSources: recentSources,
                repeatWindow: repeatWindow
            )
            tiles.append(.init(coordinate: target.coordinate, source: selected.reference))
            recentSources.append(selected.reference)
            progress(.init(completed: tiles.count, total: prepared.targets.count))
        }
        try Task.checkCancellation()

        return MosaicPreviewAssignment(
            engineVersion: engineVersion,
            tiles: tiles
        )
    }

    private func prepare(
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor],
        repeatWindow: Int
    ) throws -> (targets: [MosaicTargetDescriptor], sources: [MosaicSourceDescriptor]) {
        guard repeatWindow >= 0 else {
            throw MosaicAssignmentError.negativeRepeatWindow
        }
        guard !sources.isEmpty else {
            throw MosaicAssignmentError.noSources
        }

        let componentCount = sources[0].descriptor.components.count
        for descriptor in sources.map(\.descriptor) + targets.map(\.descriptor) {
            guard descriptor.components.count == componentCount else {
                throw MosaicAssignmentError.inconsistentComponentCount(
                    expected: componentCount,
                    actual: descriptor.components.count
                )
            }
        }

        let sourceReferences = sources.map(\.reference)
        guard Set(sourceReferences).count == sourceReferences.count else {
            throw MosaicAssignmentError.duplicateSources
        }
        let targetCoordinates = targets.map(\.coordinate)
        guard Set(targetCoordinates).count == targetCoordinates.count else {
            throw MosaicAssignmentError.duplicateTargets
        }
        guard targetCoordinates.allSatisfy({ $0.column >= 0 && $0.row >= 0 }) else {
            throw MosaicAssignmentError.invalidCoordinate
        }

        let orderedSources = sources.sorted { sourceKey($0.reference) < sourceKey($1.reference) }
        let orderedTargets = targets.sorted {
            ($0.coordinate.row, $0.coordinate.column) < ($1.coordinate.row, $1.coordinate.column)
        }
        return (orderedTargets, orderedSources)
    }

    private func selectSource(
        for target: MosaicTargetDescriptor,
        from orderedSources: [MosaicSourceDescriptor],
        recentSources: [AssetReference],
        repeatWindow: Int
    ) -> MosaicSourceDescriptor {
        let recent = Set(recentSources.suffix(repeatWindow))
        let unrepeated = orderedSources.filter { !recent.contains($0.reference) }
        let candidates = unrepeated.isEmpty ? orderedSources : unrepeated
        return candidates.min { lhs, rhs in
            let lhsScore = squaredDistance(target.descriptor, lhs.descriptor)
            let rhsScore = squaredDistance(target.descriptor, rhs.descriptor)
            if lhsScore == rhsScore {
                return sourceKey(lhs.reference) < sourceKey(rhs.reference)
            }
            return lhsScore < rhsScore
        }!
    }

    private func squaredDistance(_ lhs: MosaicDescriptor, _ rhs: MosaicDescriptor) -> Double {
        zip(lhs.components, rhs.components).reduce(into: 0) { distance, pair in
            let difference = pair.0 - pair.1
            distance += difference * difference
        }
    }

    private func sourceKey(_ reference: AssetReference) -> String {
        "\(reference.origin.rawValue):\(reference.id)"
    }
}

public enum MosaicAssignmentError: Error, Equatable, Sendable {
    case unsupportedAssignmentVersion(Int)
    case unsupportedDescriptorVersion(Int)
    case emptyDescriptor
    case nonFiniteDescriptor
    case inconsistentComponentCount(expected: Int, actual: Int)
    case noSources
    case negativeRepeatWindow
    case duplicateSources
    case duplicateTargets
    case invalidCoordinate
}
