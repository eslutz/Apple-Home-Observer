import XCTest
@testable import ObserverCore

final class RecoveryCleanupTests: XCTestCase {
    func testLegacyJournalDecodesBeforeCleanupFieldsExisted() throws {
        let json = #"{"schema":"apple-home-restore-journal/v1","id":"11111111-1111-4111-8111-111111111111","predecessorFile":"before.aho","preview":{"homeID":"home","fingerprint":"fingerprint","operations":[],"unresolvedIDs":[],"coverage":[],"mappings":{}},"completed":[],"disabledTriggerIDs":[],"created":{},"state":"partial_failure"}"#
        let journal = try JSONDecoder().decode(RestoreJournal.self,from:Data(json.utf8))
        XCTAssertEqual(journal.state,"partial_failure")
        XCTAssertTrue(journal.createdKinds.isEmpty)
        XCTAssertFalse(journal.predecessorRestored)
    }

    func testCleanupOrderAndRestartResumption() throws {
        let operations: [(RestoreOperation.Kind,String)] = [(.room,"room"),(.scene,"scene"),(.zone,"zone"),(.group,"group"),(.automation,"trigger")]
        let preview = RestorePreview(homeID:"home",fingerprint:"fingerprint",operations:operations.map { .init(kind:$0.0,savedID:$0.1) },unresolvedIDs:[],coverage:[],mappings:[:])
        var journal = RestoreJournal(predecessorFile:"predecessor",preview:preview)
        journal.created = Dictionary(uniqueKeysWithValues:operations.map { ($0.1,UUID().uuidString) })
        journal.createdKinds = ["room":"room","scene":"scene","zone":"zone","group":"group","trigger":"trigger"]
        let plan = try RecoveryCleanupPlanner.plan(for:journal)
        XCTAssertEqual(plan.map(\.kind),[.trigger,.scene,.group,.zone,.room])
        journal.cleanupInFlightID = plan[0].homeKitID
        let restarted = try JSONDecoder().decode(RestoreJournal.self,from:JSONEncoder().encode(journal))
        XCTAssertEqual(try RecoveryCleanupPlanner.plan(for:restarted),plan)
        journal.removedCreatedIDs.append(plan[0].homeKitID)
        XCTAssertEqual(try RecoveryCleanupPlanner.plan(for:journal).map(\.kind),[.scene,.group,.zone,.room])
    }


    func testCleanupSkipsExistingObjectsButRequiresIDsForNewObjects() throws {
        let preview = RestorePreview(homeID:"home",fingerprint:"fingerprint",operations:[
            .init(kind:.room,savedID:"existing-room",currentID:"same-room-id"),
            .init(kind:.scene,savedID:"new-scene")
        ],unresolvedIDs:[],coverage:[],mappings:[:])
        var journal = RestoreJournal(predecessorFile:"predecessor",preview:preview)
        journal.created["new-scene"] = UUID().uuidString
        journal.createdKinds["new-scene"] = "scene"
        XCTAssertEqual(try RecoveryCleanupPlanner.plan(for:journal).map(\.kind),[.scene])
        journal.created.removeValue(forKey:"new-scene")
        journal.createdKinds.removeValue(forKey:"new-scene")
        XCTAssertThrowsError(try RecoveryCleanupPlanner.plan(for:journal))
    }

    func testCleanupRequiresHomeToMatchTheRestoredPredecessor() throws {
        let home = HomeSnapshot(homeID:"home",name:"Home",rooms:[.init(id:"room",name:"Room")],accessories:[.init(id:"accessory",name:"Blind",roomID:"room",services:[.init(id:"service",name:"Window",type:"window",characteristics:[.init(id:"characteristic",type:"position")])])])
        XCTAssertNoThrow(try RecoveryCleanupPlanner.verifyPredecessor(predecessor:home,current:home,mappings:[:]))
        var changed = home; changed.name = "Changed"
        XCTAssertThrowsError(try RecoveryCleanupPlanner.verifyPredecessor(predecessor:home,current:changed,mappings:[:]))
        var otherHome = home; otherHome.homeID = "other"
        XCTAssertThrowsError(try RecoveryCleanupPlanner.verifyPredecessor(predecessor:home,current:otherHome,mappings:[:]))
    }

    func testCleanupAcceptsOnlyExplicitReplacementMappings() throws {
        let predecessor = HomeSnapshot(homeID:"home",name:"Home",rooms:[.init(id:"room",name:"Room")],accessories:[.init(id:"old",name:"Blind",roomID:"room",services:[.init(id:"old-service",name:"Window",type:"window",characteristics:[.init(id:"old-char",type:"position")])])])
        var current = predecessor; current.accessories[0].id = "new"; current.accessories[0].services[0].id = "new-service"; current.accessories[0].services[0].characteristics[0].id = "new-char"
        XCTAssertThrowsError(try RecoveryCleanupPlanner.verifyPredecessor(predecessor:predecessor,current:current,mappings:[:]))
        XCTAssertNoThrow(try RecoveryCleanupPlanner.verifyPredecessor(predecessor:predecessor,current:current,mappings:["old":"new","old-service":"new-service","old-char":"new-char"]))
    }

    func testCleanupRejectsUnjournaledOrAliasedIDs() throws {
        let preview = RestorePreview(homeID:"home",fingerprint:"fingerprint",operations:[.init(kind:.scene,savedID:"scene"),.init(kind:.room,savedID:"room")],unresolvedIDs:[],coverage:[],mappings:[:])
        var journal = RestoreJournal(predecessorFile:"predecessor",preview:preview)
        journal.created["scene"] = UUID().uuidString; journal.createdKinds["scene"] = "scene"
        XCTAssertThrowsError(try RecoveryCleanupPlanner.plan(for:journal))
        journal.created["room"] = journal.created["scene"]; journal.createdKinds["room"] = "room"
        XCTAssertThrowsError(try RecoveryCleanupPlanner.plan(for:journal))
    }
}
