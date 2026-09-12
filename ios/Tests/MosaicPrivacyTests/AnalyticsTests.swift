import XCTest
@testable import MosaicPrivacy

final class AnalyticsTests: XCTestCase {
    func testSourceCountsAreCoarselyBucketed() {
        XCTAssertEqual(SourceCountBucket(count: 99), .under100)
        XCTAssertEqual(SourceCountBucket(count: 100), .from100To249)
        XCTAssertEqual(SourceCountBucket(count: 500), .from500To999)
        XCTAssertEqual(SourceCountBucket(count: 1_000), .over1000)
    }
}

