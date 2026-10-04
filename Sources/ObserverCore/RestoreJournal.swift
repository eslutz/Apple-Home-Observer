import Foundation
import CryptoKit

public struct RestoreJournal: Codable, Sendable {
    public var schema = "apple-home-restore-journal/v1"
    public var id = UUID().uuidString
    public var date = Date()
    public var predecessorFile: String
    public var preview: RestorePreview
    public var completed: [Int] = []
    public var inFlight: Int?
    public var preparingTriggerID: String?
    public var disabledTriggerIDs: [String] = []
    public var created: [String:String] = [:]
    public var createdKinds: [String:String] = [:]
    public var removedCreatedIDs: [String] = []
    public var cleanupInFlightID: String?
    public var predecessorRestored = false
    public var predecessorMappings: [String:String] = [:]
    public var state = "prepared"
    public var recoveryOf: String?
    public init(predecessorFile:String,preview:RestorePreview) { self.predecessorFile = predecessorFile; self.preview = preview }
    private enum CodingKeys: String, CodingKey {
        case schema,id,date,predecessorFile,preview,completed,inFlight,preparingTriggerID,disabledTriggerIDs,created,createdKinds,removedCreatedIDs,cleanupInFlightID,predecessorRestored,predecessorMappings,state,recoveryOf
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        schema = try c.decodeIfPresent(String.self,forKey:.schema) ?? "apple-home-restore-journal/v1"
        id = try c.decode(String.self,forKey:.id); date = try c.decodeIfPresent(Date.self,forKey:.date) ?? Date()
        predecessorFile = try c.decode(String.self,forKey:.predecessorFile); preview = try c.decode(RestorePreview.self,forKey:.preview)
        completed = try c.decodeIfPresent([Int].self,forKey:.completed) ?? []; inFlight = try c.decodeIfPresent(Int.self,forKey:.inFlight)
        preparingTriggerID = try c.decodeIfPresent(String.self,forKey:.preparingTriggerID)
        disabledTriggerIDs = try c.decodeIfPresent([String].self,forKey:.disabledTriggerIDs) ?? []
        created = try c.decodeIfPresent([String:String].self,forKey:.created) ?? [:]
        createdKinds = try c.decodeIfPresent([String:String].self,forKey:.createdKinds) ?? [:]
        removedCreatedIDs = try c.decodeIfPresent([String].self,forKey:.removedCreatedIDs) ?? []
        cleanupInFlightID = try c.decodeIfPresent(String.self,forKey:.cleanupInFlightID)
        predecessorRestored = try c.decodeIfPresent(Bool.self,forKey:.predecessorRestored) ?? false
        predecessorMappings = try c.decodeIfPresent([String:String].self,forKey:.predecessorMappings) ?? [:]
        state = try c.decodeIfPresent(String.self,forKey:.state) ?? "prepared"
        recoveryOf = try c.decodeIfPresent(String.self,forKey:.recoveryOf)
    }
}
public final class JournalStore {
    public let root: URL
    private let key: SymmetricKey
    private let header = Data("AHOJ1".utf8)
    public init(root:URL,key:SymmetricKey) throws {
        self.root = root; self.key = key
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard (try root.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink == false else { throw ObserverError.unsafePath }
    }
    public func save(_ journal: RestoreJournal) throws {
        guard journal.schema == "apple-home-restore-journal/v1", UUID(uuidString:journal.id) != nil else { throw ObserverError.invalidArchive }
        let data = try Coding.encode(journal)
        guard data.count <= ArchiveCodec.maximumBytes - 64 else { throw ObserverError.invalidArchive }
        try PrivateFiles.write(header + AES.GCM.seal(data,using:key,authenticating:header).combined!,to:root.appendingPathComponent(journal.id + ".ahj"))
    }
    public func load(_ id:String) throws -> RestoreJournal {
        guard UUID(uuidString:id) != nil else { throw ObserverError.unsafePath }
        let data = try PrivateFiles.read(root.appendingPathComponent(id + ".ahj"),maximum:ArchiveCodec.maximumBytes)
        guard data.prefix(5) == header else { throw ObserverError.invalidArchive }
        let raw = try AES.GCM.open(AES.GCM.SealedBox(combined:data.dropFirst(5)),using:key,authenticating:header)
        let journal = try Coding.decode(RestoreJournal.self,raw)
        guard journal.schema == "apple-home-restore-journal/v1", journal.id == id else { throw ObserverError.invalidArchive }
        return journal
    }
    public func pending() throws -> [RestoreJournal] {
        let names = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "ahj" }
        guard names.count <= 10000 else { throw ObserverError.invalidArchive }
        return try names.map { try load($0.deletingPathExtension().lastPathComponent) }.filter { !["completed","reviewed_recovery","rolled_back"].contains($0.state) }.sorted { $0.date < $1.date }
    }
}

public enum RecoveryObjectKind: String, Codable, Sendable {
    case trigger, scene, group, zone, room
}

public struct RecoveryCleanupItem: Equatable, Sendable {
    public var savedID: String
    public var homeKitID: String
    public var kind: RecoveryObjectKind
}

public enum RecoveryCleanupPlanner {
    public static func verifyPredecessor(predecessor: HomeSnapshot, current: HomeSnapshot, mappings: [String:String]) throws {
        try predecessor.validate(); try current.validate()
        guard predecessor.homeID == current.homeID else { throw ObserverError.wrongHome }
        let audit = try RestorePlanner.preview(saved:predecessor,current:current,mappings:mappings)
        guard audit.unresolvedIDs.isEmpty, audit.operations.isEmpty else { throw ObserverError.stalePreview }
    }

    /// Return exact HomeKit identities in dependency order. Never infer IDs by name.
    public static func plan(for journal: RestoreJournal) throws -> [RecoveryCleanupItem] {
        var result: [RecoveryCleanupItem] = []
        var identifiers = Set<String>()
        let createdIDs = Set(journal.created.keys)
        let kindIDs = Set(journal.createdKinds.keys)
        let creationCandidates = Set(journal.preview.operations.compactMap { operation -> String? in
            guard cleanupKind(operation.kind) != nil, operation.currentID == nil else { return nil }
            return operation.savedID
        })
        guard createdIDs == kindIDs, createdIDs.isSubset(of:creationCandidates) else { throw ObserverError.invalidMapping }
        for operation in journal.preview.operations {
            guard let kind = cleanupKind(operation.kind) else { continue }
            if operation.currentID != nil { continue }
            guard let id = journal.created[operation.savedID], UUID(uuidString:id) != nil,
                  let rawKind = journal.createdKinds[operation.savedID],
                  let recordedKind = RecoveryObjectKind(rawValue:rawKind), recordedKind == kind else {
                throw ObserverError.invalidMapping
            }
            guard identifiers.insert(id).inserted else { throw ObserverError.invalidMapping }
            if !journal.removedCreatedIDs.contains(id) {
                result.append(.init(savedID:operation.savedID,homeKitID:id,kind:kind))
            }
        }
        let order: [RecoveryObjectKind:Int] = [.trigger:0,.scene:1,.group:2,.zone:3,.room:4]
        return result.sorted {
            let a = order[$0.kind,default:99], b = order[$1.kind,default:99]
            return a == b ? $0.savedID < $1.savedID : a < b
        }
    }

    private static func cleanupKind(_ kind: RestoreOperation.Kind) -> RecoveryObjectKind? {
        switch kind {
        case .automation: .trigger
        case .scene: .scene
        case .group: .group
        case .zone: .zone
        case .room: .room
        default: nil
        }
    }
}
