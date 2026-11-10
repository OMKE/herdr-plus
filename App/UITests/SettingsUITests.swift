import XCTest

final class SettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testKeyBarScrolls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-keybar"]
        app.launch()
        let esc = app.buttons["Escape"].firstMatch
        XCTAssertTrue(esc.waitForExistence(timeout: 10))
        let x0 = esc.frame.minX
        snap(app, "keybar-before")
        let start = esc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 0)))
        sleep(1)
        snap(app, "keybar-after")
        XCTAssertLessThan(esc.frame.minX, x0 - 50, "Key bar did not scroll")
    }

    func testWorkingRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-working"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Deliberating…"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["4m 50s · ↓ 3.4k tokens"].exists)
        XCTAssertTrue(app.staticTexts["Working"].exists)
        snap(app, "working-row")
    }

    func testSettingsScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-settings"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 10))
        snap(app, "settings-top")
        app.swipeUp()
        snap(app, "settings-scrolled")
        app.swipeUp()
        snap(app, "settings-bottom")
        app.swipeDown()
        app.swipeDown()
        for (row, name) in [("Appearance", "appearance"), ("Fonts & Size", "fonts"), ("Toolbar", "toolbar"), ("Speech", "speech"), ("Hardware Keyboard", "keyboard"), ("App Icon", "icon")] {
            let r = app.staticTexts[row].firstMatch
            XCTAssertTrue(r.waitForExistence(timeout: 5))
            r.tap()
            sleep(1)
            snap(app, name)
            if name == "toolbar" || name == "fonts" {
                app.swipeUp()
                snap(app, name + "-2")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
    }
}
