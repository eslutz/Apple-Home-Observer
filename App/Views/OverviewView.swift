import SwiftUI

struct OverviewView: View {
    @ObservedObject var runtime: Runtime
    @State private var confirmInventory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Home, with a recovery history")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Encrypted snapshots preserve the configuration HomeKit makes available. Observation records changes without operating your accessories.")
                .foregroundStyle(ObserverStyle.secondaryText)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(runtime.health.inventoryReady ? "Inventory ready" : "Setup or review needed",
                          systemImage: runtime.health.inventoryReady ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.headline)
                    Text(runtime.status).accessibilityIdentifier("observer.status")
                    if runtime.busy { ProgressView("Working…") }
                    if !runtime.restoreStatus.isEmpty { Label(runtime.restoreStatus, systemImage: "exclamationmark.triangle") }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if runtime.selectedID.isEmpty {
                ContentUnavailableView("Choose a Home", systemImage: "house", description: Text("Grant Home Data access, then choose the Home to observe in the sidebar."))
            } else {
                GroupBox("Snapshot history") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Accessories", value: runtime.inventory.map { String($0.accessories.count) } ?? "Waiting for inventory")
                        LabeledContent("Unavailable now", value: runtime.inventory == nil ? "—" : String(runtime.health.unavailable))
                        LabeledContent("Recovery coverage notices", value: runtime.inventory == nil ? "—" : String(runtime.health.coverageGaps))
                        LabeledContent("Last reconciliation", value: runtime.health.lastReconcile?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet complete")
                        LabeledContent("Saved snapshots", value: String(runtime.archives.count))
                        LabeledContent("Latest backup", value: runtime.archives.last?.date.formatted(date: .abbreviated, time: .shortened) ?? "Not yet saved")
                        LabeledContent("Daily schedule", value: "2:00 AM · New York")
                        if runtime.health.unavailable > 0 {
                            Text("Unavailable is HomeKit’s current reachability report; it can be intermittent and does not identify the cause.")
                                .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                        }
                    }.padding(8)
                }
            }
            if let pending = runtime.pendingInventory {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Inventory needs review", systemImage: "exclamationmark.triangle").font(.headline)
                        Text("A changed inventory is being held. The previous snapshot remains protected.")
                        if let known = runtime.inventory {
                            ForEach(Array(SnapshotDiff.compare(known, pending).enumerated()), id: \.offset) { _, change in
                                Text(change.kind + ": " + (change.before ?? change.objectID) + " → " + (change.after ?? "missing"))
                                    .font(.callout).textSelection(.enabled)
                            }
                            Button("Review and Accept Inventory") { confirmInventory = true }
                        } else { Text("Waiting for a second matching complete inventory.").foregroundStyle(ObserverStyle.secondaryText) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            if runtime.inventory != nil {
            GroupBox("Planned configuration changes") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Before editing names, rooms, scenes, or automations, mark a planned editing window. Changes are still recorded.")
                    Button("Mark Next 15 Minutes as Planned") {
                        runtime.plannedUntil = Date().addingTimeInterval(900)
                        runtime.status = "Configuration edits are marked planned for 15 minutes."
                    }
                    .disabled(runtime.inventory == nil || !runtime.health.inventoryReady || runtime.busy)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            }
        }
        .confirmationDialog("Accept the changed inventory?", isPresented: $confirmInventory, titleVisibility: .visible) {
            Button("Accept Reviewed Inventory") { runtime.reconcile(approveRemoval: true) }
        } message: {
            Text("Confirm the missing objects are expected. This allows new snapshots of the changed Home; existing encrypted snapshots stay available.")
        }
    }
}
