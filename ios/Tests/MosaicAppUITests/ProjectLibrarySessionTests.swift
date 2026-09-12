import Foundation
import XCTest
import MosaicCore
import MosaicPersistence
@testable import MosaicAppUI

@MainActor
final class ProjectLibrarySessionTests: XCTestCase {
    func testRefreshLoadsMostRecentlyUpdatedProjectFirst() async {
        let older = MosaicProject(updatedAt: Date(timeIntervalSinceReferenceDate: 1), title: "Older")
        let newer = MosaicProject(updatedAt: Date(timeIntervalSinceReferenceDate: 2), title: "Newer")
        let session = ProjectLibrarySession(store: InMemoryProjectStore(projects: [older, newer]))

        await session.refresh()

        XCTAssertEqual(session.projects.map(\.title), ["Newer", "Older"])
        XCTAssertNil(session.message)
    }

    func testRenameAndDeleteUpdateTheCatalogue() async {
        let project = MosaicProject(title: "Original")
        let store = InMemoryProjectStore(projects: [project])
        let session = ProjectLibrarySession(store: store)

        await session.rename(project, to: "  Holiday memories  ")
        XCTAssertEqual(session.projects.first?.title, "Holiday memories")

        guard let renamed = session.projects.first else {
            return XCTFail("Expected renamed project")
        }
        await session.delete(renamed)
        XCTAssertTrue(session.projects.isEmpty)
    }
}
