import XCTest

final class NativeAcceptanceTests: XCTestCase {
    private func select(_ section: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: "observer.section." + section).firstMatch
        if !row.isHittable && app.buttons["observer.navigation.toggle"].exists {
            app.buttons["observer.navigation.toggle"].click()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
    }
    func testScreensAndKeyboardCommands() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        for appearance in ["light", "dark"] {
            app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
            for section in ["overview", "backups", "recovery", "blinds", "coverage", "monitoring"] {
                select(section, in: app)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "native-\(appearance)-\(section)"; screenshot.lifetime = .keepAlways; add(screenshot)
                try app.performAccessibilityAudit(for: .contrast)
                try app.performAccessibilityAudit(for: .all.subtracting(.contrast))
            }
            select("overview", in: app)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Sample inventory refreshed"].waitForExistence(timeout: 5))
            app.typeKey("b", modifierFlags: [.command, .shift])
            XCTAssertTrue(app.staticTexts["Sample backup action verified"].waitForExistence(timeout: 5))
            app.menuBars.menuBarItems["Acceptance"].click()
            app.menuItems["Toggle Test Appearance"].click()
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testWindowSizesAndSearch() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "many-backups"
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        for size in [CGSize(width: 680, height: 520), CGSize(width: 980, height: 720), CGSize(width: 1200, height: 850)] {
            let before = window.frame
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: size.width - before.width, dy: size.height - before.height)))
            XCTAssertEqual(window.frame.width, size.width, accuracy: 16)
            XCTAssertEqual(window.frame.height, size.height, accuracy: 16)
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "native-window-\(Int(size.width))"; capture.lifetime = .keepAlways; add(capture)
        }
        select("backups", in: app)
        let search = app.textFields["observer.snapshot.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.click(); search.typeText("no matching synthetic snapshot")
        XCTAssertTrue(app.staticTexts["No matching snapshots"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testGuardedStates() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        for fixture in ["empty", "busy", "incomplete", "error", "recovery", "interrupted"] {
            app.launchEnvironment["OBSERVER_UI_AUDIT"] = fixture
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
            select("recovery", in: app)
            if ["empty", "busy", "incomplete"].contains(fixture) {
                app.menuBars.menuBarItems["Home"].click()
                XCTAssertFalse(app.menuItems["Back Up Now"].isEnabled)
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            }
            if fixture == "recovery" {
                app.buttons["Apply Reviewed Restore…"].click()
                XCTAssertTrue(app.buttons["Apply Restore"].waitForExistence(timeout: 5))
                app.buttons["Apply Restore"].click()
                XCTAssertTrue(app.staticTexts["Sample restore action verified; no Home changes applied"].waitForExistence(timeout: 5))
            }
            if fixture == "interrupted" { XCTAssertTrue(app.staticTexts["Interrupted restore"].exists) }
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "native-state-" + fixture; capture.lifetime = .keepAlways; add(capture)
            app.terminate()
        }
    }

}
