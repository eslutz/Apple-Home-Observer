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

    @ViewBuilder
    private var appContent: some View {
        #if OBSERVER_ACCEPTANCE
        if ProcessInfo.processInfo.environment["OBSERVER_UI_PLATFORM_CONTROL"] == "1" {
            VStack(spacing: 24) {
                Text("Native platform control").font(.title).accessibilityAddTraits(.isHeader)
                Button("Platform control action") { acceptanceAppearance = .dark }
            }
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Native platform control")
        } else {
            ObserverView(runtime: runtime)
        }
        #else
        ObserverView(runtime: runtime)
        #endif
    }

    var body: some Scene {
        WindowGroup("Apple Home Observer") {
            appContent
                #if targetEnvironment(macCatalyst)
                .background(CatalystWindowConfiguration().allowsHitTesting(false).accessibilityHidden(true))
                #endif
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
                #if targetEnvironment(macCatalyst)
                ForEach([1280, 1200, 980, 680], id: \.self) { width in
                    Button("Resize Test Window " + String(width)) {
                        let height = width == 1280 ? 800 : (width == 1200 ? 850 : (width == 980 ? 720 : 520))
                        CatalystWindowConfiguration.requestAcceptanceSize(CGSize(width: width, height: height))
                    }
                }
                #endif
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
