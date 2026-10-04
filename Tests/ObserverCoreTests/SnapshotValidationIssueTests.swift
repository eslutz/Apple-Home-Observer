import XCTest
@testable import ObserverCore

final class SnapshotValidationIssueTests: XCTestCase {
    func snapshot() -> HomeSnapshot {
        HomeSnapshot(homeID: "home", name: "Home", rooms: [.init(id: "room", name: "Room")], accessories: [.init(id: "accessory", name: "Accessory", roomID: "room", services: [.init(id: "service", name: "Service", type: "light", characteristics: [.init(id: "characteristic", type: "power")])])])
    }

    func testValidSnapshotAndUnassignedRoomHaveNoIssue() {
        var value = snapshot()
        value.accessories[0].roomID = nil
        XCTAssertNil(value.validationIssue())
        XCTAssertNoThrow(try value.validate())
    }

    func testDuplicateIdentifiersHaveAStableIssueCode() {
        var value = snapshot()
        value.accessories.append(value.accessories[0])
        XCTAssertEqual(value.validationIssue(), .duplicateIdentifier)
        XCTAssertThrowsError(try value.validate())
    }

    func testDanglingRoomReferenceHasAStableIssueCode() {
        var value = snapshot()
        value.accessories[0].roomID = "missing-room"
        XCTAssertEqual(value.validationIssue(), .accessoryRoomReference)
        XCTAssertThrowsError(try value.validate())
    }

    func testIncompleteFlagHasAStableIssueCode() {
        var value = snapshot()
        value.complete = false
        XCTAssertEqual(value.validationIssue(), .markedIncomplete)
    }
    func testDanglingZoneRoomHasItsOwnIssueCode() {
        var value = snapshot()
        value.zones = [.init(id: "zone", name: "Zone", members: ["missing-room"])]
        XCTAssertEqual(value.validationIssue(), .zoneRoomReference)
    }

    func testDanglingServiceGroupMemberHasItsOwnIssueCode() {
        var value = snapshot()
        value.groups = [.init(id: "group", name: "Group", members: ["missing-service"])]
        XCTAssertEqual(value.validationIssue(), .serviceGroupReference)
    }

    func testDanglingSceneCharacteristicHasItsOwnIssueCode() {
        var value = snapshot()
        value.scenes = [.init(id: "scene", name: "Scene", actions: [.init(characteristicID: "missing-characteristic", value: .bool(true))])]
        XCTAssertEqual(value.validationIssue(), .sceneCharacteristicReference)
    }

    func testDanglingAutomationReferenceHasItsOwnIssueCode() {
        var value = snapshot()
        value.automations = [.init(id: "automation", name: "Automation", kind: "timer", sceneIDs: ["missing-scene"])]
        XCTAssertEqual(value.validationIssue(), .automationReference)
    }

}
