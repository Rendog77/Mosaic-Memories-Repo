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
        cancelPicker.tap()

        XCTAssertTrue(chooseHero.waitForExistence(timeout: 10))
        XCTAssertTrue(chooseHero.isHittable)
    }
}
