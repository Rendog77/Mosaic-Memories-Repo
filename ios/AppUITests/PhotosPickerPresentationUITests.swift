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
        if !framingTitle.waitForExistence(timeout: 5) {
            let addSelection = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Add'")
            ).firstMatch
            if !waitForHittable(addSelection, timeout: 5) {
                attachPickerDiagnostics(from: app, name: "Picker after tapping seeded photo")
                XCTFail("The seeded photo neither completed single selection nor enabled Add")
                return
            }
            addSelection.tap()
        }

        if !framingTitle.waitForExistence(timeout: 15) {
            attachPickerDiagnostics(from: app, name: "After confirming seeded photo")
            XCTFail("Selecting the seeded photo did not advance to hero framing")
            return
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

    private func attachPickerDiagnostics(from app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(name) screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
