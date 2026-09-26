import Foundation

public enum MosaicQualityCriterion: String, Codable, CaseIterable, Equatable, Sendable {
    case heroLikeness
    case tileAuthenticity
    case tileDiversity
    case cropSafety
}

public struct MosaicQualityRubric: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let maximumMeanHeroDeltaE: Double
    public let maximumP90HeroDeltaE: Double
    public let minimumTileAuthenticity: Double
    public let minimumSourceDiversity: Double
    public let maximumAdjacentRepeatRatio: Double
    public let minimumSubjectCoverage: Double

    public init(
        version: Int = MosaicQualityRubric.currentVersion,
        maximumMeanHeroDeltaE: Double,
        maximumP90HeroDeltaE: Double,
        minimumTileAuthenticity: Double,
        minimumSourceDiversity: Double,
        maximumAdjacentRepeatRatio: Double,
        minimumSubjectCoverage: Double
    ) {
        self.version = version
        self.maximumMeanHeroDeltaE = maximumMeanHeroDeltaE
        self.maximumP90HeroDeltaE = maximumP90HeroDeltaE
        self.minimumTileAuthenticity = minimumTileAuthenticity
        self.minimumSourceDiversity = minimumSourceDiversity
        self.maximumAdjacentRepeatRatio = maximumAdjacentRepeatRatio
        self.minimumSubjectCoverage = minimumSubjectCoverage
    }

    public static let provisional = MosaicQualityRubric(
        maximumMeanHeroDeltaE: 18,
        maximumP90HeroDeltaE: 28,
        minimumTileAuthenticity: 0.35,
        minimumSourceDiversity: 0.60,
        maximumAdjacentRepeatRatio: 0.05,
        minimumSubjectCoverage: 0.90
    )
}

public struct MosaicQualityMetrics: Codable, Equatable, Sendable {
    public let meanHeroDeltaE: Double
    public let p90HeroDeltaE: Double
    public let tileAuthenticity: Double
    public let sourceDiversity: Double
    public let adjacentRepeatRatio: Double
    public let subjectCoverage: Double
}

public struct MosaicQualityEvaluation: Codable, Equatable, Sendable {
    public let metrics: MosaicQualityMetrics
    public let failedCriteria: [MosaicQualityCriterion]

    public var passed: Bool { failedCriteria.isEmpty }
}

public struct MosaicQualityGateSummary: Codable, Equatable, Sendable {
    public let passingProjects: Int
    public let totalProjects: Int
    public let minimumPassingProjects: Int

    public var passed: Bool {
        totalProjects > 0 && passingProjects >= minimumPassingProjects
    }
}

public struct MosaicQualityEvaluator: Sendable {
    private static let unavailableSourceDeltaE = 400.0

    public init() {}

    public func summarize(
        _ evaluations: [MosaicQualityEvaluation],
        minimumPassingProjects: Int,
        requiredProjectCount: Int = 10
    ) throws -> MosaicQualityGateSummary {
        guard requiredProjectCount > 0,
              evaluations.count == requiredProjectCount,
              minimumPassingProjects > 0,
              minimumPassingProjects <= requiredProjectCount else {
            throw MosaicQualityEvaluationError.invalidGate
        }
        return MosaicQualityGateSummary(
            passingProjects: evaluations.filter(\.passed).count,
            totalProjects: evaluations.count,
            minimumPassingProjects: minimumPassingProjects
        )
    }

