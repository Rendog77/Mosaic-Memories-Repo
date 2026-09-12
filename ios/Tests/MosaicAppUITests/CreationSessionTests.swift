import Foundation
import XCTest
import MosaicCore
import MosaicFeatures
import MosaicPersistence
@testable import MosaicAppUI

@MainActor
final class CreationSessionTests: XCTestCase {
    func testSessionAutosavesAndRestoresWorkflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProjectStore(directory: directory)
        let session = CreationSession(store: store)

        await session.selectHero(.init(id: "hero", origin: .testFixture))
        let sources = (0..<100).map { AssetReference(id: "source-\($0)", origin: .testFixture) }
        await session.reviewSources(sources)
        await session.confirmSources()

        let restored = CreationSession(store: store)
        await restored.restoreMostRecentProject()

        XCTAssertEqual(restored.workflow.project, session.workflow.project)
        XCTAssertEqual(restored.workflow.step, .preview)
    }

    func testInsufficientSourcesProduceHelpfulMessage() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = CreationSession(store: JSONProjectStore(directory: directory))
        await session.reviewSources([])
        await session.confirmSources()
        XCTAssertEqual(session.message, "Choose at least 100 photos. You currently have 0.")
    }
}

