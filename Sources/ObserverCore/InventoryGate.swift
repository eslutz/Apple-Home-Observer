import Foundation

public struct InventoryGate {
    public enum Decision: Equatable { case ready, waiting, incomplete, removalNeedsReview }
    private var candidateFingerprint: String?
    public init() {}
    public mutating func evaluate(_ snapshot: HomeSnapshot, previous: HomeSnapshot?, approveRemoval: Bool = false) -> Decision {
        guard (try? snapshot.validate()) != nil,
              snapshot.accessories.allSatisfy({ $0.services.contains { !$0.characteristics.isEmpty } }),
              let fingerprint = try? snapshot.fingerprint() else { candidateFingerprint = nil; return .incomplete }
        guard candidateFingerprint == fingerprint else { candidateFingerprint = fingerprint; return .waiting }
        if let previous, (try? previous.fingerprint()) == fingerprint { return .ready }
        if let previous, !approveRemoval, !Self.ids(previous).isSubset(of:Self.ids(snapshot)) { return .removalNeedsReview }
        return .ready
    }
    private static func ids(_ s: HomeSnapshot) -> Set<String> {
        Set(s.accessories.map(\.id) + s.accessories.flatMap(\.services).map(\.id) + s.accessories.flatMap(\.services).flatMap(\.characteristics).map(\.id) + s.rooms.map(\.id) + s.zones.map(\.id) + s.groups.map(\.id) + s.scenes.map(\.id) + s.automations.map(\.id))
    }
}
