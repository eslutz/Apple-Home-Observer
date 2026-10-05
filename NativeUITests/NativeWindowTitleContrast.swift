import XCTest
import AppKit
import ImageIO

// Verify only the native toolbar title against its rendered pixels.
// Its AX value, direct window parent and toolbar geometry must match.
struct NativeWindowTitleContrast {
    let frame: CGRect
    let toolbar: CGRect
    let title: String
    let window: CGRect
    let image: CGImage

    init?(app: XCUIApplication, title: String) {
        let nativeWindow = app.windows.firstMatch
        let field = nativeWindow.children(matching: .staticText).allElementsBoundByIndex
            .filter { ($0.value as? String) == title }
        guard nativeWindow.identifier == "SceneWindow", field.count == 1,
              let heading = field.first, heading.exists, heading.isHittable else { return nil }
        self.title = title
        frame = heading.frame
        toolbar = nativeWindow.toolbars.firstMatch.frame
        window = nativeWindow.frame
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width > 0, frame.height > 0,
              toolbar.contains(frame), window.contains(frame),
              let source = CGImageSourceCreateWithData(heading.screenshot().pngRepresentation as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.image = image
    }

    func verifies(_ issue: XCUIAccessibilityAuditIssue, test: XCTestCase) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element,
              element.elementType == .staticText, (element.value as? String) == title, element.exists else { return false }
        let rect = element.frame
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width > 0, rect.height > 0,
              frame.insetBy(dx: -1, dy: -1).contains(rect),
              abs(frame.width - rect.width) <= 1, abs(frame.height - rect.height) <= 1,
              toolbar.contains(rect), window.contains(rect) else { return false }
        let crop = image
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
        // The system exposes the entire title slot, including blank space.
        // Require at least 100 dark opaque pixels, so a handful of
        // outliers cannot qualify a wide or compact native title slot.
        guard luminances.count >= 10_000 else { return false }
        let foregroundIndex = max(99, Int(Double(luminances.count - 1) * 0.001))
        let ratio = (luminances[Int(Double(luminances.count - 1) * 0.99)] + 0.05) /
                    (luminances[foregroundIndex] + 0.05)
        print("WINDOW TITLE CONTRAST MEASUREMENT: \(title) ratio=\(ratio) rect=\(rect) ")
        if ratio < 4.5 {
            let rejected = XCTAttachment(image: NSImage(cgImage: crop, size: .zero))
            rejected.name = "rejected-window-title-measurement-" + title
            rejected.lifetime = .keepAlways; test.add(rejected)
            return false
        }
        let evidence = XCTAttachment(image: NSImage(cgImage: crop, size: .zero))
        evidence.name = "verified-window-title-contrast-" + title
        evidence.lifetime = .keepAlways; test.add(evidence)
        print("VERIFIED WINDOW TITLE CONTRAST: \(title) \(ratio):1")
        return true
    }
}
