import SwiftUI

struct CoverageView: View {
    @ObservedObject var runtime: Runtime

    @State private var search = ""

    private struct Entry: Identifiable {
        let index: Int
        let category: String
        let name: String
        let gap: CoverageGap
        var id: Int { index }
    }

    private var entries: [Entry] {
        guard let inventory = runtime.inventory else { return [] }
        let all = inventory.coverage.enumerated().map { index, gap -> Entry in
            let owner: (String, String)
            if gap.objectID == inventory.homeID { owner = ("Home", inventory.name) }
            else if let value = inventory.automations.first(where: { $0.id == gap.objectID }) { owner = ("Automation", value.name) }
            else if let value = inventory.scenes.first(where: { $0.id == gap.objectID }) { owner = ("Scene", value.name) }
            else if let value = inventory.accessories.first(where: { $0.id == gap.objectID }) { owner = ("Accessory", value.name) }
            else if let value = inventory.accessories.flatMap(\.services).first(where: { $0.id == gap.objectID }) { owner = ("Service", value.name) }
            else if inventory.accessories.flatMap(\.services).flatMap(\.characteristics).contains(where: { $0.id == gap.objectID }) { owner = ("Characteristic", "HomeKit characteristic") }
            else if let value = inventory.groups.first(where: { $0.id == gap.objectID }) { owner = ("Group", value.name) }
            else if let value = inventory.zones.first(where: { $0.id == gap.objectID }) { owner = ("Zone", value.name) }
            else if let value = inventory.rooms.first(where: { $0.id == gap.objectID }) { owner = ("Room", value.name) }
            else { owner = ("HomeKit object", "Unmatched object") }
            return Entry(index: index, category: owner.0, name: owner.1, gap: gap)
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.category.localizedCaseInsensitiveContains(query) ||
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.gap.objectID.localizedCaseInsensitiveContains(query) ||
            $0.gap.reason.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            Text("Know what you can recover").font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Apple’s public HomeKit API does not expose every Home setting. Pairing credentials, access permissions, favorites, hub selection, and some automations require manual recovery.")
                .foregroundStyle(ObserverStyle.secondaryText)
            if let inventory = runtime.inventory {
                if inventory.coverage.isEmpty {
                    Label("No additional coverage notices in this inventory", systemImage: "checkmark.circle")
                } else {
                    TextField("Search notices", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search recovery coverage notices")
                    Text("Showing \(entries.count) of \(inventory.coverage.count) notices")
                        .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                    if entries.isEmpty {
                        ContentUnavailableView("No matching notices", systemImage: "magnifyingglass", description: Text("Try an object name, identifier, or reason."))
                    } else {
                        ForEach(entries) { entry in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(entry.name, systemImage: entry.category == "Home" ? "house" : "info.circle")
                                        .font(.headline)
                                    Text(entry.category).font(.subheadline).foregroundStyle(ObserverStyle.secondaryText)
                                    Text(entry.gap.reason).fixedSize(horizontal: false, vertical: true)
                                    LabeledContent("HomeKit ID", value: entry.gap.objectID)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Waiting for inventory", systemImage: "checklist", description: Text("Coverage notices appear after the selected Home is available."))
            }
            DisclosureGroup("Local storage and monitoring") {
                Text(runtime.root.path).font(.callout.monospaced()).textSelection(.enabled).padding(.top, 8)
                Text("Encrypted archives, health data, and diagnostic events are stored locally. Central monitoring must be installed and verified separately.")
                    .foregroundStyle(ObserverStyle.secondaryText).padding(.top, 8)
            }
        }
    }
}
