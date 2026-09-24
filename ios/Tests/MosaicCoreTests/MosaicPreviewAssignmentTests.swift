import XCTest
@testable import MosaicCore

final class MosaicPreviewAssignmentTests: XCTestCase {
    func testDescriptorAndAssignmentRoundTripThroughJSON() throws {
        let descriptor = try MosaicDescriptor(components: [42, -3, 18])
        let source = AssetReference(id: "source", origin: .testFixture)
        let assignment = MosaicPreviewAssignment(
            engineVersion: 1,
            tiles: [.init(coordinate: .init(column: 0, row: 0), source: source)]
        )

        let decodedDescriptor = try JSONDecoder().decode(
            MosaicDescriptor.self,
            from: JSONEncoder().encode(descriptor)
        )
        let decodedAssignment = try JSONDecoder().decode(
            MosaicPreviewAssignment.self,
            from: JSONEncoder().encode(assignment)
        )

        XCTAssertEqual(decodedDescriptor, descriptor)
        XCTAssertEqual(decodedAssignment, assignment)
    }

    func testAssignmentUsesNearestSourceAndRowMajorOrder() throws {
        let dark = try source("dark", components: [0, 0, 0])
        let light = try source("light", components: [100, 0, 0])
        let targets = [
            try target(column: 1, row: 0, components: [90, 0, 0]),
            try target(column: 0, row: 0, components: [10, 0, 0]),
        ]

        let assignment = try MosaicPreviewAssigner().assign(
            targets: targets,
            sources: [light, dark],
            repeatWindow: 0
        )

        XCTAssertEqual(assignment.tiles.map(\.coordinate), [
            .init(column: 0, row: 0),
            .init(column: 1, row: 0),
        ])
        XCTAssertEqual(assignment.tiles.map(\.source.id), ["dark", "light"])
    }

    func testRepeatWindowChoosesNextBestAvailableSource() throws {
        let best = try source("best", components: [0])
        let fallback = try source("fallback", components: [10])
        let targets = [
            try target(column: 0, row: 0, components: [0]),
            try target(column: 1, row: 0, components: [0]),
            try target(column: 2, row: 0, components: [0]),
        ]

        let assignment = try MosaicPreviewAssigner().assign(
            targets: targets,
            sources: [best, fallback],
            repeatWindow: 1
        )

        XCTAssertEqual(assignment.tiles.map(\.source.id), ["best", "fallback", "best"])
    }

    func testTieBreakIsStableAcrossSourceInputOrder() throws {
        let first = try source("a", components: [5])
        let second = try source("b", components: [5])
        let targets = [try target(column: 0, row: 0, components: [5])]
        let assigner = MosaicPreviewAssigner()

        let forward = try assigner.assign(targets: targets, sources: [first, second], repeatWindow: 0)
        let reversed = try assigner.assign(targets: targets, sources: [second, first], repeatWindow: 0)

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.tiles.first?.source.id, "a")
    }

    func testInvalidInputsAreRejected() throws {
        XCTAssertThrowsError(try MosaicDescriptor(components: [])) { error in
            XCTAssertEqual(error as? MosaicAssignmentError, .emptyDescriptor)
        }
        XCTAssertThrowsError(try MosaicDescriptor(version: 99, components: [0])) { error in
            XCTAssertEqual(error as? MosaicAssignmentError, .unsupportedDescriptorVersion(99))
        }
        let futureAssignment = Data(
            #"{"version":99,"engineVersion":1,"descriptorVersion":1,"tiles":[]}"#.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(MosaicPreviewAssignment.self, from: futureAssignment)
        ) { error in
            XCTAssertEqual(error as? MosaicAssignmentError, .unsupportedAssignmentVersion(99))
        }

        let source = try source("source", components: [0, 1])
        let target = try target(column: 0, row: 0, components: [0])
        XCTAssertThrowsError(
            try MosaicPreviewAssigner().assign(targets: [target], sources: [source], repeatWindow: 0)
        ) { error in
            XCTAssertEqual(
                error as? MosaicAssignmentError,
                .inconsistentComponentCount(expected: 2, actual: 1)
            )
        }
    }

    private func source(_ id: String, components: [Double]) throws -> MosaicSourceDescriptor {
        MosaicSourceDescriptor(
            reference: .init(id: id, origin: .testFixture),
            descriptor: try MosaicDescriptor(components: components)
        )
    }

    private func target(
        column: Int,
        row: Int,
        components: [Double]
    ) throws -> MosaicTargetDescriptor {
        MosaicTargetDescriptor(
            coordinate: .init(column: column, row: row),
            descriptor: try MosaicDescriptor(components: components)
        )
    }
}
