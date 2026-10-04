import Foundation
import CryptoKit

public enum ObserverError: Error { case invalidSnapshot, invalidArchive, stalePreview, wrongHome, invalidMapping, unsupported, unsafePath }

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): guard v.isFinite else { throw ObserverError.invalidSnapshot }; try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var foundation: Any {
        switch self {
        case .string(let x): return x
        case .number(let x): return NSNumber(value: x)
        case .bool(let x): return NSNumber(value: x)
        case .array(let x): return x.map(\.foundation)
        case .object(let x): return x.mapValues(\.foundation)
        case .null: return NSNull()
        }
    }
    public static func from(_ value: Any?) -> JSONValue? {
        guard let value else { return .null }
        if let x = value as? NSNumber {
            if CFGetTypeID(x) == CFBooleanGetTypeID() { return .bool(x.boolValue) }
            return x.doubleValue.isFinite ? .number(x.doubleValue) : nil
        }
        if let x = value as? String { return .string(x) }
        if let x = value as? [Any] { let v = x.compactMap(Self.from); return v.count == x.count ? .array(v) : nil }
        return nil
    }
}

public struct NamedObject: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var members: [String]
    public init(id: String, name: String, members: [String] = []) { self.id = id; self.name = name; self.members = members }
}
public struct CharacteristicRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var type: String; public var readable: Bool; public var notifiable: Bool
    public init(id: String, type: String, readable: Bool = false, notifiable: Bool = false) { self.id = id; self.type = type; self.readable = readable; self.notifiable = notifiable }
}
public struct ServiceRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var type: String; public var characteristics: [CharacteristicRecord]
    public init(id: String, name: String, type: String, characteristics: [CharacteristicRecord] = []) { self.id = id; self.name = name; self.type = type; self.characteristics = characteristics }
}
public struct AccessoryRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var roomID: String?
    public var manufacturer: String?; public var model: String?; public var serial: String?; public var firmware: String?; public var bridgeIDs: [String]; public var services: [ServiceRecord]
    public init(id: String, name: String, roomID: String? = nil, manufacturer: String? = nil, model: String? = nil, serial: String? = nil, firmware: String? = nil, bridgeIDs: [String] = [], services: [ServiceRecord] = []) {
        self.id = id; self.name = name; self.roomID = roomID; self.manufacturer = manufacturer; self.model = model; self.serial = serial; self.firmware = firmware; self.bridgeIDs = bridgeIDs; self.services = services
    }
}
public struct SceneAction: Codable, Equatable, Sendable {
    public var characteristicID: String; public var value: JSONValue
    public init(characteristicID: String, value: JSONValue) { self.characteristicID = characteristicID; self.value = value }
}
public struct SceneRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var type: String; public var actions: [SceneAction]; public var restorable: Bool
    public init(id: String, name: String, type: String = "user", actions: [SceneAction] = [], restorable: Bool = true) { self.id = id; self.name = name; self.type = type; self.actions = actions; self.restorable = restorable }
}
public struct EventRecord: Codable, Equatable, Sendable {
    public var kind: String; public var characteristicID: String?; public var value: JSONValue?; public var calendar: [String: Int]?; public var timeZone: String?; public var significantEvent: String?; public var offset: [String: Int]?
    public init(kind: String, characteristicID: String? = nil, value: JSONValue? = nil, calendar: [String: Int]? = nil, timeZone: String? = nil, significantEvent: String? = nil, offset: [String: Int]? = nil) { self.kind = kind; self.characteristicID = characteristicID; self.value = value; self.calendar = calendar; self.timeZone = timeZone; self.significantEvent = significantEvent; self.offset = offset }
}
public struct PredicateRecord: Codable, Equatable, Sendable {
    public var kind: String; public var children: [PredicateRecord]?; public var keyPath: String?; public var value: JSONValue?; public var comparison: UInt?; public var modifier: UInt?; public var options: UInt?
    public init(kind: String, children: [PredicateRecord]? = nil, keyPath: String? = nil, value: JSONValue? = nil, comparison: UInt? = nil, modifier: UInt? = nil, options: UInt? = nil) { self.kind = kind; self.children = children; self.keyPath = keyPath; self.value = value; self.comparison = comparison; self.modifier = modifier; self.options = options }
}
public struct AutomationRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var kind: String; public var enabled: Bool; public var sceneIDs: [String]; public var events: [EventRecord]; public var endEvents: [EventRecord]; public var predicate: PredicateRecord?; public var recurrence: [[String: Int]]; public var executesOnce: Bool; public var fireDate: Date?; public var timeZone: String?; public var restorable: Bool
    public init(id: String, name: String, kind: String, enabled: Bool = false, sceneIDs: [String] = [], events: [EventRecord] = [], endEvents: [EventRecord] = [], predicate: PredicateRecord? = nil, recurrence: [[String: Int]] = [], executesOnce: Bool = false, fireDate: Date? = nil, timeZone: String? = nil, restorable: Bool = true) { self.id = id; self.name = name; self.kind = kind; self.enabled = enabled; self.sceneIDs = sceneIDs; self.events = events; self.endEvents = endEvents; self.predicate = predicate; self.recurrence = recurrence; self.executesOnce = executesOnce; self.fireDate = fireDate; self.timeZone = timeZone; self.restorable = restorable }
}
public enum AutomationReferenceIssue: String, Equatable, Sendable {
    case sceneNotRestorable = "automation_scene_not_restorable"
    case characteristicMissing = "automation_characteristic_missing"
}
extension AutomationRecord {
    public mutating func markNonRestorableIfReferencesAreMissing(restorableSceneIDs: Set<String>, characteristicIDs: Set<String>) -> AutomationReferenceIssue? {
        guard restorable else { return nil }
        if !Set(sceneIDs).isSubset(of: restorableSceneIDs) {
            restorable = false
            return .sceneNotRestorable
        }
        if !(events + endEvents).allSatisfy({ $0.characteristicID == nil || characteristicIDs.contains($0.characteristicID!) }) {
            restorable = false
            return .characteristicMissing
        }
        return nil
    }
}
public struct CoverageGap: Codable, Equatable, Sendable {
    public var objectID: String; public var reason: String
    public init(objectID: String, reason: String) { self.objectID = objectID; self.reason = reason }
}
public enum SnapshotValidationIssue: String, Equatable, Sendable {
    case unsupportedSchema = "unsupported_schema"
    case markedIncomplete = "snapshot_incomplete"
    case missingHomeIdentifier = "missing_home_identifier"
    case noAccessories = "no_accessories"
    case tooManyAccessories = "too_many_accessories"
    case emptyIdentifier = "empty_identifier"
    case duplicateIdentifier = "duplicate_identifier"
    case accessoryRoomReference = "accessory_room_reference"
    case zoneRoomReference = "zone_room_reference"
    case serviceGroupReference = "service_group_reference"
    case sceneCharacteristicReference = "scene_characteristic_reference"
    case automationReference = "automation_reference"
    case tooManyRecords = "too_many_records"
}

