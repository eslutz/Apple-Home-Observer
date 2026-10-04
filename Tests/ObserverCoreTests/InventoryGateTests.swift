import XCTest
@testable import ObserverCore
final class InventoryGateTests: XCTestCase {
    func snapshot() -> HomeSnapshot { HomeSnapshot(homeID:"home",name:"Home",rooms:[.init(id:"room",name:"Room")],accessories:[.init(id:"a",name:"A",roomID:"room",services:[.init(id:"s",name:"S",type:"light",characteristics:[.init(id:"c",type:"power")])])]) }
    func testInitialAndChangedGraphsRequireTwoMatchingObservations() {
        var gate = InventoryGate(); let initial = snapshot()
        XCTAssertEqual(gate.evaluate(initial,previous:nil),.waiting)
        XCTAssertEqual(gate.evaluate(initial,previous:nil),.ready)
        var changed = initial;changed.accessories[0].name = "Reset"
        XCTAssertEqual(gate.evaluate(changed,previous:initial),.waiting)
        XCTAssertEqual(gate.evaluate(changed,previous:initial),.ready)
    }
    func testStablePartialGraphCannotReplaceKnownGraphWithoutReview() {
        var initial = snapshot(); initial.accessories.append(.init(id:"b",name:"B",roomID:"room",services:[.init(id:"bs",name:"BS",type:"other",characteristics:[.init(id:"bc",type:"value")])]))
        var gate = InventoryGate(); let partial = snapshot()
        XCTAssertEqual(gate.evaluate(partial,previous:initial),.waiting)
        XCTAssertEqual(gate.evaluate(partial,previous:initial),.removalNeedsReview)
        XCTAssertEqual(gate.evaluate(partial,previous:initial,approveRemoval:true),.ready)
    }
    func testEmptyServicesRemainIncompleteButUnassignedRoomCanBeCaptured() {
        var gate = InventoryGate(); var incomplete = snapshot(); incomplete.accessories[0].services = []
        XCTAssertEqual(gate.evaluate(incomplete,previous:nil),.incomplete)
        var unassigned = snapshot(); unassigned.accessories[0].roomID = nil
        XCTAssertEqual(gate.evaluate(unassigned,previous:nil),.waiting)
        XCTAssertEqual(gate.evaluate(unassigned,previous:nil),.ready)
    }
}
