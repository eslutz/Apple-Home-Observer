import XCTest

final class AccessibilityTests: XCTestCase {
    private let sections = [("Overview", "overview"), ("Backups", "backups"), ("Recovery", "recovery"), ("Blind Investigation", "blinds"), ("Backup Coverage", "coverage"), ("Monitoring", "monitoring")]
    private func select(_ section: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: "observer.section." + section).firstMatch
        for _ in 0..<5 where !row.isHittable {
            app.descendants(matching: .any).matching(identifier: "observer.sidebar").firstMatch.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "Missing sidebar section: \(section)")
        row.tap()
    }
    func testLargestTextScreens() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = "light"
        app.launchEnvironment["OBSERVER_UI_TEXT_SIZE"] = "largest"
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
        for (section, id) in sections {
            select(id, in: app)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "largest-text-\(section)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate()
    }

    func testOverviewContrast() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "empty"
        app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = "light"
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit { issue in
            print("AUDIT focused: \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
            return false
        }
        app.terminate()
    }

    func testEmptyAndPopulatedScreensInBothAppearances() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        for fixture in ["empty", "populated"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchEnvironment["OBSERVER_UI_AUDIT"] = fixture
                app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
                app.launch()
                XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
                for (section, id) in sections {
                    select(id, in: app)
                    if fixture == "populated" && id == "backups" {
                        XCTAssertTrue(app.buttons["Preview Restore"].waitForExistence(timeout: 5), "Synthetic backup card must be present")
                    }
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = "\(fixture)-\(appearance)-\(section)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    try app.performAccessibilityAudit { issue in
                        print("AUDIT \(fixture)/\(appearance)/\(section): \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
                        return false
                    }
                }
                app.terminate()
            }
        }
    }
}
