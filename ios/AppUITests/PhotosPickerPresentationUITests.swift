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
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: 10))
        tapPickerCancel(in: app)

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
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: 10))
        tapFirstPickerPhoto(in: app)

        let framingTitle = app.staticTexts["Frame your hero"]
        if !framingTitle.waitForExistence(timeout: 5) {
            let addSelection = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Add'")
            ).firstMatch
            if !addSelection.waitForExistence(timeout: 5) {
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

    private func tapPickerCancel(in app: XCUIApplication) {
        // The out-of-process picker intermittently reports a zero frame for Cancel.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.10, dy: 0.115)
        ).tap()
    }

    private func tapFirstPickerPhoto(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        // On the CI simulator the system's privacy notice sits above the grid.
        // The seeded image is the first (black) tile, centered near this point.
        let point = CGVector(dx: 1.0 / 6.0, dy: 0.47)
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
