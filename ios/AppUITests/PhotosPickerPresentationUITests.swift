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

        let addSelection = app.buttons["Add"].firstMatch
        if !waitForHittable(addSelection) {
            attachHierarchy(from: app, name: "Picker hierarchy after tapping seeded photo")
            XCTFail("The seeded photo was not selected in the picker")
            return
        }
        addSelection.tap()

        let framingTitle = app.staticTexts["Frame your hero"]
        if !framingTitle.waitForExistence(timeout: 15) {
            attachHierarchy(from: app, name: "Hierarchy after confirming seeded photo")
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

    private func attachHierarchy(from app: XCUIApplication, name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
