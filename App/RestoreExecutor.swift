import Foundation
import HomeKit
import CryptoKit

@MainActor extension Runtime {
    func persistJournal(_ journal: RestoreJournal) throws {
        guard let key else { throw ObserverError.invalidArchive }
        try JournalStore(root:root.appendingPathComponent("journals"),key:key).save(journal)
    }

    func applyPreview() async {
        guard let preview, !busy, !journalCheckFailed, let home = adapter.home, let store, let key, recoveryJournals.isEmpty || (recoveryJournals.count == 1 && recoveryJournalID == recoveryJournals.first?.id) else { return }
        plannedUntil = Date().addingTimeInterval(900)
        busy = true; defer { busy = false; self.preview = nil; refreshJournals(); reconcile() }
        do {
            let current = try adapter.snapshot(); try preview.validate(current:current)
            let predecessor = try store.save(current,reason:.predecessor,protecting:Set(recoveryJournals.map(\.predecessorFile)))
            var journal = RestoreJournal(predecessorFile:predecessor.file,preview:preview); journal.recoveryOf = recoveryJournalID
            try persistJournal(journal)
            var rooms = home.rooms.reduce(into: [String:HMRoom]()) { $0[$1.uniqueIdentifier.uuidString] = $1 }; rooms[home.roomForEntireHome().uniqueIdentifier.uuidString] = home.roomForEntireHome()
            var scenes = Dictionary(uniqueKeysWithValues:home.actionSets.map { ($0.uniqueIdentifier.uuidString,$0) })
            let services = Dictionary(uniqueKeysWithValues:home.accessories.flatMap(\.services).map { ($0.uniqueIdentifier.uuidString,$0) })
            let chars = Dictionary(uniqueKeysWithValues:home.accessories.flatMap(\.services).flatMap(\.characteristics).map { ($0.uniqueIdentifier.uuidString,$0) })
            let changedScenes = Set(preview.operations.filter { $0.kind == .scene }.compactMap(\.currentID))
            let changedTriggers = Set(preview.operations.filter { $0.kind == .automation }.compactMap(\.currentID))
            // Disable affected triggers before editing any scene definition.
            for trigger in home.triggers where changedTriggers.contains(trigger.uniqueIdentifier.uuidString) || trigger.actionSets.contains(where: { changedScenes.contains($0.uniqueIdentifier.uuidString) }) {
                journal.preparingTriggerID = trigger.uniqueIdentifier.uuidString; journal.state = "preparing"; try persistJournal(journal)
                do { try await trigger.enable(false) }
                catch { journal.state = "partial_failure"; try persistJournal(journal); restoreStatus = "Restore stopped while disabling a trigger. Review its encrypted journal and predecessor."; return }
                journal.disabledTriggerIDs.append(trigger.uniqueIdentifier.uuidString); journal.preparingTriggerID = nil; try persistJournal(journal)
            }
            for (index,op) in preview.operations.enumerated() {
                journal.inFlight = index; journal.state = "applying"; try persistJournal(journal)
                do {
                    switch op.kind {
                    case .homeName: try await home.updateName(op.name!)
                    case .room:
                        let value = try Coding.decode(NamedObject.self,op.payload!)
                        if let id = op.currentID, let r = rooms[id] { try await r.updateName(value.name) }
                        else { let r = try await home.addRoom(named:value.name); rooms[op.savedID] = r; journal.created[op.savedID] = r.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.room.rawValue; try persistJournal(journal) }
                    case .accessoryName:
                        guard let a = home.accessories.first(where: { $0.uniqueIdentifier.uuidString == op.currentID }) else { throw ObserverError.invalidMapping }; try await a.updateName(op.name!)
                    case .accessoryRoom:
                        let roomID = try Coding.decode(String?.self,op.payload!)
                        guard let a = home.accessories.first(where: { $0.uniqueIdentifier.uuidString == op.currentID }), let room = roomID.flatMap({ rooms[$0] }) else { throw ObserverError.invalidMapping }
                        try await home.assignAccessory(a,to:room)
                    case .serviceName:
                        guard let service = services[op.currentID!] else { throw ObserverError.invalidMapping }; try await service.updateName(op.name!)
                    case .zone:
                        let value = try Coding.decode(NamedObject.self,op.payload!)
                        let zone: HMZone
                        if let id = op.currentID, let existing = home.zones.first(where: { $0.uniqueIdentifier.uuidString == id }) { zone = existing; try await zone.updateName(value.name) }
                        else { zone = try await home.addZone(named:value.name); journal.created[op.savedID] = zone.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.zone.rawValue; try persistJournal(journal) }
                        let desired = try value.members.map { id -> HMRoom in guard let room = rooms[id] else { throw ObserverError.invalidMapping }; return room }
                        for room in zone.rooms where !desired.contains(room) { try await zone.removeRoom(room) }
                        for room in desired where !zone.rooms.contains(room) { try await zone.addRoom(room) }
                    case .group:
                        let value = try Coding.decode(NamedObject.self,op.payload!)
                        let group: HMServiceGroup
                        if let id = op.currentID, let existing = home.serviceGroups.first(where: { $0.uniqueIdentifier.uuidString == id }) { group = existing; try await group.updateName(value.name) }
                        else { group = try await home.addServiceGroup(named:value.name); journal.created[op.savedID] = group.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.group.rawValue; try persistJournal(journal) }
                        let desired = try value.members.map { id -> HMService in guard let service = services[id] else { throw ObserverError.invalidMapping }; return service }
                        for service in group.services where !desired.contains(service) { try await group.removeService(service) }
                        for service in desired where !group.services.contains(service) { try await group.addService(service) }
                    case .scene:
                        let value = try Coding.decode(SceneRecord.self,op.payload!)
                        let scene: HMActionSet
                        if let id = op.currentID, let existing = scenes[id] { scene = existing; try await scene.updateName(value.name) }
                        else { scene = try await home.addActionSet(named:value.name); scenes[op.savedID] = scene; journal.created[op.savedID] = scene.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.scene.rawValue; try persistJournal(journal) }
                        // Definition edits only. This code never calls executeActionSet or writeValue.
                        let actions = try value.actions.map { a -> HMAction in guard let c = chars[a.characteristicID], c.properties.contains(HMCharacteristicPropertyWritable), let v = a.value.foundation as? (NSCopying & NSObjectProtocol) else { throw ObserverError.unsupported }; return HMCharacteristicWriteAction(characteristic:c,targetValue:v) }
                        for action in scene.actions { try await scene.removeAction(action) }
                        for action in actions { try await scene.addAction(action) }
                    case .automation:
                        let value = try Coding.decode(AutomationRecord.self,op.payload!)
                        let trigger: HMTrigger
                        let old = home.triggers.first { $0.uniqueIdentifier.uuidString == op.currentID }
                        if let old { try await old.enable(false) }
                        if value.kind == "timer" {
                            guard value.timeZone == nil, let date = value.fireDate else { throw ObserverError.unsupported }
                            let recurrence = value.recurrence.first.map { HomeAdapter.components($0) }
                            if let existing = old as? HMTimerTrigger { trigger = existing; try await existing.updateFireDate(date); try await existing.updateRecurrence(recurrence) }
                            else { guard old == nil else { throw ObserverError.unsupported }; trigger = HMTimerTrigger(name:value.name,fireDate:date,recurrence:recurrence); try await home.addTrigger(trigger); journal.created[op.savedID] = trigger.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.trigger.rawValue; try persistJournal(journal) }
                        } else if value.kind == "event" {
                            let events = try value.events.map { try Self.makeEvent($0,chars:chars) }; let ends = try value.endEvents.map { try Self.makeEvent($0,chars:chars) }; let recurrences = value.recurrence.map { HomeAdapter.components($0) }; let predicate = try value.predicate.map(Self.makePredicate)
                            if let existing = old as? HMEventTrigger { trigger = existing; try await existing.updateEvents(events); try await existing.updateEndEvents(ends); try await existing.updateRecurrences(recurrences); try await existing.updatePredicate(predicate); try await existing.updateExecuteOnce(value.executesOnce) }
                            else { guard old == nil else { throw ObserverError.unsupported }; let t = HMEventTrigger(name:value.name,events:events,end:ends,recurrences:recurrences,predicate:predicate); trigger = t; try await home.addTrigger(t); journal.created[op.savedID] = t.uniqueIdentifier.uuidString; journal.createdKinds[op.savedID] = RecoveryObjectKind.trigger.rawValue; try persistJournal(journal); try await t.updateExecuteOnce(value.executesOnce) }
                        } else { throw ObserverError.unsupported }
                        try await trigger.enable(false); try await trigger.updateName(value.name)
                        let desired = try value.sceneIDs.map { id -> HMActionSet in guard let scene = scenes[id] else { throw ObserverError.invalidMapping }; return scene }
                        for scene in trigger.actionSets where !desired.contains(scene) { try await trigger.removeActionSet(scene) }
                        for scene in desired where !trigger.actionSets.contains(scene) { try await trigger.addActionSet(scene) }
                    }
                    journal.completed.append(index); journal.inFlight = nil; try persistJournal(journal)
                } catch {
                    journal.state = "partial_failure"; try persistJournal(journal)
                    event("apple_home.restore_partial",attributes:["operation.index":index,"journal.id":journal.id],severity:"ERROR")
                    restoreStatus = "Restore stopped at operation \(index+1). Use the predecessor archive to preview rollback. Inspect the journal before deleting any newly created objects."
                    return
                }
            }
            journal.state = "completed"; try persistJournal(journal)
            if let originalID = recoveryJournalID {
                let journalStore = try JournalStore(root:root.appendingPathComponent("journals"),key:key)
                var original = try journalStore.load(originalID)
                original.predecessorRestored = true; original.predecessorMappings = preview.mappings; original.state = "predecessor_restored"
                try journalStore.save(original)
                restoreStatus = "Pre-restore definitions are back. Review the Home, then remove only the objects this journal created."
            } else {
                restoreStatus = "Restore definitions applied. Review triggers in Home before enabling."
            }
            event("apple_home.restore_completed",attributes:["operation.count":journal.completed.count,"journal.id":journal.id])
        } catch { restoreStatus = "Restore refused: \(String(describing:error))"; event("apple_home.restore_refused",attributes:[:],severity:"ERROR") }
    }
    func removeCreatedRecoveryObjects(_ originalID: String) async {
        guard !busy, let home = adapter.home, home.uniqueIdentifier.uuidString == selectedID,
              let key, let journalStore = try? JournalStore(root:root.appendingPathComponent("journals"),key:key),
              var original = try? journalStore.load(originalID), original.preview.homeID == selectedID, original.predecessorRestored else {
            restoreStatus = "Restore the encrypted predecessor successfully before removing created objects."; return
        }
        guard let store, let predecessorIndex = archives.first(where: { $0.file == original.predecessorFile }),
              let predecessor = try? store.load(predecessorIndex), let current = try? adapter.snapshot() else {
            restoreStatus = "Cleanup is blocked until the predecessor and current Home inventory can be read."; return
        }
        do { try RecoveryCleanupPlanner.verifyPredecessor(predecessor:predecessor,current:current,mappings:original.predecessorMappings) }
        catch { restoreStatus = "Cleanup is blocked because the current Home does not yet match the restored predecessor. Refresh and review before retrying."; return }
        let plan: [RecoveryCleanupItem]
        do { plan = try RecoveryCleanupPlanner.plan(for:original) }
        catch { restoreStatus = "Cleanup is blocked because one or more created object IDs are not fully recorded. Review those objects manually in Home."; return }
        busy = true; defer { busy = false; refreshJournals(); reconcile() }
        original.state = "cleaning_created_objects"
        do {
            for item in plan {
                original.cleanupInFlightID = item.homeKitID
                try journalStore.save(original)
                switch item.kind {
                case .trigger:
                    if let object = home.triggers.first(where: { $0.uniqueIdentifier.uuidString == item.homeKitID }) { try await home.removeTrigger(object) }
                case .scene:
                    if let object = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == item.homeKitID }) { try await home.removeActionSet(object) }
                case .group:
                    if let object = home.serviceGroups.first(where: { $0.uniqueIdentifier.uuidString == item.homeKitID }) { try await home.removeServiceGroup(object) }
                case .zone:
                    if let object = home.zones.first(where: { $0.uniqueIdentifier.uuidString == item.homeKitID }) { try await home.removeZone(object) }
                case .room:
                    if let object = home.rooms.first(where: { $0.uniqueIdentifier.uuidString == item.homeKitID }) { try await home.removeRoom(object) }
                }
                if !original.removedCreatedIDs.contains(item.homeKitID) { original.removedCreatedIDs.append(item.homeKitID) }
                original.cleanupInFlightID = nil
                try journalStore.save(original)
            }
            original.state = "rolled_back"; original.predecessorRestored = true
            try journalStore.save(original)
            restoreStatus = "Created restore objects removed in dependency order. Review the Home and re-enable only automations you trust."
            event("apple_home.restore_cleanup_completed",attributes:["journal.id":original.id,"object.count":original.removedCreatedIDs.count])
        } catch {
            original.state = "cleanup_partial"
            try? journalStore.save(original)
            restoreStatus = "Cleanup stopped at one object. Earlier removals are journaled; review the recovery list before retrying."
            event("apple_home.restore_cleanup_partial",attributes:["journal.id":original.id,"object.count":original.removedCreatedIDs.count],severity:"ERROR")
        }
    }

    func refreshJournals() {
        do {
            guard let key else { throw ObserverError.invalidArchive }
            recoveryJournals = try JournalStore(root:root.appendingPathComponent("journals"),key:key).pending(); journalCheckFailed = false
        } catch { restoreStatus = "Journal recovery check failed. Restore remains blocked."; journalCheckFailed = true }
    }
    func previewRollback(_ journal: RestoreJournal) {
        guard journal.preview.homeID == selectedID, let item = archives.first(where: { $0.file == journal.predecessorFile }) else { restoreStatus = "Select the original Home to preview this journal's predecessor."; return }
        makePreview(item); recoveryJournalID = journal.id
    }
    func acknowledgeRecovery(_ journal: RestoreJournal) {
        do { var reviewed = journal; reviewed.state = "reviewed_recovery"; try persistJournal(reviewed); recoveryJournalID = nil; refreshJournals() }
        catch { restoreStatus = "Recovery acknowledgement could not be saved." }
    }
    static func makeEvent(_ e: EventRecord,chars:[String:HMCharacteristic]) throws -> HMEvent {
        switch e.kind {
        case "characteristic": guard let id = e.characteristicID, let c = chars[id] else { throw ObserverError.invalidMapping }; return HMCharacteristicEvent(characteristic:c,triggerValue:e.value?.foundation as? (NSCopying & NSObjectProtocol))
        case "calendar": guard let d = e.calendar else { throw ObserverError.unsupported }; return HMCalendarEvent(fire:HomeAdapter.components(d,zone:e.timeZone))
        case "significant": guard let name = e.significantEvent, [HMSignificantEvent.sunrise.rawValue,HMSignificantEvent.sunset.rawValue].contains(name) else { throw ObserverError.unsupported }; return HMSignificantTimeEvent(significantEvent:HMSignificantEvent(rawValue:name),offset:e.offset.map { HomeAdapter.components($0) })
        default: throw ObserverError.unsupported
        }
    }
    static func makePredicate(_ p: PredicateRecord) throws -> NSPredicate {
        if let children = p.children {
            let predicates = try children.map(makePredicate)
            switch p.kind { case "and": return NSCompoundPredicate(andPredicateWithSubpredicates:predicates); case "or": return NSCompoundPredicate(orPredicateWithSubpredicates:predicates); case "not": guard predicates.count == 1 else { throw ObserverError.unsupported }; return NSCompoundPredicate(notPredicateWithSubpredicate:predicates[0]); default: throw ObserverError.unsupported }
        }
        guard p.kind == "comparison", p.keyPath == HMCharacteristicValueKeyPath, let value = p.value, let comparison = p.comparison, comparison <= 5, p.modifier == 0, let type = NSComparisonPredicate.Operator(rawValue:comparison) else { throw ObserverError.unsupported }
        return NSComparisonPredicate(leftExpression:NSExpression(forKeyPath:HMCharacteristicValueKeyPath),rightExpression:NSExpression(forConstantValue:value.foundation),modifier:.direct,type:type,options:NSComparisonPredicate.Options(rawValue:p.options ?? 0))
    }
}
