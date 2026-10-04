import Foundation

public struct MetadataChange: Codable, Equatable, Sendable {
    public var kind: String; public var objectID: String; public var before: String?; public var after: String?
}
public enum SnapshotDiff {
    public static func compare(_ old: HomeSnapshot, _ new: HomeSnapshot) -> [MetadataChange] {
        var result: [MetadataChange] = []
        func objects<T: Encodable & Identifiable>(_ a: [T], _ b: [T], kind: String) where T.ID == String {
            let before = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
            let after = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
            for id in Set(before.keys).union(after.keys).sorted() {
                let x = before[id].flatMap { try? Coding.encode($0) }; let y = after[id].flatMap { try? Coding.encode($0) }
                if x != y { result.append(.init(kind: kind + (x == nil ? ".added" : y == nil ? ".removed" : ".changed"), objectID: id, before: nil, after: nil)) }
            }
        }
        let before = Dictionary(uniqueKeysWithValues: old.accessories.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: new.accessories.map { ($0.id, $0) })
        for id in Set(before.keys).union(after.keys).sorted() {
            guard let a = before[id], let b = after[id] else {
                result.append(.init(kind: "accessory." + (before[id] == nil ? "added" : "removed"), objectID: id, before: before[id]?.name, after: after[id]?.name)); continue
            }
            if a.name != b.name { result.append(.init(kind: "accessory.name", objectID: id, before: a.name, after: b.name)) }
            if a.roomID != b.roomID { result.append(.init(kind: "accessory.room", objectID: id, before: a.roomID, after: b.roomID)) }
            objects(a.services, b.services, kind: "service")
        }
        objects(old.rooms, new.rooms, kind: "room"); objects(old.zones, new.zones, kind: "zone")
        objects(old.groups, new.groups, kind: "group"); objects(old.scenes, new.scenes, kind: "scene"); objects(old.automations, new.automations, kind: "automation")
        if old.name != new.name { result.append(.init(kind: "home.name", objectID: new.homeID, before: old.name, after: new.name)) }
        return result
    }
}
public struct MovementWatchdog {
    struct Pending { var target: Double; var current: Double; var deadline: TimeInterval }
    private var pending: [String: Pending] = [:]
    public let travelSeconds: TimeInterval
    public init(travelSeconds: TimeInterval) { self.travelSeconds = max(1, travelSeconds) }
    public mutating func target(device: String, value: Double, current: Double, now: TimeInterval, travelSeconds: TimeInterval? = nil) {
        guard value.isFinite, current.isFinite, (0...100).contains(value), (0...100).contains(current) else { return }
        if abs(value - current) <= 5 { pending.removeValue(forKey: device) }
        else { pending[device] = Pending(target: value, current: current, deadline: now + min(600,max(1,travelSeconds ?? self.travelSeconds)) + 15) }
    }
    @discardableResult public mutating func position(device: String, value: Double) -> Bool {
        guard value.isFinite, var p = pending[device] else { return false }
        p.current = value
        if abs(p.current - p.target) <= 5 { pending.removeValue(forKey: device); return true }
        pending[device] = p
        return false
    }
    public mutating func expire(now: TimeInterval) -> [String] {
        let ids = pending.filter { $0.value.deadline <= now }.map(\.key).sorted()
        for id in ids { pending.removeValue(forKey: id) }; return ids
    }
}
public enum BackupSchedule {
    public static func dailyDue(now: Date, lastDaily: Date?) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.startOfDay(for: now)
        guard let today = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: start, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) else { return false }
        // Before today's scheduled time, catch up yesterday's missed run.
        let due = now >= today ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        return lastDaily == nil || lastDaily! < due
    }
}
