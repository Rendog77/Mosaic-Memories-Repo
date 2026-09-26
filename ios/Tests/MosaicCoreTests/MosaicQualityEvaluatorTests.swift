import XCTest
@testable import MosaicCore

final class MosaicQualityEvaluatorTests: XCTestCase {
    func testBalancedProjectPassesProvisionalTwoDistanceRubric() throws {
        let fixture = try makeFixture(likeness: 0.5, targetOffset: 0)
        let evaluation = try MosaicQualityEvaluator().evaluate(
            project: fixture.project,
            assignment: fixture.assignment,
            targets: fixture.targets,
            sources: fixture.sources,
            subjectBounds: try HeroCrop(x: 0.3, y: 0.2, width: 0.4, height: 0.5)
        )

        XCTAssertTrue(evaluation.passed)
        XCTAssertEqual(evaluation.failedCriteria, [])
        XCTAssertEqual(evaluation.metrics.meanHeroDeltaE, 0, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.p90HeroDeltaE, 0, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.tileAuthenticity, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.sourceDiversity, 1, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.adjacentRepeatRatio, 0, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.subjectCoverage, 1, accuracy: 0.000_001)
    }

    func testEvaluationReportsEveryFailedQualityDimension() throws {
        let sourceReferences = (0..<4).map {
            AssetReference(id: "source-\($0)", origin: .testFixture)
        }
        let sources = try sourceReferences.map {
            MosaicSourceDescriptor(
                reference: $0,
                descriptor: try MosaicDescriptor(components: [0, -100, -100])
            )
        }
        let targets = try (0..<4).map {
            MosaicTargetDescriptor(
                coordinate: .init(column: $0, row: 0),
                descriptor: try MosaicDescriptor(components: [100, 100, 100])
            )
        }
        let project = MosaicProject(
            heroCrop: try HeroCrop(x: 0, y: 0, width: 0.5, height: 0.5),
            sources: sourceReferences,
            sourcesConfirmed: true,
            recipe: .init(columns: 4, likeness: 0.9, repeatWindow: 1)
        )
        let assignment = MosaicPreviewAssignment(
            engineVersion: project.recipe.engineVersion,
            tiles: targets.map {
                .init(coordinate: $0.coordinate, source: sourceReferences[0])
            }
        )

        let evaluation = try MosaicQualityEvaluator().evaluate(
            project: project,
            assignment: assignment,
            targets: targets,
            sources: sources,
            subjectBounds: try HeroCrop(x: 0.4, y: 0.4, width: 0.4, height: 0.4)
        )

        XCTAssertFalse(evaluation.passed)
        XCTAssertEqual(evaluation.failedCriteria, [
            .heroLikeness,
            .tileAuthenticity,
            .tileDiversity,
            .cropSafety,
        ])
        XCTAssertEqual(evaluation.metrics.meanHeroDeltaE, 30, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.tileAuthenticity, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.sourceDiversity, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.adjacentRepeatRatio, 1, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.metrics.subjectCoverage, 0.0625, accuracy: 0.000_001)
    }

    func testTenProjectCalibrationSuiteEnforcesEightProjectGate() throws {
        let evaluator = MosaicQualityEvaluator()
        let evaluations = try (0..<10).map { index in
            let fixture = try makeFixture(
                likeness: 0.5,
                targetOffset: index < 8 ? 0 : 100
            )
            return try evaluator.evaluate(
                project: fixture.project,
                assignment: fixture.assignment,
                targets: fixture.targets,
                sources: fixture.sources,
                subjectBounds: try HeroCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            )
        }

        let summary = try evaluator.summarize(
            evaluations,
            minimumPassingProjects: 8
        )

        XCTAssertEqual(summary.passingProjects, 8)
        XCTAssertEqual(summary.totalProjects, 10)
        XCTAssertEqual(summary.minimumPassingProjects, 8)
        XCTAssertTrue(summary.passed)
        XCTAssertThrowsError(
            try evaluator.summarize(
                Array(evaluations.dropLast()),
                minimumPassingProjects: 8
            )
        ) { error in
            XCTAssertEqual(error as? MosaicQualityEvaluationError, .invalidGate)
        }
    }

    func testInvalidRubricAndMismatchedAssignmentAreRejected() throws {
        let fixture = try makeFixture(likeness: 0.5, targetOffset: 0)
        let invalidRubric = MosaicQualityRubric(
            maximumMeanHeroDeltaE: -1,
            maximumP90HeroDeltaE: 28,
            minimumTileAuthenticity: 0.35,
            minimumSourceDiversity: 0.6,
            maximumAdjacentRepeatRatio: 0.05,
            minimumSubjectCoverage: 0.9
        )
        XCTAssertThrowsError(
            try MosaicQualityEvaluator().evaluate(
                project: fixture.project,
                assignment: fixture.assignment,
                targets: fixture.targets,
                sources: fixture.sources,
                subjectBounds: try HeroCrop(x: 0, y: 0, width: 1, height: 1),
                rubric: invalidRubric
            )
        ) { error in
            XCTAssertEqual(error as? MosaicQualityEvaluationError, .invalidRubric)
        }

        let incomplete = MosaicPreviewAssignment(
            engineVersion: fixture.project.recipe.engineVersion,
            tiles: Array(fixture.assignment.tiles.dropLast())
        )
        XCTAssertThrowsError(
            try MosaicQualityEvaluator().evaluate(
                project: fixture.project,
                assignment: incomplete,
                targets: fixture.targets,
                sources: fixture.sources,
                subjectBounds: try HeroCrop(x: 0, y: 0, width: 1, height: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? MosaicQualityEvaluationError,
                .assignmentDoesNotMatchInputs
            )
        }
    }

    private func makeFixture(
        likeness: Double,
        targetOffset: Double
    ) throws -> (
        project: MosaicProject,
        assignment: MosaicPreviewAssignment,
        targets: [MosaicTargetDescriptor],
        sources: [MosaicSourceDescriptor]
    ) {
        let values = [10.0, 30.0, 50.0, 70.0]
        let references = values.indices.map {
            AssetReference(id: "source-\($0)", origin: .testFixture)
        }
        let sources = try zip(references, values).map { pair in
            let (reference, value) = pair
            return MosaicSourceDescriptor(
                reference: reference,
                descriptor: try MosaicDescriptor(components: [value, 0, 0])
            )
        }
        let targets = try values.enumerated().map { pair in
            let (index, value) = pair
            return MosaicTargetDescriptor(
                coordinate: .init(column: index, row: 0),
                descriptor: try MosaicDescriptor(
                    components: [value, targetOffset, targetOffset]
                )
            )
        }
        let project = MosaicProject(
            sources: references,
            sourcesConfirmed: true,
            recipe: .init(columns: 4, likeness: likeness, repeatWindow: 1)
        )
        let assignment = try MosaicPreviewAssigner().assign(
            targets: targets,
            sources: sources,
            repeatWindow: project.recipe.repeatWindow,
            engineVersion: project.recipe.engineVersion
        )
        return (project, assignment, targets, sources)
    }
}
