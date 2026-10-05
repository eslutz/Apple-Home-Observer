#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Configure the native scene once the SwiftUI view joins its window.
struct CatalystWindowConfiguration: UIViewRepresentable {
    #if OBSERVER_ACCEPTANCE
    static func requestAcceptanceSize(_ size: CGSize) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        guard scenes.count == 1, let scene = scenes.first else { return }
        let frame = CGRect(origin: CGPoint(x: 100, y: 100), size: size)
        scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)) { error in
            print("Acceptance window geometry request failed: \(error.localizedDescription)")
        }
    }
    #endif

    final class WindowProbe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let scene = window.windowScene else { return }
            scene.title = "Apple Home Observer"
            window.accessibilityLabel = "Apple Home Observer"
            scene.sizeRestrictions?.minimumSize = CGSize(width: 680, height: 520)
            scene.sizeRestrictions?.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                         height: CGFloat.greatestFiniteMagnitude)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            #if OBSERVER_ACCEPTANCE
            guard let window, let scene = window.windowScene, let limits = scene.sizeRestrictions else { return }
            let actual = scene.effectiveGeometry.systemFrame
            let geometry: [String: Double] = ["width": actual.width, "height": actual.height,
                                              "minimumWidth": limits.minimumSize.width, "minimumHeight": limits.minimumSize.height]
            if let data = try? JSONSerialization.data(withJSONObject: geometry),
               let value = String(data: data, encoding: .utf8) { window.accessibilityValue = value }
            #endif
        }
    }
    func makeUIView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.isAccessibilityElement = false
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: WindowProbe, context: Context) { }
}
#endif
