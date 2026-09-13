import XCTest
@testable import MosaicPrivacy

final class AnalyticsTests: XCTestCase {
    func testSourceCountsAreCoarselyBucketed() {
        XCTAssertEqual(SourceCountBucket(count: 99), .under100)
        XCTAssertEqual(SourceCountBucket(count: 100), .from100To249)
        XCTAssertEqual(SourceCountBucket(count: 500), .from500To999)
        XCTAssertEqual(SourceCountBucket(count: 1_000), .over1000)
    }

    func testValidatorAcceptsOnlyCoarseAllowlistedValues() throws {
        let event = AnalyticsEvent(
            name: .sourceSetConfirmed,
            fields: [
                .workflowStep: "preview",
                .sourceCountBucket: "100_249",
                .selectionMode: "manual",
            ]
        )
        XCTAssertNoThrow(try AnalyticsEventValidator().validate(event))
    }

    func testValidatorRejectsFilenameOrFreeTextValues() {
        let event = AnalyticsEvent(
            name: .previewCompleted,
            fields: [.failureReason: "IMG_1042.JPG failed for Michael"]
        )
        XCTAssertThrowsError(try AnalyticsEventValidator().validate(event)) { error in
            XCTAssertEqual(error as? AnalyticsValidationError, .disallowedValue(field: .failureReason))
        }
    }
}
