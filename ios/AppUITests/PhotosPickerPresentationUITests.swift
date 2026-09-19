import CoreGraphics
import XCTest

@MainActor
final class PhotosPickerPresentationUITests: XCTestCase {
    func testHeroPickerOpensAndDismissesWithoutChangingSelection() {
        let app = XCUIApplication()
        app.launch()

        let newMosaic = app.buttons["New mosaic"]
        XCTAssertTrue(newMosaic.waitForExistence(timeout: 10))
        newMosaic.tap()

        let chooseHero = app.buttons["Choose hero photo"]
        XCTAssertTrue(chooseHero.waitForExistence(timeout: 10))
        chooseHero.tap()

        let cancelPicker = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(waitForHittable(cancelPicker))
        cancelPicker.tap()

        XCTAssertTrue(chooseHero.waitForExistence(timeout: 10))
        XCTAssertTrue(chooseHero.isHittable)
    }

    func testSelectingSeededHeroAdvancesToFraming() {
        let app = XCUIApplication()
        app.launch()

        let newMosaic = app.buttons["New mosaic"]
        XCTAssertTrue(newMosaic.waitForExistence(timeout: 10))
        newMosaic.tap()

        let chooseHero = app.buttons["Choose hero photo"]
        XCTAssertTrue(chooseHero.waitForExistence(timeout: 10))
        chooseHero.tap()

        let cancelPicker = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(waitForHittable(cancelPicker))
        tapFirstPickerPhoto(in: app, below: cancelPicker)

        let framingTitle = app.staticTexts["Frame your hero"]
        if !framingTitle.waitForExistence(timeout: 15) {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy after selecting seeded photo"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("Selecting the seeded photo did not advance to hero framing")
        }
        XCTAssertTrue(app.buttons["Choose source photos"].isHittable)
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapFirstPickerPhoto(in app: XCUIApplication, below cancelButton: XCUIElement) {
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let columnWidth = windowFrame.width / 3
        let gridTop = cancelButton.frame.maxY + 56
        let point = CGVector(
            dx: (columnWidth / 2) / windowFrame.width,
            dy: (gridTop + columnWidth / 2) / windowFrame.height
        )
        window.coordinate(withNormalizedOffset: point).tap()
    }
}
