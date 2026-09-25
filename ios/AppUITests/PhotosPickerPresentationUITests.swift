import CoreGraphics
import XCTest

@MainActor
final class PhotosPickerPresentationUITests: XCTestCase {
    func testReadySourceSetCanBeConfirmedWithoutLibraryPermission() {
        let app = XCUIApplication()
        app.launch()

        let seededProject = app.staticTexts["CI Source Review"]
        XCTAssertTrue(seededProject.waitForExistence(timeout: 10))
        seededProject.tap()

        let reviewTitle = app.staticTexts["Review your photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["100 photos selected — ready to create"].exists)

        let confirmPhotos = app.buttons["Confirm photos"]
        XCTAssertTrue(confirmPhotos.exists)
        XCTAssertTrue(confirmPhotos.isEnabled)
        confirmPhotos.tap()

        let previewTitle = app.staticTexts["Your mosaic"]
        if !previewTitle.waitForExistence(timeout: 20) {
            attachPickerDiagnostics(from: app, name: "After confirming 100 source photos")
            XCTFail("A ready source set did not advance to preview")
        }
    }

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
        guard let cancelFrame = waitForPickerFrame(cancelPicker) else {
            attachPickerDiagnostics(from: app, name: "Picker without a usable Cancel frame")
            XCTFail("The photo picker did not expose a usable Cancel button")
            return
        }
        guard dismissPicker(cancelPicker, initialFrame: cancelFrame, in: app) else {
            attachPickerDiagnostics(from: app, name: "Picker after Cancel did not dismiss")
            XCTFail("The photo picker did not dismiss after tapping Cancel")
            return
        }
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

    private func dismissPicker(
        _ cancelButton: XCUIElement,
        initialFrame: CGRect,
        in app: XCUIApplication
    ) -> Bool {
        let hittable = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: cancelButton)
        if XCTWaiter.wait(for: [expectation], timeout: 3) == .completed {
            cancelButton.tap()
            if waitForNonexistence(cancelButton, timeout: 4) {
                return true
            }
        }

        // The system picker can temporarily expose Cancel as non-hittable even
        // with a valid frame. Route a physical tap through the app window then.
        tapPickerCancel(at: usableFrame(of: cancelButton) ?? initialFrame, in: app)
        if waitForNonexistence(cancelButton, timeout: 4) {
            return true
        }

        // Allow one fresh accessibility attempt after the picker settles.
        if cancelButton.exists, cancelButton.isHittable {
            cancelButton.tap()
        }
        return waitForNonexistence(cancelButton, timeout: 4)
    }

    private func tapPickerCancel(at buttonFrame: CGRect, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        if hasUsableFrame(buttonFrame), hasUsableFrame(windowFrame) {
            let offset = CGVector(
                dx: (buttonFrame.midX - windowFrame.minX) / windowFrame.width,
                dy: (buttonFrame.midY - windowFrame.minY) / windowFrame.height
            )
            if offset.dx.isFinite, offset.dy.isFinite,
               offset.dx >= 0, offset.dx <= 1,
               offset.dy >= 0, offset.dy <= 1 {
                window.coordinate(withNormalizedOffset: offset).tap()
                return
            }
        }

        // Preserve a fallback for picker versions that omit a usable frame.
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.10, dy: 0.115)
        ).tap()
    }

    private func usableFrame(of element: XCUIElement) -> CGRect? {
        guard element.exists else { return nil }
        let frame = element.frame
        return hasUsableFrame(frame) ? frame : nil
    }

    private func waitForNonexistence(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !element.exists
    }

    private func waitForPickerLayout(_ cancelButton: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitForPickerFrame(cancelButton, timeout: timeout) != nil
    }

    private func waitForPickerFrame(
        _ cancelButton: XCUIElement,
        timeout: TimeInterval = 10
    ) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cancelButton.exists {
                let frame = cancelButton.frame
                if hasUsableFrame(frame) {
                    Thread.sleep(forTimeInterval: 0.5)
                    return frame
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    private func hasUsableFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
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
