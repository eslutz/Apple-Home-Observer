import Foundation

/// Installation defaults contain no network endpoint or developer identity.
enum ObserverConfiguration {
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "org.example.AppleHomeObserver" }
    static var monitoringFolder: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "ObserverMonitoringFolder") as? String ?? ""
        let components = configured.split(separator: "/", omittingEmptySubsequences: false)
        guard !configured.isEmpty, !configured.hasPrefix("/"), !components.contains(".."), !components.contains(".") else { return ".local/state/apple-home-observer" }
        return configured
    }
}
