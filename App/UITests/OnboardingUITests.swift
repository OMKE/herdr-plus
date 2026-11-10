import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDiscoveryFindsMacOnFindStep() throws {
        let app = XCUIApplication()
        app.launch()
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10))
        cont.tap()
        XCTAssertTrue(app.staticTexts["Find your Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Macs nearby"].exists)
        addUIInterruptionMonitor(withDescription: "Local network") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.swipeUp()
        app.swipeDown()
        let mac = app.buttons["found-mac"].firstMatch
        let found = mac.waitForExistence(timeout: 20)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "find-step"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(found, "No Mac found over Bonjour")
        mac.tap()
        let host = app.textFields["mac-studio or 100.x.y.z"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertFalse((host.value as? String ?? "").isEmpty)
        let user = app.textFields["username-field"]
        let typed = user.value as? String ?? ""
        XCTAssertTrue(typed.isEmpty || typed == user.placeholderValue, "Username must not be guessed")
        XCTAssertTrue(app.staticTexts["Reachable"].waitForExistence(timeout: 8))
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "picked"
        after.lifetime = .keepAlways
        add(after)
    }

    func testTailscaleAuthSkipsKey() throws {
        let app = XCUIApplication()
        app.launch()
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10))
        cont.tap()
        XCTAssertTrue(app.staticTexts["Find your Mac"].waitForExistence(timeout: 5))
        app.buttons["Tailscale SSH"].tap()
        let host = app.textFields["mac-studio or 100.x.y.z"]
        host.tap()
        host.typeText("my-mac")
        let user = app.textFields["username-field"]
        user.tap()
        user.typeText("someone")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Turn on Tailscale SSH"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tailscale-step"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
