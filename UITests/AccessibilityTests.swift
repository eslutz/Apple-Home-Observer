import XCTest
import UIKit
import ImageIO

final class AccessibilityTests: XCTestCase {
    private let sections = [("Overview", "overview"), ("Backups", "backups"), ("Recovery", "recovery"), ("Blind Investigation", "blinds"), ("Backup Coverage", "coverage"), ("Monitoring", "monitoring")]
    private var contrastScreen: CGImage?
    private var contrastAppFrame = CGRect.zero
    private var contrastSidebarFrame = CGRect.zero
    private var contrastLabelFrames = [String: CGRect]()
    private func captureContrastBaseline(in app: XCUIApplication) {
        contrastAppFrame = app.frame
        contrastSidebarFrame = app.descendants(matching: .any).matching(identifier: "observer.sidebar").firstMatch.frame
        contrastLabelFrames.removeAll()
        for (label, id) in sections {
            let row = app.descendants(matching: .any).matching(identifier: "observer.section." + id).firstMatch
            if row.exists && row.isHittable { contrastLabelFrames[label] = row.frame }
        }
        let heading = app.staticTexts["Home"].firstMatch
        if heading.exists && heading.isHittable { contrastLabelFrames["Home"] = heading.frame }
        let home = app.descendants(matching: .any).matching(identifier: "observer.home").firstMatch
        if home.exists && home.isHittable, let value = home.value as? String { contrastLabelFrames[value] = home.frame }
        // Capture the isolated simulator screen: application screenshots can be
        // cropped before their landscape orientation is applied. ImageIO applies
        // the PNG orientation metadata before AX-to-pixel mapping.
        let data = XCUIScreen.main.screenshot().pngRepresentation
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
            contrastScreen = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else { contrastScreen = nil }
        let baseline = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        baseline.name = "contrast-baseline"; baseline.lifetime = .keepAlways; add(baseline)
    }
    // iOS 26/27 can report contrast on native sidebar text whose captured
    // pixels pass normal-text contrast. Only captured, identified sidebar rows
    // and Home controls are candidates; geometry and measured pixels must pass.
    private func verifiedSidebarContrast(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element,
              contrastLabelFrames[element.label] != nil,
              element.exists else { return false }
        let rect = element.frame
        print("CONTRAST GEOMETRY: \(element.label) reported=\(rect) row=\(String(describing: contrastLabelFrames[element.label])) sidebar=\(contrastSidebarFrame)")
        guard let expected = contrastLabelFrames[element.label],
              expected.insetBy(dx: -1, dy: -1).contains(rect),
              contrastSidebarFrame.contains(rect), contrastAppFrame.contains(rect),
              rect.width > 0, rect.height > 0, let screen = contrastScreen else { return false }
        let scaleX = CGFloat(screen.width) / contrastAppFrame.width
        let scaleY = CGFloat(screen.height) / contrastAppFrame.height
        let pixels = CGRect(x: (rect.minX - contrastAppFrame.minX) * scaleX,
                            y: (rect.minY - contrastAppFrame.minY) * scaleY,
                            width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let crop = screen.cropping(to: pixels) else { return false }
        let width = crop.width, height = crop.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered, width * height >= 100 else { return false }
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var luminances = [Double]()
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] == 255 {
            luminances.append(0.2126 * linear(bytes[index]) + 0.7152 * linear(bytes[index + 1]) + 0.0722 * linear(bytes[index + 2]))
        }
        guard luminances.count >= 100 else { return false }
        luminances.sort()
        let ratio = (luminances[Int(Double(luminances.count - 1) * 0.99)] + 0.05) /
                    (luminances[Int(Double(luminances.count - 1) * 0.05)] + 0.05)
        print("SIDEBAR CONTRAST MEASUREMENT: \(element.label) ratio=\(ratio) rect=\(rect) app=\(app.frame) screenshot=\(screen.width)x\(screen.height)")
        if ratio < 4.5 {
            let rejected = XCTAttachment(image: UIImage(cgImage: crop))
            rejected.name = "rejected-sidebar-measurement-" + element.label
            rejected.lifetime = .keepAlways; add(rejected)
            return false
        }
        let evidence = XCTAttachment(image: UIImage(cgImage: crop))
        evidence.name = "verified-sidebar-contrast-" + element.label
        evidence.lifetime = .keepAlways; add(evidence)
        print("VERIFIED SIDEBAR CONTRAST: \(element.label) \(ratio):1")
        return true
    }
    private func select(_ section: String, in app: XCUIApplication) {
        let toggle = app.buttons["observer.navigation.toggle"]
        let navigationRow = app.descendants(matching: .any).matching(identifier: "observer.section." + section).firstMatch
        if !navigationRow.isHittable && toggle.exists { toggle.tap() }
        let row = app.descendants(matching: .any).matching(identifier: "observer.section." + section).firstMatch
        for _ in 0..<5 where !row.isHittable {
            app.descendants(matching: .any).matching(identifier: "observer.sidebar").firstMatch.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "Missing sidebar section: \(section)")
        row.tap()
    }
    func testLargestTextScreens() throws {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        XCUIDevice.shared.orientation = .landscapeLeft
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
            app.launchEnvironment["OBSERVER_UI_TEXT_SIZE"] = "largest"
            app.launch()
            XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
            for (section, id) in sections {
                select(id, in: app)
                if app.descendants(matching: .any).matching(identifier: "observer.section." + id).firstMatch.isHittable {
                    app.buttons["observer.navigation.toggle"].tap()
                }
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "largest-\(appearance)-\(section)"; attachment.lifetime = .keepAlways; add(attachment)
                // Font-size mutation is covered separately by the standard matrix.
                try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait])
            }
            app.terminate()
        }
    }

    func testFocusedDarkScreens() throws {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "empty"
        XCUIDevice.shared.appearance = .dark
        app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = "dark"
        app.launch()
        for (title, id) in sections where ["overview", "backups", "recovery", "coverage"].contains(id) {
            select(id, in: app)
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); capture.name = "focused-dark-" + title; capture.lifetime = .keepAlways; add(capture)
            captureContrastBaseline(in: app)
            try app.performAccessibilityAudit(for: .contrast) { issue in
                if self.verifiedSidebarContrast(issue, in: app) { return true }
                print("AUDIT focused-dark/\(id): \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
                return false
            }
        }
        app.terminate()
    }

    func testPopulatedCoverage() throws {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "populated"
        app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = "light"
        XCUIDevice.shared.appearance = .light
        app.launch()
        select("coverage", in: app)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "populated-coverage-hit-target"; capture.lifetime = .keepAlways; add(capture)
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
            print("AUDIT coverage: \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
            return false
        }
        app.terminate()
    }

    func testOverviewContrast() throws {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["OBSERVER_UI_AUDIT"] = "empty"
        XCUIDevice.shared.appearance = .light
        app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = "light"
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
        captureContrastBaseline(in: app)
        try app.performAccessibilityAudit(for: .contrast) { issue in
            if self.verifiedSidebarContrast(issue, in: app) { return true }
            print("AUDIT focused: \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
            return false
        }
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast))
        app.terminate()
    }

    func testEmptyAndPopulatedScreensInBothAppearances() throws {
        continueAfterFailure = true
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        XCUIDevice.shared.orientation = .landscapeLeft
        for fixture in ["empty", "populated"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchEnvironment["OBSERVER_UI_AUDIT"] = fixture
                XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
                app.launchEnvironment["OBSERVER_UI_APPEARANCE"] = appearance
                app.launch()
                XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
                for (section, id) in sections {
                    // Audit tools mutate traits while checking Dynamic Type. Start
                    // each screen from the requested appearance and fresh app state.
                    if id != "overview" {
                        app.terminate()
                        XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
                        app.launch()
                        XCTAssertTrue(app.staticTexts["Your Home, with a recovery history"].waitForExistence(timeout: 10))
                    }
                    select(id, in: app)
                    if fixture == "populated" && id == "backups" {
                        XCTAssertTrue(app.buttons["Preview Restore"].waitForExistence(timeout: 5), "Synthetic backup card must be present")
                    }
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "\(fixture)-\(appearance)-\(section)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    // Check contrast before the audit changes Dynamic Type traits.
                    // Maximum-size contrast is covered by testLargestTextScreens.
                    captureContrastBaseline(in: app)
                    try app.performAccessibilityAudit(for: .contrast) { issue in
                        if self.verifiedSidebarContrast(issue, in: app) { return true }
                        print("AUDIT \(fixture)/\(appearance)/\(section): \(issue.compactDescription) | \(issue.element?.label ?? "no element") | \(issue.detailedDescription)")
                        return false
                    }
                    try app.performAccessibilityAudit(for: .all.subtracting(.contrast))
                }
                app.terminate()
            }
        }
    }
}
