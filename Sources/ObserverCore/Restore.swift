import Foundation

public struct RestoreOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case homeName, room, zone, accessoryName, accessoryRoom, serviceName, group, scene, automation }
    public var kind: Kind; public var savedID: String; public var currentID: String?; public var name: String?; public var payload: Data?
    public init(kind: Kind, savedID: String, currentID: String? = nil, name: String? = nil, payload: Data? = nil) { self.kind = kind; self.savedID = savedID; self.currentID = currentID; self.name = name; self.payload = payload }
}
public struct RestorePreview: Codable, Sendable {
    public var homeID: String; public var fingerprint: String; public var operations: [RestoreOperation]; public var unresolvedIDs: [String]; public var coverage: [CoverageGap]; public var mappings: [String: String]
    public func validate(current: HomeSnapshot) throws {
        try current.validate()
        guard current.homeID == homeID else { throw ObserverError.wrongHome }
        guard try current.fingerprint() == fingerprint else { throw ObserverError.stalePreview }
        guard unresolvedIDs.isEmpty else { throw ObserverError.invalidMapping }
    }
}
public enum RestorePlanner {
    public static func preview(saved: HomeSnapshot, current: HomeSnapshot, mappings: [String: String] = [:]) throws -> RestorePreview {
        try saved.validate(); try current.validate()
        guard saved.homeID == current.homeID else { throw ObserverError.wrongHome }
        let currentAccessories = Set(current.accessories.map(\.id))
        let savedServices = saved.accessories.flatMap(\.services); let currentServices = current.accessories.flatMap(\.services)
        let savedCharacteristics = savedServices.flatMap(\.characteristics); let currentCharacteristics = currentServices.flatMap(\.characteristics)
        let classes = [(Set(saved.accessories.map(\.id)),currentAccessories),(Set(savedServices.map(\.id)),Set(currentServices.map(\.id))),(Set(savedCharacteristics.map(\.id)),Set(currentCharacteristics.map(\.id)))]
        guard mappings.allSatisfy({ pair in classes.contains { $0.0.contains(pair.key) && $0.1.contains(pair.value) } }) else { throw ObserverError.invalidMapping }
        for (old,new) in classes {
            let effective = old.map { mappings[$0] ?? $0 }.filter(new.contains)
            guard Set(effective).count == effective.count else { throw ObserverError.invalidMapping }
        }
        var idMap = mappings; var unresolved: [String] = []; var operations: [RestoreOperation] = []; var coverage = saved.coverage
        func add<T: Encodable>(_ kind: RestoreOperation.Kind, id: String, currentID: String?, name: String?, payload: T) throws { operations.append(.init(kind: kind, savedID: id, currentID: currentID, name: name, payload: try Coding.encode(payload))) }
        if saved.name != current.name { operations.append(.init(kind: .homeName, savedID: saved.homeID, currentID: current.homeID, name: saved.name)) }
        for r in saved.rooms { if current.rooms.first(where: { $0.id == r.id }) != r { try add(.room, id: r.id, currentID: current.rooms.contains(where: { $0.id == r.id }) ? r.id : nil, name: r.name, payload: r) } }
        for a in saved.accessories {
            let id = idMap[a.id] ?? a.id
            guard let b = current.accessories.first(where: { $0.id == id }) else { unresolved.append(a.id); continue }
            // An explicit accessory mapping does not authorize guessing its services or characteristics.
            idMap[a.id] = id
            if a.name != b.name { operations.append(.init(kind: .accessoryName, savedID: a.id, currentID: id, name: a.name)) }
            if a.roomID != b.roomID { try add(.accessoryRoom, id: a.id, currentID: id, name: nil, payload: a.roomID) }
            for s in a.services {
                let serviceID = idMap[s.id] ?? s.id
                guard let t = b.services.first(where: { $0.id == serviceID }), t.type == s.type else { unresolved.append(s.id); continue }
                idMap[s.id] = serviceID
                for c in s.characteristics {
                    let charID = idMap[c.id] ?? c.id
                    guard let other = t.characteristics.first(where: { $0.id == charID }), other.type == c.type else { unresolved.append(c.id); continue }
                    idMap[c.id] = charID
                }
                if s.name != t.name { operations.append(.init(kind: .serviceName, savedID: s.id, currentID: t.id, name: s.name)) }
            }
        }
        for z in saved.zones { if current.zones.first(where: { $0.id == z.id }) != z { try add(.zone, id: z.id, currentID: current.zones.contains(where: { $0.id == z.id }) ? z.id : nil, name: z.name, payload: z) } }
        let services = Set(current.accessories.flatMap(\.services).map(\.id)); let characteristics = Set(current.accessories.flatMap(\.services).flatMap(\.characteristics).map(\.id))
        for original in saved.groups {
            var g = original; g.members = g.members.map { idMap[$0] ?? $0 }
            if current.groups.first(where: { $0.id == g.id }) == g { continue }
            if !Set(g.members).isSubset(of: services) { unresolved += g.members.filter { !services.contains($0) }; continue }
            try add(.group, id: g.id, currentID: current.groups.contains(where: { $0.id == g.id }) ? g.id : nil, name: g.name, payload: g)
        }
        for original in saved.scenes {
            var s = original; s.actions = s.actions.map { var a = $0; a.characteristicID = idMap[a.characteristicID] ?? a.characteristicID; return a }
            if current.scenes.first(where: { $0.id == s.id }) == s { continue }
            guard s.restorable, s.type == "user" else { coverage.append(.init(objectID: s.id, reason: "Scene requires manual recovery")); continue }
            if !s.actions.allSatisfy({ characteristics.contains($0.characteristicID) }) { unresolved += s.actions.filter { !characteristics.contains($0.characteristicID) }.map(\.characteristicID); continue }
            try add(.scene, id: s.id, currentID: current.scenes.contains(where: { $0.id == s.id }) ? s.id : nil, name: s.name, payload: s)
        }
        for original in saved.automations {
            var a = original
            a.events = a.events.map { var e = $0; e.characteristicID = e.characteristicID.map { idMap[$0] ?? $0 }; return e }
            a.endEvents = a.endEvents.map { var e = $0; e.characteristicID = e.characteristicID.map { idMap[$0] ?? $0 }; return e }
            if current.automations.first(where: { $0.id == a.id }) == a { continue }
            guard a.restorable else { coverage.append(.init(objectID: a.id, reason: "Automation requires manual recovery")); continue }
            let missing = (a.events + a.endEvents).compactMap(\.characteristicID).filter { !characteristics.contains($0) }
            if !missing.isEmpty { unresolved += missing; continue }
            var disabled = a; disabled.enabled = false
            try add(.automation, id: a.id, currentID: current.automations.contains(where: { $0.id == a.id }) ? a.id : nil, name: a.name, payload: disabled)
        }
        return .init(homeID: current.homeID, fingerprint: try current.fingerprint(), operations: operations, unresolvedIDs: Array(Set(unresolved)).sorted(), coverage: coverage, mappings: idMap)
    }
}