public struct HomeSnapshot: Codable, Equatable, Sendable {
    public var schema = "apple-home-snapshot/v1"; public var capturedAt = Date(); public var homeID: String; public var name: String; public var complete: Bool
    public var rooms: [NamedObject]; public var zones: [NamedObject]; public var accessories: [AccessoryRecord]; public var groups: [NamedObject]; public var scenes: [SceneRecord]; public var automations: [AutomationRecord]; public var coverage: [CoverageGap]
    public init(homeID: String, name: String, complete: Bool = true, rooms: [NamedObject] = [], zones: [NamedObject] = [], accessories: [AccessoryRecord] = [], groups: [NamedObject] = [], scenes: [SceneRecord] = [], automations: [AutomationRecord] = [], coverage: [CoverageGap] = []) { self.homeID = homeID; self.name = name; self.complete = complete; self.rooms = rooms; self.zones = zones; self.accessories = accessories; self.groups = groups; self.scenes = scenes; self.automations = automations; self.coverage = coverage }
    public func validationIssue() -> SnapshotValidationIssue? {
        guard schema == "apple-home-snapshot/v1" else { return .unsupportedSchema }
        guard complete else { return .markedIncomplete }
        guard !homeID.isEmpty else { return .missingHomeIdentifier }
        guard !accessories.isEmpty else { return .noAccessories }
        guard accessories.count <= 4096 else { return .tooManyAccessories }
        let lists = [rooms.map(\.id), zones.map(\.id), accessories.map(\.id), groups.map(\.id), scenes.map(\.id), automations.map(\.id), accessories.flatMap(\.services).map(\.id), accessories.flatMap(\.services).flatMap(\.characteristics).map(\.id)]
        for ids in lists {
            if ids.contains(where: \.isEmpty) { return .emptyIdentifier }
            if Set(ids).count != ids.count { return .duplicateIdentifier }
        }
        let roomIDs = Set(rooms.map(\.id)); let serviceIDs = Set(accessories.flatMap(\.services).map(\.id)); let charIDs = Set(accessories.flatMap(\.services).flatMap(\.characteristics).map(\.id)); let sceneIDs = Set(scenes.map(\.id))
        if !accessories.allSatisfy({ $0.roomID == nil || roomIDs.contains($0.roomID!) }) { return .accessoryRoomReference }
        if !zones.allSatisfy({ Set($0.members).isSubset(of:roomIDs) }) { return .zoneRoomReference }
        if !groups.allSatisfy({ Set($0.members).isSubset(of:serviceIDs) }) { return .serviceGroupReference }
        if !scenes.allSatisfy({ !$0.restorable || $0.actions.allSatisfy { charIDs.contains($0.characteristicID) } }) { return .sceneCharacteristicReference }
        if !automations.allSatisfy({ !$0.restorable || (Set($0.sceneIDs).isSubset(of:sceneIDs) && ($0.events + $0.endEvents).allSatisfy { $0.characteristicID == nil || charIDs.contains($0.characteristicID!) }) }) { return .automationReference }
        if lists.contains(where: { $0.count > 32768 }) { return .tooManyRecords }
        return nil
    }
    public func validate() throws {
        guard validationIssue() == nil else { throw ObserverError.invalidSnapshot }
    }
    public func fingerprint() throws -> String {
        var v = self; v.capturedAt = Date(timeIntervalSince1970: 0)
        v.rooms = v.rooms.sorted { $0.id < $1.id }
        v.zones = v.zones.map { var x = $0; x.members.sort(); return x }.sorted { $0.id < $1.id }
        v.groups = v.groups.map { var x = $0; x.members.sort(); return x }.sorted { $0.id < $1.id }
        v.accessories = v.accessories.map { var x = $0; x.bridgeIDs.sort(); x.services = x.services.map { var y = $0; y.characteristics.sort { $0.id < $1.id }; return y }.sorted { $0.id < $1.id }; return x }.sorted { $0.id < $1.id }
        v.scenes = v.scenes.map { var x = $0; x.actions.sort { $0.characteristicID < $1.characteristicID }; return x }.sorted { $0.id < $1.id }
        v.automations = v.automations.map { var x = $0; x.sceneIDs.sort(); return x }.sorted { $0.id < $1.id }
        v.coverage.sort { ($0.objectID,$0.reason) < ($1.objectID,$1.reason) }
        return SHA256.hash(data: try Coding.encode(v)).map { String(format: "%02x", $0) }.joined()
    }
}
public enum Coding {
    public static func encode<T: Encodable>(_ v: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .millisecondsSince1970; return try e.encode(v) }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { let e = JSONDecoder(); e.dateDecodingStrategy = .millisecondsSince1970; return try e.decode(t, from: d) }
}

public enum RecoveryKeyCodec {
    private static let header = "AHO-RECOVERY-v1"
    private static let maximumBytes = 128

    public static func encode(_ key: SymmetricKey) throws -> Data {
        let raw = key.withUnsafeBytes { Data($0) }
        guard raw.count == 32 else { throw ObserverError.invalidArchive }
        return Data((header + "\n" + raw.base64EncodedString() + "\n").utf8)
    }

    public static func decode(_ data: Data) throws -> SymmetricKey {
        guard data.count <= maximumBytes,
              let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\n") else { throw ObserverError.invalidArchive }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 3,
              lines[0] == header,
              !lines[1].isEmpty,
              lines[2].isEmpty,
              let raw = Data(base64Encoded: String(lines[1]), options: []),
              raw.count == 32 else { throw ObserverError.invalidArchive }
        return SymmetricKey(data: raw)
    }
}
