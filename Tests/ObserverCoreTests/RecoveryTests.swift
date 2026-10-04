import XCTest
import CryptoKit
@testable import ObserverCore

final class RecoveryTests: XCTestCase {
    func fixture() -> HomeSnapshot {
        HomeSnapshot(homeID: "home", name: "Test", rooms: [.init(id: "room", name: "Office")], accessories: [.init(id: "lamp", name: "Lamp", roomID: "room", manufacturer: "Fixture", model: "1", serial: "123", services: [])])
    }
    func testEncryptedRoundTripAndTamperRejection() throws {
        let key = SymmetricKey(size: .bits256)
        let data = try ArchiveCodec.seal(fixture(), key: key)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Office"))
        XCTAssertEqual(try ArchiveCodec.open(data, key: key).homeID, "home")
        XCTAssertThrowsError(try ArchiveCodec.open(data, key: SymmetricKey(size: .bits256)))
        var corrupt = data; corrupt[corrupt.count - 1] ^= 1
        XCTAssertThrowsError(try ArchiveCodec.open(corrupt, key: key))
    }
    func testRestorePreviewRejectsDifferentHomeAndStaleGraph() throws {
        let original = fixture()
        var changed = original; changed.accessories[0].name = "Default name"
        let preview = try RestorePlanner.preview(saved: original, current: changed)
        XCTAssertEqual(preview.operations.count, 1)
        XCTAssertEqual(preview.operations[0].kind, .accessoryName)
        XCTAssertNoThrow(try preview.validate(current: changed))
        XCTAssertThrowsError(try preview.validate(current: original))
        var other = changed; other.homeID = "another"
        XCTAssertThrowsError(try RestorePlanner.preview(saved: original, current: other))
    }
    func testReplacedAccessoryRequiresExplicitMapping() throws {
        let saved = fixture(); var current = saved; current.accessories[0].id = "replacement"
        let unmapped = try RestorePlanner.preview(saved: saved, current: current)
        XCTAssertEqual(unmapped.unresolvedIDs, ["lamp"])
        let mapped = try RestorePlanner.preview(saved: saved, current: current, mappings: ["lamp": "replacement"])
        XCTAssertTrue(mapped.unresolvedIDs.isEmpty)
        XCTAssertThrowsError(try RestorePlanner.preview(saved: saved, current: current, mappings: ["lamp": "missing"]))
    }
    func testIncompleteInventoryDoesNotReplaceLastBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root, key: SymmetricKey(size: .bits256))
        _ = try store.save(fixture(), reason: .baseline)
        var incomplete = fixture(); incomplete.complete = false
        XCTAssertThrowsError(try store.save(incomplete, reason: .daily))
        XCTAssertEqual(try store.loadLatest().name, "Test")
    }
    func testDiffSeparatesMetadataFromDeviceState() throws {
        var changed = fixture(); changed.accessories[0].name = "Reset"
        let events = SnapshotDiff.compare(fixture(), changed)
        XCTAssertEqual(events.map(\.kind), ["accessory.name"])
        XCTAssertEqual(events.first?.before, "Lamp")
    }
    func testWatchdogIgnoresIdleAndSupersededCommands() {
        var w = MovementWatchdog(travelSeconds: 20)
        XCTAssertTrue(w.expire(now: 100).isEmpty)
        w.target(device: "blind", value: 75, current: 25, now: 0)
        w.target(device: "blind", value: 50, current: 25, now: 10)
        XCTAssertTrue(w.expire(now: 36).isEmpty)
        XCTAssertEqual(w.expire(now: 46), ["blind"])
        w.target(device: "blind", value: 75, current: 25, now: 50)
        XCTAssertFalse(w.position(device: "blind", value: 50))
        XCTAssertTrue(w.position(device: "blind", value: 72))
        XCTAssertFalse(w.position(device: "blind", value: 75))
        XCTAssertTrue(w.expire(now: 100).isEmpty)
    }

    func testRecoveryKeyCodecRoundTripsAndRejectsMalformedFiles() throws {
        let key = SymmetricKey(size: .bits256)
        let encoded = try RecoveryKeyCodec.encode(key)
        let decoded = try RecoveryKeyCodec.decode(encoded)
        XCTAssertEqual(Data(key.withUnsafeBytes { Data($0) }), Data(decoded.withUnsafeBytes { Data($0) }))
        XCTAssertThrowsError(try RecoveryKeyCodec.decode(Data("wrong-header\n\(String(repeating: "A", count: 44))\n".utf8)))
        XCTAssertThrowsError(try RecoveryKeyCodec.decode(Data("AHO-RECOVERY-v1\nAA==\n".utf8)))
        XCTAssertThrowsError(try RecoveryKeyCodec.decode(Data(repeating: 0x41, count: 129)))
        XCTAssertThrowsError(try RecoveryKeyCodec.encode(SymmetricKey(size: .bits128)))
    }
    func testDailySchedulingAcrossMissedRunAndDST() {
        let date = ISO8601DateFormatter().date(from: "2026-11-01T08:00:00Z")!
        XCTAssertTrue(BackupSchedule.dailyDue(now: date, lastDaily: nil))
        XCTAssertFalse(BackupSchedule.dailyDue(now: date, lastDaily: date))
    }
}
