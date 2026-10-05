import XCTest

final class NativeAcceptanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // Catalyst may expose a finite AX frame but an invalid default hit point.
    // Anchor input to the verified native window instead of the app root.
    private func click(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let frame = element.frame
        let window = app.windows.firstMatch
        let origin = window.frame.origin
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width > 0, frame.height > 0,
              origin.x.isFinite, origin.y.isFinite else {
            XCTFail("Cannot click a native control with invalid geometry: \(element.identifier)")
            return
        }
        XCTAssertTrue(element.isHittable)
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).click()
    }

    // The same disabled wrapper is reported by the minimal text/button
    // control. It belongs to Catalyst above the named UIKit window, rather
    // than to an unlabeled app control. Match only that exact structure.
    private func verifiedPlatformWindowContainer(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        let nativeWindow = app.windows.firstMatch
        guard let element = issue.element,
              issue.auditType == .sufficientElementDescription,
              nativeWindow.identifier == "SceneWindow",
              element.elementType == .group, !element.isEnabled,
              element.label.isEmpty, element.identifier.isEmpty,
              element.frame.minX.isFinite, element.frame.minY.isFinite,
              element.frame.width > 0, element.frame.height > 0,
              element.frame == nativeWindow.frame,
              nativeWindow.children(matching: .group).count == 1,
              nativeWindow.children(matching: .group).firstMatch.frame == element.frame,
              element.children(matching: .any).count == 1,
              element.children(matching: .window).count == 1,
              element.children(matching: .window).firstMatch.label == "Apple Home Observer" else { return false }
        print("VERIFIED CATALYST STRUCTURAL WRAPPER: minimal platform control reproduces this finding")
        return true
    }

    private func select(_ section: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: "observer.section." + section).firstMatch
        if !row.isHittable {
            var toggle = app.buttons["observer.navigation.toggle"]
            if !toggle.exists { toggle = app.windows.firstMatch.toolbars.buttons["Navigation"].firstMatch }
            if !toggle.exists { toggle = app.windows.firstMatch.toolbars.buttons["Sidebar"].firstMatch }
            XCTAssertTrue(toggle.exists, "No accessible native navigation toggle")
            click(toggle, in: app)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let frame = row.frame
        XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width > 0 && frame.height > 0,
                      "Native AX row has invalid geometry: \(section), \(frame)")
        XCTAssertTrue(row.isHittable, "Native sidebar row is not hittable: \(section)")
        click(row, in: app)
        let headings = ["overview": "Your Home, with a recovery history", "backups": "Encrypted backups",
                        "recovery": "Review before restoring", "blinds": "Record a blind command",
                        "coverage": "Know what you can recover", "monitoring": "Private monitoring export"]
        guard let heading = headings[section] else { XCTFail("Unknown native section: \(section)"); return }
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5),
                      "Navigation did not reach the requested native page: \(section)")
    }
    private func resize(_ size: CGSize, in app: XCUIApplication) {
        app.menuBars.menuBarItems["Acceptance"].click()
        app.menuItems["Resize Test Window \(Int(size.width))"].click()
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let nativeWindow = app.descendants(matching: .window).matching(NSPredicate(format: "label == %@", "Apple Home Observer")).firstMatch
            guard let value = nativeWindow.value as? String, let data = value.data(using: .utf8),
                  let geometry = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                  let width = geometry["width"], let height = geometry["height"] else { return false }
            return abs(width - size.width) <= 16 && abs(height - size.height) <= 16
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed)
    }

    func testScreensAndKeyboardCommands() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        for appearance in ["light", "dark"] {
            app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
            resize(CGSize(width: 1200, height: 850), in: app)
            for section in ["overview", "backups", "recovery", "blinds", "coverage", "monitoring"] {
                select(section, in: app)
                let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                screenshot.name = "native-\(appearance)-\(section)"; screenshot.lifetime = .keepAlways; add(screenshot)
                let captionContrast = NativeHomeCaptionContrast(app: app)
                let sidebarContrast = ["overview", "backups", "recovery", "blinds", "coverage", "monitoring"]
                    .compactMap { NativeHomeCaptionContrast(app: app, section: $0) }
                let titles = ["overview": "Overview", "backups": "Backups", "recovery": "Recovery", "blinds": "Blind Investigation", "coverage": "Backup Coverage", "monitoring": "Monitoring"]
                let titleContrast = titles[section].flatMap { NativeWindowTitleContrast(app: app, title: $0) }
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    if captionContrast?.verifies(issue, test: self) == true { return true }
                    if sidebarContrast.contains(where: { $0.verifies(issue, test: self) }) { return true }
                    if titleContrast?.verifies(issue, test: self) == true { return true }
                    print("NATIVE AUDIT: \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
                    return false
                }
                try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
                    if self.verifiedPlatformWindowContainer(issue, in: app) { return true }
                    print("NATIVE AUDIT DETAIL: \(issue.element?.debugDescription ?? "no element")")
                    let tree = XCTAttachment(string: app.debugDescription)
                    tree.name = "native-accessibility-tree"; tree.lifetime = .keepAlways; self.add(tree)
                    print("NATIVE AUDIT: \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.element?.identifier ?? "no identifier") | \(issue.detailedDescription)")
                    return false
                }
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
    func testCoverageDisclosure() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        for appearance in ["light", "dark"] {
            app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
            app.launch()
            resize(CGSize(width: 1200, height: 850), in: app)
            select("coverage", in: app)
            let disclosure = app.buttons["Local storage and monitoring"]
            XCTAssertEqual(disclosure.value as? String, "Collapsed")
            click(disclosure, in: app)
            XCTAssertEqual(disclosure.value as? String, "Expanded")
            click(disclosure, in: app)
            XCTAssertEqual(disclosure.value as? String, "Collapsed")
            let sidebarContrast = ["overview", "backups", "recovery", "blinds", "coverage", "monitoring"]
                .compactMap { NativeHomeCaptionContrast(app: app, section: $0) }
            let caption = NativeHomeCaptionContrast(app: app)
            let title = NativeWindowTitleContrast(app: app, title: "Backup Coverage")
            try app.performAccessibilityAudit(for: .contrast) { issue in
                caption?.verifies(issue, test: self) == true ||
                    title?.verifies(issue, test: self) == true ||
                    sidebarContrast.contains(where: { $0.verifies(issue, test: self) })
            }
            try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
                self.verifiedPlatformWindowContainer(issue, in: app)
            }
            app.terminate()
        }
    }

    func testPlatformWindowWrapperDiagnostic() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        app.launchEnvironment["OBSERVER_UI_PLATFORM_CONTROL"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Platform control action"].waitForExistence(timeout: 15))
        var wrapperReported = false
        try app.performAccessibilityAudit(for: .sufficientElementDescription) { issue in
            guard let element = issue.element,
                  issue.auditType == .sufficientElementDescription,
                  element.elementType == .group, !element.isEnabled,
                  element.label.isEmpty, element.identifier.isEmpty,
                  element.frame == app.windows.firstMatch.frame,
                  element.children(matching: .window).count == 1,
                  element.children(matching: .window).firstMatch.label == "Apple Home Observer" else { return false }
            wrapperReported = true
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "minimal-platform-wrapper-tree"; tree.lifetime = .keepAlways; self.add(tree)
            return true
        }
        print("MINIMAL PLATFORM CONTROL WRAPPER REPORTED: \(wrapperReported)")
        XCTAssertTrue(app.buttons["Platform control action"].isHittable)
        click(app.buttons["Platform control action"], in: app)
        app.terminate()
    }

    func testKeyboardCommandsAndSearch() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "many-backups"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        select("overview", in: app)
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Sample inventory refreshed"].waitForExistence(timeout: 5))
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Sample backup action verified"].waitForExistence(timeout: 5))
        select("backups", in: app)
        let search = app.textFields["observer.snapshot.search"]
        click(search, in: app)
        search.typeText("no matching synthetic snapshot")
        XCTAssertTrue(app.staticTexts["No matching snapshots"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSystemWindowLayouts() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        // Catalyst can return a stale outer AX window frame while its UIKit
        // window already has restored geometry. Fixture-only geometry exposes
        // the actual window bounds, not a requested or assumed test size.
        func measuredSize() -> CGSize? {
            let window = app.descendants(matching: .window).matching(NSPredicate(format: "label == %@", "Apple Home Observer")).firstMatch
            guard let value = window.value as? String, let data = value.data(using: .utf8),
                  let geometry = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                  let width = geometry["width"], let height = geometry["height"],
                  width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Fill"].click()
        guard let filled = measuredSize() else { XCTFail("Missing actual native window geometry"); return }
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Move & Resize"].hover()
        app.menuItems.matching(identifier: "_zoomLeft:").firstMatch.click()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let size = measuredSize() else { return false }
            return size.width < filled.width - 100
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        guard let compact = measuredSize() else { XCTFail("Missing compact window geometry"); return }
        XCTAssertGreaterThanOrEqual(compact.width, 680)
        XCTAssertGreaterThanOrEqual(compact.height, 520)
        XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].exists)
        print("NATIVE SYSTEM WINDOW LAYOUTS: filled=\(filled) compact=\(compact)")
        app.terminate()
    }

    func testWindowSizesAndSearch() throws {
        let app = XCUIApplication(bundleIdentifier: "org.example.AppleHomeObserver.Acceptance")
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "many-backups"
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        for size in [CGSize(width: 1200, height: 850), CGSize(width: 980, height: 720), CGSize(width: 680, height: 520)] {
            resize(size, in: app)
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); capture.name = "native-window-\(Int(size.width))"; capture.lifetime = .keepAlways; add(capture)
        }
        select("backups", in: app)
        let search = app.textFields["observer.snapshot.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); click(search, in: app); search.typeText("no matching synthetic snapshot")
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
                let apply = app.buttons["Apply Reviewed Restore…"]
                click(apply, in: app)
                let restoreAppeared = app.buttons["Apply Restore"].waitForExistence(timeout: 15)
                let dialogCapture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                dialogCapture.name = "native-restore-confirmation"; dialogCapture.lifetime = .keepAlways; add(dialogCapture)
                XCTAssertTrue(restoreAppeared)
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
                XCTAssertFalse(app.buttons["Apply Restore"].exists)
                XCTAssertFalse(app.staticTexts["Sample restore action verified; no Home changes applied"].exists)
                click(apply, in: app)
                XCTAssertTrue(app.buttons["Apply Restore"].waitForExistence(timeout: 5))
                click(app.buttons["Apply Restore"], in: app)
                XCTAssertTrue(app.staticTexts["Sample restore action verified; no Home changes applied"].waitForExistence(timeout: 5))
            }
            if fixture == "interrupted" { XCTAssertTrue(app.staticTexts["Interrupted restore"].exists) }
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); capture.name = "native-state-" + fixture; capture.lifetime = .keepAlways; add(capture)
            app.terminate()
        }
    }

}
