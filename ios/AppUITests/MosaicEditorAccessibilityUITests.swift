import CoreGraphics
import XCTest

@MainActor
final class MosaicEditorAccessibilityUITests: XCTestCase {
    func testEditorControlsSupportLikenessReplacementUndoAndRedo() {
        let app = XCUIApplication()
        app.launch()

        let editorProject = app.staticTexts["CI Editor"]
        XCTAssertTrue(editorProject.waitForExistence(timeout: 10))
        editorProject.tap()

        let continueToEditor = app.buttons["Continue to editor"]
        if !continueToEditor.waitForExistence(timeout: 30) {
            attachDiagnostics(from: app, name: "Editor fixture preview did not finish")
            XCTFail("The deterministic editor fixture did not produce a preview")
            return
        }
        continueToEditor.tap()

        let editorTitle = app.staticTexts["mosaic.editor.title"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))

        let slider = app.sliders["mosaic.editor.likeness"]
        let canvas = app.otherElements["mosaic.editor.canvas"]
        let undo = app.buttons["mosaic.editor.undo"]
        let redo = app.buttons["mosaic.editor.redo"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(undo.exists)
        XCTAssertTrue(redo.exists)
        XCTAssertEqual(slider.value as? String, "50 percent hero likeness")
        XCTAssertFalse(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)

        slider.adjust(toNormalizedSliderPosition: 0.70)
        XCTAssertTrue(waitForValue("70 percent hero likeness", on: slider, timeout: 10))
        XCTAssertTrue(waitForEnabled(undo, timeout: 10))

        let editorScrollView = app.scrollViews["mosaic.editor.scroll"]
        XCTAssertTrue(editorScrollView.exists)
        makeHittable(undo, in: editorScrollView)
        undo.tap()
        XCTAssertTrue(waitForValue("50 percent hero likeness", on: slider, timeout: 10))
        XCTAssertTrue(waitForEnabled(redo, timeout: 10))

        makeHittable(redo, in: editorScrollView)
        redo.tap()
        XCTAssertTrue(waitForValue("70 percent hero likeness", on: slider, timeout: 10))

        makeHittable(canvas, in: editorScrollView, direction: .up)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()

        let selection = app.otherElements["mosaic.editor.selection"]
        if !selection.waitForExistence(timeout: 10) {
            attachDiagnostics(from: app, name: "Editor tile was not selected")
            XCTFail("Tapping the mosaic did not expose the selected tile inspector")
            return
        }

        let replace = app.buttons["mosaic.editor.replace"]
        makeHittable(replace, in: editorScrollView)
        replace.tap()

        let replacement = app.buttons[
            "mosaic.editor.replacement.10000000-0000-0000-0000-000000000002"
        ]
        if !replacement.waitForExistence(timeout: 10) {
            attachDiagnostics(from: app, name: "Replacement sheet did not load")
            XCTFail("The replacement sheet did not expose the alternate source photo")
            return
        }
        XCTAssertTrue(replacement.isEnabled)
        replacement.tap()

        XCTAssertTrue(waitForNonexistence(replacement, timeout: 10))
        makeHittable(undo, in: editorScrollView)
        XCTAssertTrue(waitForEnabled(undo, timeout: 10))
        undo.tap()
        XCTAssertTrue(waitForEnabled(redo, timeout: 10))
        XCTAssertEqual(slider.value as? String, "70 percent hero likeness")

        makeHittable(redo, in: editorScrollView)
        redo.tap()
        XCTAssertTrue(waitForEnabled(undo, timeout: 10))
        XCTAssertEqual(slider.value as? String, "70 percent hero likeness")
    }

    private enum ScrollDirection {
        case up
        case down
    }

    private func makeHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        direction: ScrollDirection = .down
    ) {
        for _ in 0..<5 where !element.isHittable {
            switch direction {
            case .up: scrollView.swipeDown()
            case .down: scrollView.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(
        _ value: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNonexistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func attachDiagnostics(from app: XCUIApplication, name: String) {
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
