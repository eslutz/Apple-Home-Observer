import Foundation
import CryptoKit
import Darwin

public enum ArchiveCodec {
    private static let header = Data("AHO1".utf8)
    public static let maximumBytes = 32 * 1024 * 1024
    public static func seal(_ snapshot: HomeSnapshot, key: SymmetricKey) throws -> Data {
        try snapshot.validate()
        let data = try Coding.encode(snapshot)
        guard data.count < maximumBytes - 32 else { throw ObserverError.invalidArchive }
        return header + (try AES.GCM.seal(data, using: key, authenticating: header).combined!)
    }
    public static func open(_ data: Data, key: SymmetricKey) throws -> HomeSnapshot {
        guard data.count > 32, data.count <= maximumBytes, data.prefix(4) == header else { throw ObserverError.invalidArchive }
        let payload = try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(4)), using: key, authenticating: header)
        let snapshot = try Coding.decode(HomeSnapshot.self, payload); try snapshot.validate(); return snapshot
    }
}
public enum SnapshotReason: String, Codable, Sendable { case baseline, daily, change, predecessor, manual }
public struct SnapshotIndex: Codable, Sendable {
    public var file: String; public var date: Date; public var reason: SnapshotReason; public var digest: String
}
public final class SnapshotStore {
    public let root: URL
    private let key: SymmetricKey
    public init(root: URL, key: SymmetricKey) throws {
        self.root = root; self.key = key
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == false else { throw ObserverError.unsafePath }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    public func save(_ snapshot: HomeSnapshot, reason: SnapshotReason, protecting: Set<String> = []) throws -> SnapshotIndex {
        let encrypted = try ArchiveCodec.seal(snapshot, key: key)
        let item = SnapshotIndex(file: UUID().uuidString + ".aho", date: snapshot.capturedAt, reason: reason, digest: try snapshot.fingerprint())
        try PrivateFiles.write(encrypted, to: root.appendingPathComponent(item.file))
        var items = try index(); items.append(item)
        let allowed = protecting.union(Set(items.filter { $0.reason == .baseline }.map(\.file) + items.filter { $0.reason == .daily }.suffix(30).map(\.file) + items.filter { $0.reason != .baseline && $0.reason != .daily }.suffix(100).map(\.file)))
        // Commit the retained index before deleting expired archives. A failed write never removes a recovery point.
        try PrivateFiles.write(Coding.encode(items.filter { allowed.contains($0.file) }), to: root.appendingPathComponent("index.json"))
        try PrivateFiles.write(encrypted, to: root.appendingPathComponent("latest.aho"))
        for x in items where !allowed.contains(x.file) { try? FileManager.default.removeItem(at: root.appendingPathComponent(x.file)) }
        return item
    }
    public func index() throws -> [SnapshotIndex] {
        let path = root.appendingPathComponent("index.json")
        if !FileManager.default.fileExists(atPath: path.path) { return [] }
        let data = try PrivateFiles.read(path, maximum: 1024 * 1024)
        let items = try Coding.decode([SnapshotIndex].self, data)
        guard items.allSatisfy({ UUID(uuidString: String($0.file.dropLast(4))) != nil && $0.file.hasSuffix(".aho") }) else { throw ObserverError.unsafePath }
        return items
    }
    public func loadLatest() throws -> HomeSnapshot { try ArchiveCodec.open(PrivateFiles.read(root.appendingPathComponent("latest.aho"), maximum: ArchiveCodec.maximumBytes), key: key) }
    public func load(_ item: SnapshotIndex) throws -> HomeSnapshot {
        guard try index().contains(where: { $0.file == item.file }) else { throw ObserverError.unsafePath }
        return try ArchiveCodec.open(PrivateFiles.read(root.appendingPathComponent(item.file), maximum: ArchiveCodec.maximumBytes), key: key)
    }
}
public enum PrivateFiles {
    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ObserverError.unsafePath }
        defer { close(fd); unlink(temporary.path) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.write(contentsOf: data); try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else { throw ObserverError.unsafePath }
    }
    public static func read(_ url: URL, maximum: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ObserverError.unsafePath }; defer { close(fd) }
        var info = stat(); guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0, info.st_size <= maximum else { throw ObserverError.unsafePath }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let data = try handle.read(upToCount: maximum + 1), data.count <= maximum else { throw ObserverError.invalidArchive }; return data
    }
}
