import XCTest
import CryptoKit
@testable import ObserverCore
final class JournalTests: XCTestCase {
    func testRestartRetainsUnfinishedJournalsAndSeparateHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
        let key = SymmetricKey(size:.bits256); let store = try JournalStore(root:root,key:key)
        let preview = RestorePreview(homeID:"home",fingerprint:"fingerprint",operations:[],unresolvedIDs:[],coverage:[],mappings:[:])
        var first = RestoreJournal(predecessorFile:"predecessor",preview:preview)
        first.preparingTriggerID = "trigger"; first.state = "applying"; try store.save(first)
        let second = RestoreJournal(predecessorFile:"another",preview:preview);try store.save(second)
        let restarted = try JournalStore(root:root,key:key)
        XCTAssertEqual(try restarted.pending().count,2)
        XCTAssertEqual(try restarted.load(first.id).preparingTriggerID,"trigger")
        first.state = "completed";try restarted.save(first)
        XCTAssertEqual(try restarted.pending().map(\.id),[second.id])
        XCTAssertThrowsError(try JournalStore(root:root,key:SymmetricKey(size:.bits256)).load(first.id))
    }
}
