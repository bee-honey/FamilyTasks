import XCTest
@testable import FamilyTasks

final class SyncMergeTests: XCTestCase {
    private let base = Date().addingTimeInterval(-3_600)
    private var earlier: Date { base }
    private var later: Date { base.addingTimeInterval(120) }

    func testNewerEditWinsAndAdditionsFromBothDevicesAreKept() {
        let sharedID = UUID()
        let local = SharedHouseholdPayload(tasks: [
            FamilyTask(id: sharedID, title: "Local edit", updatedAt: later)
        ])
        let remote = SharedHouseholdPayload(tasks: [
            FamilyTask(id: sharedID, title: "Old title", updatedAt: earlier),
            FamilyTask(title: "Added on the other phone", updatedAt: earlier)
        ])

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote)

        XCTAssertEqual(Set(merged.tasks.map(\.title)), ["Local edit", "Added on the other phone"])
    }

    func testRemoteEditWinsWhenItIsNewer() {
        let id = UUID()
        let local = SharedHouseholdPayload(ideas: [IdeaNote(id: id, title: "Stale", updatedAt: earlier)])
        let remote = SharedHouseholdPayload(ideas: [IdeaNote(id: id, title: "Fresh", updatedAt: later)])

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote)

        XCTAssertEqual(merged.ideas.map(\.title), ["Fresh"])
    }

    func testDeletedItemIsNotResurrectedByAnOlderCopy() {
        let item = ShoppingItem(name: "Milk", shopID: UUID(), updatedAt: earlier)
        let local = SharedHouseholdPayload(deletions: [item.id.uuidString: later])
        let remote = SharedHouseholdPayload(shopping: ShoppingPayload(shops: [], items: [item]))

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote)

        XCTAssertTrue(merged.shopping.items.isEmpty)
        XCTAssertEqual(merged.deletions[item.id.uuidString], later)
    }

    func testItemEditedAfterItWasDeletedSurvives() {
        let task = FamilyTask(title: "Edited after delete", updatedAt: later)
        let local = SharedHouseholdPayload(deletions: [task.id.uuidString: earlier])
        let remote = SharedHouseholdPayload(tasks: [task])

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote)

        XCTAssertEqual(merged.tasks.map(\.id), [task.id])
    }

    func testDeletionsFromBothSidesAreCombined() {
        let local = SharedHouseholdPayload(deletions: ["a": earlier])
        let remote = SharedHouseholdPayload(deletions: ["a": later, "b": earlier])

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote)

        XCTAssertEqual(merged.deletions, ["a": later, "b": earlier])
    }

    func testShopOrderFollowsTheMostRecentReorder() {
        let costco = Shop(name: "Costco", updatedAt: earlier)
        let target = Shop(name: "Target", updatedAt: earlier)
        let local = SharedHouseholdPayload(shopping: ShoppingPayload(shops: [target, costco], items: [], orderUpdatedAt: later))
        let remote = SharedHouseholdPayload(shopping: ShoppingPayload(shops: [costco, target], items: [], orderUpdatedAt: earlier))

        XCTAssertEqual(SharedHouseholdPayload.merged(local: local, remote: remote).shopping.shops.map(\.name), ["Target", "Costco"])
        XCTAssertEqual(SharedHouseholdPayload.merged(local: remote, remote: local).shopping.shops.map(\.name), ["Target", "Costco"])
    }

    func testRemovedMemberStaysRemovedUntilReAdded() {
        let key = SyncLedger.memberKey("kid@example.com")
        let remote = SharedHouseholdPayload(familyMembers: ["kid@example.com", "parent@example.com"])

        let removed = SharedHouseholdPayload.merged(
            local: SharedHouseholdPayload(deletions: [key: earlier]),
            remote: remote
        )
        XCTAssertEqual(removed.familyMembers, ["parent@example.com"])

        let reAdded = SharedHouseholdPayload.merged(
            local: SharedHouseholdPayload(deletions: [key: earlier], memberAdditions: [key: later]),
            remote: remote
        )
        XCTAssertEqual(reAdded.familyMembers, ["kid@example.com", "parent@example.com"])
    }

    func testLedgerUnionKeepsLatestDateAndDropsExpiredEntries() {
        let expired = Date().addingTimeInterval(-200 * 86_400)
        let union = SyncLedger.union(["a": earlier, "old": expired], ["a": later])

        XCTAssertEqual(union, ["a": later])
    }

    func testPayloadWithoutLedgerFromOlderAppVersionsStillDecodes() throws {
        let task = FamilyTask(title: "From an older app")
        let encoded = try JSONEncoder().encode(SharedHouseholdPayload(tasks: [task]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "deletions")
        json.removeValue(forKey: "memberAdditions")
        json["schemaVersion"] = 1

        let decoded = try JSONDecoder().decode(SharedHouseholdPayload.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tasks.map(\.id), [task.id])
        XCTAssertTrue(decoded.deletions.isEmpty)
        XCTAssertTrue(decoded.memberAdditions.isEmpty)
    }
}
