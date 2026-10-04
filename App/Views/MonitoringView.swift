import SwiftUI

struct MonitoringView: View {
    @ObservedObject var runtime: Runtime
    let chooseFolder: () -> Void
    @AppStorage("monitoringDashboardURL") private var dashboardAddress = ""
    private var dashboardURL: URL? {
        guard let url = URL(string: dashboardAddress), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Private monitoring export").font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("The observer’s private container is isolated by macOS. Grant access to one local folder so the monitoring service can read health and investigation events.")
                .foregroundStyle(ObserverStyle.secondaryText)
            GroupBox("Export status") {
                VStack(alignment: .leading, spacing: 14) {
                    Label(runtime.monitoringExportConfigured ? "Folder access enabled" : "Folder access not enabled",
                          systemImage: runtime.monitoringExportConfigured ? "checkmark.circle" : "lock.shield")
                        .font(.headline)
                    Text(runtime.monitoringExportStatus)
                    LabeledContent("Required folder", value: Runtime.monitoringExportDirectory.path)
                        .textSelection(.enabled)
                    Text("In the folder picker, press Command-Shift-G and enter this path. The app exports only health.json and bounded event logs. Events can contain private Home names and accessory IDs. Encrypted snapshots and recovery keys stay in the app’s private storage.")
                        .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                    Button(runtime.monitoringExportConfigured ? "Choose Folder Again" : "Grant Folder Access", action: chooseFolder)
                        .buttonStyle(.borderedProminent)
                        .tint(ObserverStyle.solidButtonTint)
                        .foregroundStyle(.primary)
                    if runtime.monitoringExportConfigured {
                        Button("Remove Folder Access", role: .destructive) { runtime.removeMonitoringExportAccess() }
                        Text("Removing access stops future exports and leaves existing files in place.")
                            .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("What the monitor receives") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Health flags, counters, and timestamps", systemImage: "heart.text.square")
                    Label("Allowlisted Home metadata and blind investigation events", systemImage: "list.bullet.rectangle")
                    Label("No encrypted Home archives, recovery keys, or accessory labels in Prometheus", systemImage: "lock.doc")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Central dashboard") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Review observer health, backup freshness, configuration drift, reachability, and recent investigation events in Monitoring Services.")
                        .foregroundStyle(ObserverStyle.secondaryText)
                    Text("Dashboard URL (optional)").font(.headline)
                    TextField("", text: $dashboardAddress)
                        .accessibilityLabel("Dashboard URL")
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    if let dashboardURL {
                        Link(destination: dashboardURL) {
                            Label("Open Apple Home Dashboard", systemImage: "chart.xyaxis.line")
                        }.buttonStyle(.bordered)
                    } else if !dashboardAddress.isEmpty {
                        Text("Enter an HTTPS address without a username or password.")
                            .foregroundStyle(ObserverStyle.secondaryText)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
