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
        XCTAssertTrue(waitForPickerLayout(cancelPicker))
        tapPickerCancel(cancelPicker, in: app)

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: cancelPicker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
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
        XCTAssertTrue(waitForPickerLayout(cancelPicker))
        tapFirstPickerPhoto(in: app)

        let framingTitle = app.staticTexts["Frame your hero"]
        if !framingTitle.waitForExistence(timeout: 5) {
            let addSelection = app.buttons["Add"].firstMatch
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

    func testSelectingTwoSourcesReachesReview() {
        let app = XCUIApplication()
        app.launch()

        let newMosaic = app.buttons["New mosaic"]
        XCTAssertTrue(newMosaic.waitForExistence(timeout: 10))
        newMosaic.tap()

        let chooseHero = app.buttons["Choose hero photo"]
        XCTAssertTrue(chooseHero.waitForExistence(timeout: 10))
        chooseHero.tap()
        XCTAssertTrue(waitForPickerLayout(app.buttons["Cancel"].firstMatch))
        tapFirstPickerPhoto(in: app)

        let chooseSources = app.buttons["Choose source photos"]
        if !chooseSources.waitForExistence(timeout: 15) {
            attachPickerDiagnostics(from: app, name: "Before source selection")
            XCTFail("Hero selection did not reach the memories step")
            return
        }
        chooseSources.tap()
        XCTAssertTrue(waitForPickerLayout(app.buttons["Cancel"].firstMatch))

        tapPickerPhoto(at: 0, in: app)
        tapPickerPhoto(at: 1, in: app)

        let addSelection = app.buttons["Add"].firstMatch
        if !addSelection.waitForExistence(timeout: 10) {
            attachPickerDiagnostics(from: app, name: "Source picker after selecting two tiles")
            XCTFail("The source picker did not expose its Add action")
            return
        }
        addSelection.tap()

        let reviewTitle = app.staticTexts["Review your photos"]
        if !reviewTitle.waitForExistence(timeout: 20) {
            attachPickerDiagnostics(from: app, name: "After confirming two source photos")
            XCTFail("Source selection did not reach review")
            return
        }
        let twoSelected = app.staticTexts["2 selected — choose 98 more"]
        XCTAssertTrue(twoSelected.waitForExistence(timeout: 10))

        let addPhotos = app.buttons["Add photos"]
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 10))
        addPhotos.tap()
        XCTAssertTrue(waitForPickerLayout(app.buttons["Cancel"].firstMatch))
        tapPickerPhoto(at: 2, in: app)

        let addAnotherSelection = app.buttons["Add"].firstMatch
        if !addAnotherSelection.waitForExistence(timeout: 10) {
            attachPickerDiagnostics(from: app, name: "Source picker while adding another photo")
            XCTFail("The source picker did not expose Add for the extra photo")
            return
        }
        addAnotherSelection.tap()

        let threeSelected = app.staticTexts["3 selected — choose 97 more"]
        if !threeSelected.waitForExistence(timeout: 20) {
            attachPickerDiagnostics(from: app, name: "Review after adding another photo")
            XCTFail("Adding a source photo did not update review")
            return
        }

        let removePhoto = app.buttons["Remove photo"].firstMatch
        XCTAssertTrue(removePhoto.waitForExistence(timeout: 10))
        removePhoto.tap()
        XCTAssertTrue(twoSelected.waitForExistence(timeout: 10))
    }

    private func tapPickerCancel(_ cancelButton: XCUIElement, in app: XCUIApplication) {
        let frame = cancelButton.frame
        if cancelButton.exists, frame.width > 0, frame.height > 0 {
            cancelButton.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).tap()
            return
        }

        // Preserve a fallback for picker versions that omit a usable frame.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.10, dy: 0.115)
        ).tap()
    }

    private func waitForPickerLayout(_ cancelButton: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cancelButton.exists {
                let frame = cancelButton.frame
                if frame.width > 0 && frame.height > 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func tapFirstPickerPhoto(in app: XCUIApplication) {
        tapPickerPhoto(at: 0, in: app)
    }

    private func tapPickerPhoto(at index: Int, in app: XCUIApplication) {
        let picker = app.otherElements
            .containing(.any, identifier: "PXGSingleViewContainerView_AX")
            .firstMatch
        let photo = picker.images.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Photo'")
        ).element(boundBy: index)
        if photo.waitForExistence(timeout: 10) {
            photo.tap()
            return
        }

        // Preserve a coordinate fallback for picker versions that omit these
        // private accessibility details. The current CI layout uses three columns.
        let column = index % 3
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: (Double(column) + 0.5) / 3.0, dy: 0.47)
        ).tap()
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
