import SwiftUI

struct RecoveryView: View {
    @ObservedObject var runtime: Runtime
    let importArchive: () -> Void
    let importKey: () -> Void
    var revealConfirmation: () -> Void = {}
    private enum Confirmation {
        case restore
        case cleanup(String)
        case finish(RestoreJournal)

        var title: String {
            switch self {
            case .restore: "Apply the reviewed restore?"
            case .cleanup: "Remove objects created by this restore?"
            case .finish: "Finish recovery review?"
            }
        }
        var message: String {
            switch self {
            case .restore: "This changes your Home configuration. An encrypted predecessor and journal are saved first. Restored automations stay disabled. Recovery can restore the predecessor, then remove only exact IDs this journal created after a separate review."
            case .cleanup: "The app removes only HomeKit IDs recorded in this encrypted journal, in dependency order: automations, scenes, groups, zones, then rooms. Existing accessories are never deleted. A missing or type-mismatched journal identity blocks cleanup."
            case .finish: "Only finish after checking the Home configuration and handling any newly created objects. This clears the recovery block. It does not undo configuration changes or remove objects you have not handled."
            }
        }
    }
    @State private var confirmation: Confirmation?

    var body: some View {
        Group {
            if let action = confirmation {
                confirmationContent(action)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Review before restoring").font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Preview the exact configuration changes and resolve accessory identities before applying. A predecessor snapshot and recovery journal are saved first. Restored automations stay disabled for review.")
                        .foregroundStyle(ObserverStyle.secondaryText)
                    AdaptiveActionStack {
                        Button("Import Encrypted Snapshot", action: importArchive).buttonStyle(.bordered).foregroundStyle(.primary)
                        Button("Import Recovery Key", action: importKey).buttonStyle(.bordered).foregroundStyle(.primary)
                    }
                    if !runtime.restoreStatus.isEmpty {
                        Label(runtime.restoreStatus, systemImage: "info.circle").textSelection(.enabled)
                    }
                    ForEach(runtime.recoveryJournals, id: \.id) { journal in
                        let remainingObjects = journal.created.values.filter { !journal.removedCreatedIDs.contains($0) }.count
                        GroupBox("Interrupted restore") {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("State", value: journal.state)
                                LabeledContent("Completed operations", value: String(journal.completed.count))
                                LabeledContent("Disabled automations", value: String(journal.disabledTriggerIDs.count))
                                LabeledContent("Journaled objects remaining", value: String(remainingObjects))
                                Text("A predecessor restore puts prior definitions back. Then remove only objects whose exact IDs this journal recorded.")
                                DisclosureGroup("Created object identifiers") {
                                    Text(journal.created.values.sorted().joined(separator: "\n")).textSelection(.enabled)
                                }.font(.callout.monospaced())
                                if journal.predecessorRestored {
                                    Label("Predecessor restored; created objects are still being reviewed.", systemImage: "checkmark.circle")
                                    Button("Remove \(remainingObjects) Journaled Objects…") { confirmation = .cleanup(journal.id) }
                                        .disabled(remainingObjects == 0)
                                } else {
                                    Button("Preview Predecessor for Rollback") { runtime.previewRollback(journal) }
                                }
                                Button("Finish Manual Recovery Review…") { confirmation = .finish(journal) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                    if runtime.savedForRestore != nil, !runtime.mappingChoices.isEmpty {
                        GroupBox("Replacement accessories") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Choose replacements only after verifying identity. Names help you choose; they are never matched automatically.")
                                ForEach(runtime.mappingChoices) { choice in
                                    Picker(choice.name, selection: Binding(get: { runtime.restoreMappings[choice.id] ?? "" }, set: {
                                        runtime.restoreMappings[choice.id] = $0; runtime.rebuildPreview()
                                    })) {
                                        Text("Choose a replacement").tag("")
                                        ForEach(choice.candidates) { Text($0.name).tag($0.id) }
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    }
                    if let preview = runtime.preview {
                        GroupBox("\(preview.operations.count) proposed changes") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(preview.operations.enumerated()), id: \.offset) { _, operation in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(operation.name ?? operation.savedID).font(.headline)
                                        Text(operation.kind.rawValue).font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                                    }.textSelection(.enabled)
                                    Divider()
                                }
                                if !preview.unresolvedIDs.isEmpty {
                                    Label("Resolve all identities before applying", systemImage: "exclamationmark.triangle").font(.headline)
                                    Text(preview.unresolvedIDs.joined(separator: "\n")).font(.callout.monospaced()).textSelection(.enabled)
                                }
                                Button("Apply Reviewed Restore…") { confirmation = .restore }
                                    .buttonStyle(.borderedProminent)
                                    .tint(ObserverStyle.solidButtonTint)
                                    .foregroundStyle(.primary)
                                    .disabled(!preview.unresolvedIDs.isEmpty || runtime.busy || runtime.journalCheckFailed || (!runtime.recoveryJournals.isEmpty && runtime.recoveryJournalID == nil))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                    } else if runtime.recoveryJournals.isEmpty {
                        ObserverEmptyState("Choose a snapshot", description: Text("Select Preview Restore in Backups, or import an encrypted snapshot to inspect its changes."))
                    }
                    Text("Restoring definitions does not execute scenes or move devices.")
                        .font(.callout).foregroundStyle(ObserverStyle.secondaryText)
                }
            }
        }
    }

    private func confirmationContent(_ action: Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(action.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(action.message).font(.body)
            AdaptiveActionStack {
                Button("Cancel", role: .cancel) { confirmation = nil }
                    .buttonStyle(.bordered).foregroundStyle(.primary)
                    .keyboardShortcut(.cancelAction)
                switch action {
                case .restore:
                    Button("Apply Restore", role: .destructive) {
                        confirmation = nil
                        Task { await runtime.applyPreview() }
                    }.buttonStyle(.bordered).foregroundStyle(.primary)
                case .cleanup(let id):
                    Button("Remove Journaled Objects", role: .destructive) {
                        confirmation = nil
                        Task { await runtime.removeCreatedRecoveryObjects(id) }
                    }.buttonStyle(.bordered).foregroundStyle(.primary)
                case .finish(let journal):
                    Button("I Have Reviewed and Handled Created Objects") {
                        confirmation = nil
                        runtime.acknowledgeRecovery(journal)
                    }.buttonStyle(.bordered).foregroundStyle(.primary)
                }
            }
        }
        .accessibilityIdentifier("observer.recovery.confirmation")
        .onAppear(perform: revealConfirmation)
    }
}
