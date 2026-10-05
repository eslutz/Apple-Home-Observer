import XCTest
import AppKit
import ImageIO

// Verify reproduced native sidebar contrast warnings against exact controls.
// Capture the visible identified control before auditing; preserve pixel proof.
struct NativeHomeCaptionContrast {
    let label: String
    let identifier: String
    let frame: CGRect
    let sidebar: CGRect
    let window: CGRect
    let image: CGImage

    init?(app: XCUIApplication, section: String? = nil) {
        let labels = ["overview": "Overview", "backups": "Backups", "recovery": "Recovery",
                      "blinds": "Blind Investigation", "coverage": "Backup Coverage", "monitoring": "Monitoring"]
        if let section {
            guard let label = labels[section] else { return nil }
            self.label = label
            identifier = "observer.section." + section
        } else {
            label = "Home"
            identifier = ""
        }
        let sidebar = app.descendants(matching: .any).matching(identifier: "observer.sidebar").firstMatch
        let heading = section == nil ? sidebar.staticTexts["Home"].firstMatch : sidebar.staticTexts.matching(identifier: identifier).firstMatch
        guard heading.exists, heading.isHittable else { return nil }
        frame = heading.frame
        self.sidebar = sidebar.frame
        window = app.windows.firstMatch.frame
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width > 0, frame.height > 0,
              self.sidebar.contains(frame), window.contains(frame),
              let source = CGImageSourceCreateWithData(heading.screenshot().pngRepresentation as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.image = image
    }

    func verifies(_ issue: XCUIAccessibilityAuditIssue, test: XCTestCase) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element,
              element.label == label, element.exists,
              identifier.isEmpty || element.identifier == identifier ||
                (element.identifier.isEmpty && element.elementType == .staticText) else { return false }
        let rect = element.frame
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width > 0, rect.height > 0,
              frame.insetBy(dx: -1, dy: -1).contains(rect),
              sidebar.contains(rect), window.contains(rect) else { return false }
        // Catalyst reports either the identified row or its label child.
        // Crop only the reported label within the pre-audit identified row.
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        let pixels = CGRect(x: (rect.minX - frame.minX) * scaleX,
                            y: (rect.minY - frame.minY) * scaleY,
                            width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let crop = image.cropping(to: pixels) else { return false }
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
        print("SIDEBAR CONTRAST MEASUREMENT: \(element.label) ratio=\(ratio) rect=\(rect) ")
        if ratio < 4.5 {
            let rejected = XCTAttachment(image: NSImage(cgImage: crop, size: .zero))
            rejected.name = "rejected-sidebar-measurement-" + element.label
            rejected.lifetime = .keepAlways; test.add(rejected)
            return false
        }
        let evidence = XCTAttachment(image: NSImage(cgImage: crop, size: .zero))
        evidence.name = "verified-sidebar-contrast-" + element.label
        evidence.lifetime = .keepAlways; test.add(evidence)
        print("VERIFIED SIDEBAR CONTRAST: \(element.label) \(ratio):1")
        return true
    }
}
