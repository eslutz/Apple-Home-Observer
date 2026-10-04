import XCTest
@testable import ObserverCore

final class AutomationReferenceIssueTests: XCTestCase {
    func testMissingSceneDisablesRestoreAndReturnsSafeIssue() {
        var automation = AutomationRecord(id: "automation", name: "Automation", kind: "timer", sceneIDs: ["scene"])
        XCTAssertEqual(automation.markNonRestorableIfReferencesAreMissing(restorableSceneIDs: [], characteristicIDs: []), .sceneNotRestorable)
        XCTAssertFalse(automation.restorable)
    }

    func testMissingCharacteristicDisablesRestoreAndReturnsSafeIssue() {
        var automation = AutomationRecord(id: "automation", name: "Automation", kind: "event", events: [.init(kind: "characteristic", characteristicID: "characteristic")])
        XCTAssertEqual(automation.markNonRestorableIfReferencesAreMissing(restorableSceneIDs: [], characteristicIDs: []), .characteristicMissing)
        XCTAssertFalse(automation.restorable)
    }

    func testResolvedReferencesPreserveRestorability() {
        var automation = AutomationRecord(id: "automation", name: "Automation", kind: "timer", sceneIDs: ["scene"], events: [.init(kind: "characteristic", characteristicID: "characteristic")])
        XCTAssertNil(automation.markNonRestorableIfReferencesAreMissing(restorableSceneIDs: ["scene"], characteristicIDs: ["characteristic"]))
        XCTAssertTrue(automation.restorable)
    }
}
