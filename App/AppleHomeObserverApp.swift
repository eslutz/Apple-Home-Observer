import SwiftUI

@main
struct AppleHomeObserverApp: App {
    @StateObject private var runtime = Runtime()
    @State private var acceptanceAppearance: ColorScheme?

    private var auditAppearance: ColorScheme? {
        if let acceptanceAppearance { return acceptanceAppearance }
        if ProcessInfo.processInfo.environment["OBSERVER_UI_SYSTEM_APPEARANCE"] == "1" { return nil }
        guard Runtime.auditMode != nil else { return nil }
        return ProcessInfo.processInfo.environment["OBSERVER_UI_APPEARANCE"] == "dark" ? .dark : .light
    }

    var body: some Scene {
        WindowGroup("Apple Home Observer") {
            ObserverView(runtime: runtime)
                .preferredColorScheme(auditAppearance)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if Runtime.auditMode != nil && ProcessInfo.processInfo.environment["OBSERVER_UI_TEXT_SIZE"] == "largest" {
                        size = .accessibility5
                    }
                }
        }
        .commands {
            #if OBSERVER_ACCEPTANCE
            CommandMenu("Acceptance") {
                Button("Toggle Test Appearance") { acceptanceAppearance = auditAppearance == .dark ? .light : .dark }
            }
            #endif
            CommandMenu("Home") {
                Button("Back Up Now") { runtime.backup(.manual) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(runtime.inventory == nil || runtime.busy || !runtime.health.inventoryReady)
                Button("Refresh Inventory") {
                    runtime.reconcile()
                    runtime.adapter.readPositions()
                }
                .keyboardShortcut("r")
                .disabled(runtime.busy)
            }
        }
    }
}
