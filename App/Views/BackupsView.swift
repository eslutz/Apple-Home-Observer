import SwiftUI

struct BackupsView: View {
    @ObservedObject var runtime: Runtime
    let preview: (SnapshotIndex) -> Void
    let export: (SnapshotIndex) -> Void
    let exportKey: () -> Void
    @State private var search = ""

    private var filteredArchives: [SnapshotIndex] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = runtime.archives.reversed()
        guard !query.isEmpty else { return Array(items) }
        return items.filter {
            $0.reason.rawValue.localizedCaseInsensitiveContains(query) ||
            $0.date.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(query) ||
            $0.file.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            Text("Encrypted backups").font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("The initial baseline, 30 daily snapshots, and 100 change or manual snapshots are retained. Snapshots needed by unresolved recovery journals are protected.")
                .foregroundStyle(ObserverStyle.secondaryText)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(runtime.recoveryExported ? "Recovery-key file exported" : "Save your recovery key",
                          systemImage: runtime.recoveryExported ? "key" : "exclamationmark.shield")
                        .font(.headline)
                    Text("Exporting confirms that a key file was saved; it cannot confirm that a separate copy is safely stored. Keep the key in a password manager or secure offline location, apart from the encrypted backups. Without it, losing this Mac’s Keychain makes the snapshots unrecoverable.")
                    Button("Export Recovery Key", action: exportKey).disabled(runtime.key == nil)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if runtime.archives.isEmpty {
                ContentUnavailableView("No snapshots yet", systemImage: "externaldrive", description: Text("A baseline is saved after two matching complete inventories. You can then make a manual backup from the toolbar."))
            } else {
                TextField("Search snapshots", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search snapshots")
                if filteredArchives.isEmpty {
                    ContentUnavailableView("No matching snapshots", systemImage: "magnifyingglass", description: Text("Try a different date, backup type, or file name."))
                } else {
                    Text("\(filteredArchives.count) of \(runtime.archives.count) snapshots")
                        .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                    LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(filteredArchives, id: \.file) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Spacer()
                                Text(item.reason.rawValue.capitalized).font(.subheadline).foregroundStyle(ObserverStyle.secondaryText)
                            }
                            AdaptiveActionStack(minimumHorizontalWidth: 320) {
                                Button("Preview Restore") { preview(item) }
                                Button("Export Snapshot") { export(item) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                    }
                }
            }
        }
    }
}