    public func evaluate(
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor],
        subjectBounds: HeroCrop,
        rubric: MosaicQualityRubric = .provisional
    ) throws -> MosaicQualityEvaluation {
        guard isValid(rubric) else { throw MosaicQualityEvaluationError.invalidRubric }
        guard project.recipe.likeness.isFinite,
              (0...1).contains(project.recipe.likeness),
              project.sourcesConfirmed,
              !targets.isEmpty,
              !sources.isEmpty,
              targets.allSatisfy({ $0.descriptor.components.count == 3 }),
              sources.allSatisfy({ $0.descriptor.components.count == 3 }) else {
            throw MosaicQualityEvaluationError.invalidInputs
        }

        let targetCoordinates = targets.map(\.coordinate)
        let tileCoordinates = assignment.tiles.map(\.coordinate)
        let sourceReferences = sources.map(\.reference)
        guard assignment.engineVersion == project.recipe.engineVersion,
              Set(targetCoordinates).count == targets.count,
              Set(tileCoordinates).count == assignment.tiles.count,
              Set(targetCoordinates) == Set(tileCoordinates),
              Set(sourceReferences).count == sourceReferences.count,
              Set(project.sources).count == project.sources.count,
              Set(project.sources) == Set(sourceReferences) else {
            throw MosaicQualityEvaluationError.assignmentDoesNotMatchInputs
        }

        let targetsByCoordinate = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.coordinate, $0.descriptor) }
        )
        let sourcesByReference = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.reference, $0.descriptor) }
        )
        let orderedTiles = assignment.tiles.sorted {
            ($0.coordinate.row, $0.coordinate.column) <
                ($1.coordinate.row, $1.coordinate.column)
        }

        var validSourceCount = 0
        var usedSources = Set<AssetReference>()
        var deltaEValues: [Double] = []
        deltaEValues.reserveCapacity(orderedTiles.count)
        for tile in orderedTiles {
            guard let target = targetsByCoordinate[tile.coordinate],
                  let source = sourcesByReference[tile.source] else {
                deltaEValues.append(Self.unavailableSourceDeltaE)
                continue
            }
            validSourceCount += 1
            usedSources.insert(tile.source)
            deltaEValues.append(deltaE(target, source))
        }

        let likenessPreservation = 1 - project.recipe.likeness
        let estimatedDeltaE = deltaEValues.map { $0 * likenessPreservation }
        let meanDeltaE = estimatedDeltaE.reduce(0, +) / Double(estimatedDeltaE.count)
        let sortedDeltaE = estimatedDeltaE.sorted()
        let p90Index = min(
            sortedDeltaE.count - 1,
            max(0, Int(ceil(Double(sortedDeltaE.count) * 0.9)) - 1)
        )
        let authenticity = Double(validSourceCount) / Double(orderedTiles.count) *
            likenessPreservation
        let diversityDenominator = max(1, min(sources.count, orderedTiles.count))
        let diversity = Double(usedSources.count) / Double(diversityDenominator)
        let adjacentRepeatRatio = adjacentRepeatRatio(in: orderedTiles)
        let crop: HeroCrop
        if let heroCrop = project.heroCrop {
            crop = heroCrop
        } else {
            crop = try HeroCrop(x: 0, y: 0, width: 1, height: 1)
        }
        let subjectCoverage = coverage(of: subjectBounds, within: crop)

        let metrics = MosaicQualityMetrics(
            meanHeroDeltaE: meanDeltaE,
            p90HeroDeltaE: sortedDeltaE[p90Index],
            tileAuthenticity: authenticity,
            sourceDiversity: diversity,
            adjacentRepeatRatio: adjacentRepeatRatio,
            subjectCoverage: subjectCoverage
        )
        var failedCriteria: [MosaicQualityCriterion] = []
        if metrics.meanHeroDeltaE > rubric.maximumMeanHeroDeltaE ||
            metrics.p90HeroDeltaE > rubric.maximumP90HeroDeltaE {
            failedCriteria.append(.heroLikeness)
        }
        if metrics.tileAuthenticity < rubric.minimumTileAuthenticity {
            failedCriteria.append(.tileAuthenticity)
        }
        if metrics.sourceDiversity < rubric.minimumSourceDiversity ||
            metrics.adjacentRepeatRatio > rubric.maximumAdjacentRepeatRatio {
            failedCriteria.append(.tileDiversity)
        }
        if metrics.subjectCoverage < rubric.minimumSubjectCoverage {
            failedCriteria.append(.cropSafety)
        }
        return MosaicQualityEvaluation(metrics: metrics, failedCriteria: failedCriteria)
    }

    private func isValid(_ rubric: MosaicQualityRubric) -> Bool {
        rubric.version == MosaicQualityRubric.currentVersion &&
            rubric.maximumMeanHeroDeltaE.isFinite && rubric.maximumMeanHeroDeltaE >= 0 &&
            rubric.maximumP90HeroDeltaE.isFinite && rubric.maximumP90HeroDeltaE >= 0 &&
            rubric.minimumTileAuthenticity.isFinite &&
            (0...1).contains(rubric.minimumTileAuthenticity) &&
            rubric.minimumSourceDiversity.isFinite &&
            (0...1).contains(rubric.minimumSourceDiversity) &&
            rubric.maximumAdjacentRepeatRatio.isFinite &&
            (0...1).contains(rubric.maximumAdjacentRepeatRatio) &&
            rubric.minimumSubjectCoverage.isFinite &&
            (0...1).contains(rubric.minimumSubjectCoverage)
    }

    private func deltaE(_ lhs: MosaicDescriptor, _ rhs: MosaicDescriptor) -> Double {
        sqrt(zip(lhs.components, rhs.components).reduce(into: 0) { result, pair in
            let difference = pair.0 - pair.1
            result += difference * difference
        })
    }

    private func adjacentRepeatRatio(in tiles: [MosaicAssignedTile]) -> Double {
        guard tiles.count > 1 else { return 0 }
        let repeats = zip(tiles, tiles.dropFirst()).reduce(into: 0) { count, pair in
            if pair.0.source == pair.1.source { count += 1 }
        }
        return Double(repeats) / Double(tiles.count - 1)
    }

    private func coverage(of subject: HeroCrop, within crop: HeroCrop) -> Double {
        let intersectionWidth = max(
            0,
            min(subject.x + subject.width, crop.x + crop.width) - max(subject.x, crop.x)
        )
        let intersectionHeight = max(
            0,
            min(subject.y + subject.height, crop.y + crop.height) - max(subject.y, crop.y)
        )
        return intersectionWidth * intersectionHeight / (subject.width * subject.height)
    }
}

public enum MosaicQualityEvaluationError: Error, Equatable, Sendable {
    case invalidRubric
    case invalidInputs
    case assignmentDoesNotMatchInputs
    case invalidGate
}
