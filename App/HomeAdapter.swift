import Foundation
import HomeKit

@MainActor final class HomeAdapter: NSObject, HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate, ObservableObject {
    @Published var homes: [HMHome] = []
    @Published var authorized = false
    let manager: HMHomeManager?
    var changed: (() -> Void)?
    var state: ((HMAccessory, HMCharacteristic?) -> Void)?
    private(set) var lastCaptureFailure: String?
    var selectedID: String? { didSet { attach(); changed?() } }
    private var subscribed = Set<String>()
    init(observe: Bool = true) { manager = observe ? HMHomeManager() : nil; super.init(); manager?.delegate = self }
    var home: HMHome? { manager?.homes.first { $0.uniqueIdentifier.uuidString == selectedID } }
    private func refreshManagerState() {
        homes = manager?.homes ?? []
        authorized = manager?.authorizationStatus.contains(.authorized) ?? false
        attach()
        changed?()
    }
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor [weak self] in self?.refreshManagerState() }
    }
    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor [weak self] in self?.refreshManagerState() }
    }
    func attach() {
        guard let home else { return }; home.delegate = self
        for a in home.accessories {
            a.delegate = self
            for c in a.services.flatMap(\.characteristics) where [HMCharacteristicTypeCurrentPosition, HMCharacteristicTypeTargetPosition, HMCharacteristicTypePositionState].contains(c.characteristicType) {
                let id = c.uniqueIdentifier.uuidString
                if c.properties.contains(HMCharacteristicPropertySupportsEventNotification), !subscribed.contains(id) {
                    c.enableNotification(true) { [weak self] error in Task { @MainActor in if error == nil { self?.subscribed.insert(id) } } }
                }
            }
        }
    }
    func readPositions() {
        for accessory in home?.accessories ?? [] {
            for characteristic in accessory.services.flatMap(\.characteristics)
            where [HMCharacteristicTypeCurrentPosition, HMCharacteristicTypeTargetPosition].contains(characteristic.characteristicType)
                && characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                let accessoryID = accessory.uniqueIdentifier.uuidString
                let characteristicID = characteristic.uniqueIdentifier.uuidString
                characteristic.readValue { [weak self] error in
                    guard error == nil else { return }
                    Task { @MainActor [weak self] in self?.emitState(accessoryID:accessoryID,characteristicID:characteristicID) }
                }
            }
        }
    }
    private func emitState(accessoryID: String, characteristicID: String?) {
        guard let accessory = home?.accessories.first(where: { $0.uniqueIdentifier.uuidString == accessoryID }) else { return }
        let characteristic = characteristicID.flatMap { id in
            accessory.services.flatMap(\.characteristics).first(where: { $0.uniqueIdentifier.uuidString == id })
        }
        state?(accessory, characteristic)
    }
    nonisolated func homeDidUpdateName(_ home: HMHome) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        Task { @MainActor [weak self] in self?.attach(); self?.changed?() }
    }
    nonisolated func home(_ home: HMHome, didRemove accessory: HMAccessory) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func home(_ home: HMHome, didUpdateNameFor room: HMRoom) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func home(_ home: HMHome, didAdd room: HMRoom) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func home(_ home: HMHome, didRemove room: HMRoom) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func accessoryDidUpdateName(_ accessory: HMAccessory) { Task { @MainActor [weak self] in self?.changed?() } }
    nonisolated func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        Task { @MainActor [weak self] in self?.attach(); self?.changed?() }
    }
    nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        let accessoryID = accessory.uniqueIdentifier.uuidString
        Task { @MainActor [weak self] in self?.emitState(accessoryID:accessoryID,characteristicID:nil) }
    }
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        let accessoryID = accessory.uniqueIdentifier.uuidString
        let characteristicID = characteristic.uniqueIdentifier.uuidString
        Task { @MainActor [weak self] in self?.emitState(accessoryID:accessoryID,characteristicID:characteristicID) }
    }
    func snapshot() throws -> HomeSnapshot {
        lastCaptureFailure = nil
        guard authorized else { lastCaptureFailure = "home_permission_missing"; throw ObserverError.invalidSnapshot }
        guard let h = home else {
            lastCaptureFailure = (selectedID?.isEmpty ?? true) ? "home_not_selected" : "selected_home_unavailable"
            throw ObserverError.invalidSnapshot
        }
        var gaps = [CoverageGap(objectID: h.uniqueIdentifier.uuidString, reason: "Pairing secrets, Apple-only automations, Home hubs, resident permissions, cameras/recording, favorites and application UI settings are not fully recoverable through public HomeKit APIs.")]
        let scenes: [SceneRecord] = h.actionSets.map { s in
            let actions: [SceneAction] = s.actions.compactMap { a in
                guard let a = a as? HMCharacteristicWriteAction<NSCopying & NSObjectProtocol>, let v = JSONValue.from(a.targetValue) else { return nil }
                return .init(characteristicID: a.characteristic.uniqueIdentifier.uuidString, value: v)
            }.sorted { $0.characteristicID < $1.characteristicID }
            let supported = actions.count == s.actions.count && s.actionSetType == HMActionSetTypeUserDefined
            if !supported { gaps.append(.init(objectID: s.uniqueIdentifier.uuidString, reason: "Built-in scene or unsupported action requires manual recovery")) }
            return .init(id: s.uniqueIdentifier.uuidString, name: s.name, type: s.actionSetType == HMActionSetTypeUserDefined ? "user" : s.actionSetType, actions: actions, restorable: supported)
        }
        var triggers: [AutomationRecord] = h.triggers.map { t in
            var a = AutomationRecord(id: t.uniqueIdentifier.uuidString, name: t.name, kind: "unsupported", enabled: t.isEnabled, sceneIDs: t.actionSets.map { $0.uniqueIdentifier.uuidString }.sorted(), restorable: false)
            if let timer = t as? HMTimerTrigger {
                // Read the deprecated field only to flag legacy timezone-bound timers for manual recovery.
                let legacyTimeZone = timer.timeZone?.identifier
                a.kind = "timer"; a.fireDate = timer.fireDate; a.timeZone = legacyTimeZone
                a.recurrence = timer.recurrence.map { [Self.components($0)] } ?? []
                a.restorable = legacyTimeZone == nil && timer.recurrence?.timeZone == nil && timer.recurrence?.calendar == nil
            } else if let event = t as? HMEventTrigger {
                a.kind = "event"; a.events = event.events.compactMap(Self.event); a.endEvents = event.endEvents.compactMap(Self.event); a.recurrence = event.recurrences?.map(Self.components) ?? []; a.executesOnce = event.executeOnce
                a.predicate = event.predicate.flatMap(Self.predicate)
                a.restorable = a.events.count == event.events.count && a.endEvents.count == event.endEvents.count && (event.predicate == nil || a.predicate != nil)
            }
            if !a.restorable { gaps.append(.init(objectID: a.id, reason: "Unsupported trigger/event/predicate requires manual recovery; exported supported fields may be incomplete")) }
            return a
        }
        let allRooms = h.rooms + (h.rooms.contains(where: { $0.uniqueIdentifier == h.roomForEntireHome().uniqueIdentifier }) ? [] : [h.roomForEntireHome()])
        let roomRecords: [NamedObject] = allRooms.map { .init(id:$0.uniqueIdentifier.uuidString,name:$0.name) }
        let zones: [NamedObject] = h.zones.map { .init(id:$0.uniqueIdentifier.uuidString,name:$0.name,members:$0.rooms.map { $0.uniqueIdentifier.uuidString }.sorted()) }
        let groups: [NamedObject] = h.serviceGroups.map { .init(id:$0.uniqueIdentifier.uuidString,name:$0.name,members:$0.services.map { $0.uniqueIdentifier.uuidString }.sorted()) }
        let accessories: [AccessoryRecord] = h.accessories.map(Self.accessory)
        let restorableSceneIDs = Set(scenes.filter(\.restorable).map(\.id))
        let characteristicIDs = Set(accessories.flatMap(\.services).flatMap(\.characteristics).map(\.id))
        for index in triggers.indices {
            if let issue = triggers[index].markNonRestorableIfReferencesAreMissing(restorableSceneIDs:restorableSceneIDs, characteristicIDs:characteristicIDs) {
                let reason = issue == .sceneNotRestorable ? "Automation references a scene that cannot be restored" : "Automation references a characteristic absent from the captured inventory"
                gaps.append(.init(objectID:triggers[index].id, reason:reason + "; preserved for manual recovery"))
            }
        }
        var result = HomeSnapshot(homeID:h.uniqueIdentifier.uuidString,name:h.name,rooms:roomRecords,zones:zones,accessories:accessories,groups:groups,scenes:scenes,automations:triggers,coverage:gaps)
        result.rooms.sort { $0.id < $1.id }; result.accessories.sort { $0.id < $1.id }; result.scenes.sort { $0.id < $1.id }; result.automations.sort { $0.id < $1.id }; result.coverage.sort { $0.objectID < $1.objectID }
        result.complete = accessories.allSatisfy { $0.services.contains { !$0.characteristics.isEmpty } }
        if let issue = result.validationIssue() {
            lastCaptureFailure = "snapshot_\(issue.rawValue)"
            throw ObserverError.invalidSnapshot
        }
        return result
    }
    static func accessory(_ a: HMAccessory) -> AccessoryRecord {
        // Keep the legacy archive field optional, but do not query HomeKit's deprecated serial-number characteristic.
        let bridges = (a.uniqueIdentifiersForBridgedAccessories ?? []).map(\.uuidString).sorted()
        let services: [ServiceRecord] = a.services.map { s in
            let characteristics: [CharacteristicRecord] = s.characteristics.map { c in .init(id:c.uniqueIdentifier.uuidString,type:c.characteristicType,readable:c.properties.contains(HMCharacteristicPropertyReadable),notifiable:c.properties.contains(HMCharacteristicPropertySupportsEventNotification)) }.sorted { $0.id < $1.id }
            return .init(id:s.uniqueIdentifier.uuidString,name:s.name,type:s.serviceType,characteristics:characteristics)
        }.sorted { $0.id < $1.id }
        return .init(id:a.uniqueIdentifier.uuidString,name:a.name,roomID:a.room?.uniqueIdentifier.uuidString,manufacturer:a.manufacturer,model:a.model,firmware:a.firmwareVersion,bridgeIDs:bridges,services:services)
    }
    static func components(_ d: DateComponents) -> [String: Int] {
        let pairs: [(String, Int?)] = [("era",d.era),("weekdayOrdinal",d.weekdayOrdinal),("weekOfMonth",d.weekOfMonth),("yearForWeekOfYear",d.yearForWeekOfYear),("quarter",d.quarter),("nanosecond",d.nanosecond),("isLeapMonth",d.isLeapMonth.map { $0 ? 1 : 0 }),("year",d.year),("month",d.month),("day",d.day),("hour",d.hour),("minute",d.minute),("second",d.second),("weekday",d.weekday),("weekOfYear",d.weekOfYear)]
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { k,v in v.map { (k,$0) } })
    }
    static func components(_ d: [String:Int], zone: String? = nil) -> DateComponents {
        var v = DateComponents(); v.era = d["era"]; v.weekdayOrdinal = d["weekdayOrdinal"]; v.weekOfMonth = d["weekOfMonth"]; v.yearForWeekOfYear = d["yearForWeekOfYear"]; v.quarter = d["quarter"]; v.nanosecond = d["nanosecond"]; v.isLeapMonth = d["isLeapMonth"].map { $0 == 1 }; v.year = d["year"]; v.month = d["month"]; v.day = d["day"]; v.hour = d["hour"]; v.minute = d["minute"]; v.second = d["second"]; v.weekday = d["weekday"]; v.weekOfYear = d["weekOfYear"]; v.timeZone = zone.flatMap(TimeZone.init(identifier:)); return v
    }
    static func event(_ event: HMEvent) -> EventRecord? {
        if let e = event as? HMCharacteristicEvent<NSCopying & NSObjectProtocol>, let value = JSONValue.from(e.triggerValue) { return .init(kind: "characteristic", characteristicID: e.characteristic.uniqueIdentifier.uuidString, value: value) }
        if let e = event as? HMCalendarEvent { guard e.fireDateComponents.calendar == nil else { return nil }; return .init(kind: "calendar", calendar: components(e.fireDateComponents), timeZone: e.fireDateComponents.timeZone?.identifier) }
        if let e = event as? HMSignificantTimeEvent { guard e.offset?.calendar == nil && e.offset?.timeZone == nil else { return nil }; return .init(kind: "significant", significantEvent: e.significantEvent.rawValue, offset: e.offset.map(components)) }
        return nil
    }
    static func predicate(_ p: NSPredicate) -> PredicateRecord? {
        if let p = p as? NSCompoundPredicate {
            let children = p.subpredicates.compactMap { ($0 as? NSPredicate).flatMap(Self.predicate) }
            guard children.count == p.subpredicates.count else { return nil }
            return .init(kind: ["not","and","or"][Int(p.compoundPredicateType.rawValue)], children: children)
        }
        // Never archive or evaluate arbitrary predicate format strings/functions.
        guard let p = p as? NSComparisonPredicate, p.leftExpression.expressionType == .keyPath, p.rightExpression.expressionType == .constantValue,
              [HMCharacteristicValueKeyPath].contains(p.leftExpression.keyPath), let value = JSONValue.from(p.rightExpression.constantValue), p.comparisonPredicateModifier == .direct, p.predicateOperatorType.rawValue <= 5 else { return nil }
        return .init(kind: "comparison", keyPath: p.leftExpression.keyPath, value: value, comparison: p.predicateOperatorType.rawValue, modifier: p.comparisonPredicateModifier.rawValue, options: p.options.rawValue)
    }
}
