import SwiftUI
import UniformTypeIdentifiers

private enum ObserverSection: String, CaseIterable, Identifiable {
    case overview, backups, recovery, blinds, coverage, monitoring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .backups: "Backups"
        case .recovery: "Recovery"
        case .blinds: "Blind Investigation"
        case .coverage: "Backup Coverage"
        case .monitoring: "Monitoring"
        }
    }
    var icon: String {
        switch self {
        case .overview: "house"
        case .backups: "externaldrive"
        case .recovery: "arrow.counterclockwise"
        case .blinds: "blinds.horizontal.closed"
        case .coverage: "checklist"
        case .monitoring: "waveform.path.ecg"
        }
    }
}

struct ObserverView: View {
    @ObservedObject var runtime: Runtime
    @Environment(\.dynamicTypeSize) private var textSize
    @ObservedObject private var adapter: HomeAdapter
    @SceneStorage("observer.section") private var section = ObserverSection.overview.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var exportDocument: PrivateDocument?
    @State private var exporting = false
    @State private var exportName = "AppleHome.archive"
    @State private var importing = false
    @State private var importingRecovery = false
    @State private var importingMonitoringFolder = false

    init(runtime: Runtime) {
        self.runtime = runtime
        self.adapter = runtime.adapter
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding<String?>(get: { section }, set: { if let value = $0 { section = value; if textSize.isAccessibilitySize { columnVisibility = .detailOnly } } })) {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Home").font(.caption).foregroundStyle(ObserverStyle.secondaryText)
                        Menu {
                            Button("Choose a Home") { runtime.selectedID = "" }
                            ForEach(runtime.homeChoices) { home in
                                Button(home.name) { runtime.selectedID = home.id }
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(runtime.homeChoices.first(where: { $0.id == runtime.selectedID })?.name ?? "Choose a Home")
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                            }
                        }
                        .disabled(runtime.busy)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Home")
                        .accessibilityValue(runtime.homeChoices.first(where: { $0.id == runtime.selectedID })?.name ?? "Choose a Home")
                        .accessibilityIdentifier("observer.home")
                    }
                }
                Section {
                    ForEach(ObserverSection.allCases) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: item.icon).accessibilityHidden(true)
                            Text(item.title).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("observer.section." + item.rawValue)
                            .tag(item.rawValue)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: textSize.isAccessibilitySize ? 440 : 260, max: 520)
            .listStyle(.sidebar)
            .tint(ObserverStyle.linkTint)
            .accessibilityIdentifier("observer.sidebar")
            .navigationTitle("Observer")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch ObserverSection(rawValue: section) ?? .overview {
                    case .overview: OverviewView(runtime: runtime)
                    case .backups:
                        BackupsView(runtime: runtime, preview: {
                            runtime.makePreview($0)
                            section = ObserverSection.recovery.rawValue
                        }, export: exportArchive, exportKey: exportKey)
                    case .recovery:
                        RecoveryView(runtime: runtime, importArchive: {
                            importingRecovery = false; importing = true
                        }, importKey: {
                            importingRecovery = true; importing = true
                        })
                    case .blinds: BlindInvestigationView(runtime: runtime)
                    case .coverage: CoverageView(runtime: runtime)
                    case .monitoring: MonitoringView(runtime: runtime) { importingMonitoringFolder = true }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle((ObserverSection(rawValue: section) ?? .overview).title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if textSize.isAccessibilitySize || columnVisibility == .detailOnly {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                        } label: { Label("Navigation", systemImage: "sidebar.left") }
                        .accessibilityIdentifier("observer.navigation.toggle")
                    }
                }
                ToolbarItem(id: "refresh", placement: .primaryAction) {
                    Button {
                        runtime.reconcile(); adapter.readPositions()
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh the selected Home’s inventory (Command-R)")
                    .disabled(runtime.busy)
                }
                if runtime.inventory != nil && !runtime.busy && runtime.health.inventoryReady {
                ToolbarItem(id: "backup", placement: .primaryAction) {
                    Button { runtime.backup(.manual) } label: {
                        Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                    }
                    .help("Save an encrypted snapshot (Shift-Command-B)")
                }
                }
            }
        }
        .onChange(of: textSize) { _, size in
            columnVisibility = size.isAccessibilitySize ? .detailOnly : .all
        }
        .tint(ObserverStyle.linkTint)
        .frame(minWidth: 680, idealWidth: 980, minHeight: 520, idealHeight: 720)
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .data, defaultFilename: exportName) { result in
            if case .success(let url) = result {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    if exportName.hasSuffix("recovery-key") {
                        runtime.recoveryExported = true
                        UserDefaults.standard.set(true, forKey: "recoveryExported")
                    }
                } catch { runtime.status = "Exported file permissions need to be set to owner-only before use." }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if importingRecovery { runtime.importRecovery(url) }
                else { runtime.importArchive(url) }
            }
        }
        .fileImporter(isPresented: $importingMonitoringFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { runtime.chooseMonitoringExportFolder(url) }
        }
    }

    private func exportArchive(_ item: SnapshotIndex) {
        if Runtime.auditMode != nil {
            exportDocument = .init(data: Data("Synthetic acceptance export".utf8))
            exportName = "sample-snapshot.txt"; exporting = true; return
        }
        do {
            guard let store = runtime.store else { return }
            exportDocument = .init(data: try PrivateFiles.read(store.root.appendingPathComponent(item.file), maximum: ArchiveCodec.maximumBytes))
            exportName = item.file
            exporting = true
        } catch { runtime.status = "Archive export failed. The saved snapshot is unchanged." }
    }

    private func exportKey() {
        guard let key = runtime.key else { return }
        do {
            exportDocument = .init(data: try RecoveryKeyCodec.encode(key))
            exportName = "AppleHome.recovery-key"
            exporting = true
        } catch { runtime.status = "Recovery key could not be exported." }
    }
}
