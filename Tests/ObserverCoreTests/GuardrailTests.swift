import XCTest
import CryptoKit
@testable import ObserverCore

final class GuardrailTests: XCTestCase {
    func fixture() -> HomeSnapshot { HomeSnapshot(homeID:"home",name:"Home",rooms:[.init(id:"r",name:"Room")],accessories:[.init(id:"a",name:"A",roomID:"r",services:[.init(id:"s",name:"Light",type:"light",characteristics:[.init(id:"c",type:"power")])])]) }
    func testMissingReferencesRejected() throws {
        var s = fixture(); s.accessories[0].roomID = "missing"; XCTAssertThrowsError(try s.validate())
        s = fixture(); s.scenes = [.init(id:"scene",name:"Scene",actions:[.init(characteristicID:"missing",value:.bool(true))])]; XCTAssertThrowsError(try s.validate())
    }
    func testCanonicalFingerprintIgnoresMembershipAndServiceOrdering() throws {
        var s = fixture(); s.rooms.append(.init(id:"r2",name:"Other")); s.zones = [.init(id:"z",name:"Zone",members:["r","r2"])]; s.accessories[0].services.append(.init(id:"s2",name:"Other",type:"other"))
        var shuffled = s; shuffled.zones[0].members.reverse(); shuffled.accessories[0].services.reverse()
        XCTAssertEqual(try s.fingerprint(),try shuffled.fingerprint())
    }
    func testMappingCannotAliasExistingAccessory() throws {
        let s = fixture(); var current = s; current.accessories.append(.init(id:"b",name:"B",roomID:"r"))
        var saved = s; saved.accessories.append(.init(id:"missing",name:"Missing",roomID:"r"))
        XCTAssertThrowsError(try RestorePlanner.preview(saved:saved,current:current,mappings:["missing":"a"]))
    }
    func testSymlinkReadRejectedWithoutExposingContents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
        let original = root.appendingPathComponent("original"); try PrivateFiles.write(Data("private".utf8),to:original)
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original)
        XCTAssertThrowsError(try PrivateFiles.read(link,maximum:100))
    }
    func testRestoreAutomationAlwaysDisabled() throws {
        var s = fixture(); s.automations = [.init(id:"t",name:"Timer",kind:"timer",enabled:true,fireDate:Date())]
        let preview = try RestorePlanner.preview(saved:s,current:fixture())
        XCTAssertEqual(preview.operations.count,1)
        XCTAssertFalse(try Coding.decode(AutomationRecord.self,preview.operations[0].payload!).enabled)
    }
    func testRetentionPreservesBaselineAndIndependentPools() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
        let store = try SnapshotStore(root:root,key:SymmetricKey(size:.bits256))
        _ = try store.save(fixture(),reason:.baseline)
        for _ in 0..<33 { _ = try store.save(fixture(),reason:.daily) }
        for _ in 0..<103 { _ = try store.save(fixture(),reason:.change) }
        let index = try store.index(); XCTAssertEqual(index.filter { $0.reason == .baseline }.count,1); XCTAssertEqual(index.filter { $0.reason == .daily }.count,30); XCTAssertEqual(index.filter { $0.reason == .change }.count,100)
        XCTAssertEqual(try store.loadLatest().homeID,"home")
    }
}

extension GuardrailTests {
    func testReplacementRequiresExplicitServiceAndCharacteristicIdentities() throws {
        let saved = fixture(); var current = saved
        current.accessories[0].id = "newA"; current.accessories[0].services[0].id = "newS"; current.accessories[0].services[0].characteristics[0].id = "newC"
        let accessoryOnly = try RestorePlanner.preview(saved:saved,current:current,mappings:["a":"newA"])
        XCTAssertEqual(accessoryOnly.unresolvedIDs,["s"])
        let all = try RestorePlanner.preview(saved:saved,current:current,mappings:["a":"newA","s":"newS","c":"newC"])
        XCTAssertTrue(all.unresolvedIDs.isEmpty)
        XCTAssertThrowsError(try RestorePlanner.preview(saved:saved,current:current,mappings:["c":"newS"]))
    }
}

extension GuardrailTests {
    func testOfflineToolAuthenticatesWithSeparatelyExportedRecoveryKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:root) }
        let key = SymmetricKey(size:.bits256)
        let archive = root.appendingPathComponent("fixture.aho");try PrivateFiles.write(ArchiveCodec.seal(fixture(),key:key),to:archive)
        let recovery = root.appendingPathComponent("fixture.recovery-key")
        let bytes: Data = key.withUnsafeBytes { Data($0) }
        try PrivateFiles.write(try RecoveryKeyCodec.encode(key),to:recovery)
        let repository = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            repository.appendingPathComponent(".build/out/Products/Debug/aho-verify"),
            repository.appendingPathComponent(".build/arm64-apple-macosx/debug/aho-verify"),
            repository.appendingPathComponent(".build/debug/aho-verify")
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath:$0.path) }) else {
            throw XCTSkip("Build the aho-verify product with swift run, then rerun to include its subprocess verification.")
        }
        let process = Process();process.executableURL = executable;process.arguments = ["--archive",archive.path,"--key-file",recovery.path]
        let output = Pipe();process.standardOutput = output;process.standardError = Pipe()
        try process.run();process.waitUntilExit();XCTAssertEqual(process.terminationStatus,0)
        let text = String(decoding:output.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        XCTAssertTrue(text.contains("Authenticated archive verified"));XCTAssertFalse(text.contains("Room"));XCTAssertFalse(text.contains(bytes.base64EncodedString()))
    }
}

extension GuardrailTests {
    func testPendingRecoveryPredecessorSurvivesRetention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let store = try SnapshotStore(root:root,key:SymmetricKey(size:.bits256));let predecessor = try store.save(fixture(),reason:.predecessor)
        for _ in 0..<102 { _ = try store.save(fixture(),reason:.change,protecting:[predecessor.file]) }
        XCTAssertEqual(try store.load(predecessor).homeID,"home")
    }
}
