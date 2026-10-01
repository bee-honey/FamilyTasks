import XCTest
@testable import FamilyTasks

final class HouseholdRecordsTests: XCTestCase {
    private let base = Date().addingTimeInterval(-3_600)
    private var earlier: Date { base }
    private var later: Date { base.addingTimeInterval(120) }

    func testEveryKindOfItemSurvivesARoundTripThroughRecords() {
        let shop = Shop(name: "Grocer", updatedAt: earlier)
        let payload = SharedHouseholdPayload(
            tasks: [FamilyTask(title: "Take out bins", updatedAt: earlier)],
            familyMembers: ["a@example.com", "b@example.com"],
            profiles: [SharedMemberProfile(email: "a@example.com", initials: "A", imageData: nil, updatedAt: earlier)],
            shopping: ShoppingPayload(shops: [shop], items: [ShoppingItem(name: "Milk", shopID: shop.id, updatedAt: earlier)], orderUpdatedAt: earlier),
            recurringTasks: [RecurringTask(title: "Pay gardener", frequency: .monthly, nextDueDate: earlier)],
            mealPlan: MealPlanPayload(mealIdeas: [MealIdea(name: "Curry")], plannedMeals: []),
            ideas: [IdeaNote(title: "Paint fence", updatedAt: earlier)],
            healthSnapshots: [HealthSnapshot(memberEmail: "a@example.com", memberInitials: "A", date: earlier, dayID: "d1", steps: 100, sleepSeconds: 0, updatedAt: earlier)],
            deletions: ["gone": earlier],
            memberAdditions: [SyncLedger.memberKey("b@example.com"): earlier]
        )

        let records = HouseholdRecords.records(from: payload, updatedBy: "a@example.com")
        let restored = HouseholdRecords.payload(from: Array(records.values))

        XCTAssertEqual(restored.tasks.map(\.title), ["Take out bins"])
        XCTAssertEqual(restored.familyMembers, ["a@example.com", "b@example.com"])
        XCTAssertEqual(restored.memberAdditions, payload.memberAdditions)
        XCTAssertEqual(restored.profiles.map(\.email), ["a@example.com"])
        XCTAssertEqual(restored.shopping.shops.map(\.id), [shop.id])
        XCTAssertEqual(restored.shopping.items.map(\.name), ["Milk"])
        XCTAssertEqual(restored.shopping.orderUpdatedAt, earlier)
        XCTAssertEqual(restored.recurringTasks.map(\.title), ["Pay gardener"])
        XCTAssertEqual(restored.mealPlan.mealIdeas.map(\.name), ["Curry"])
        XCTAssertEqual(restored.ideas.map(\.title), ["Paint fence"])
        XCTAssertEqual(restored.healthSnapshots.map(\.steps), [100])
        XCTAssertEqual(restored.deletions, ["gone": earlier])
    }

    func testHealthIsOneRecordPerMember() {
        let snapshots = (1...30).map { day in
            HealthSnapshot(memberEmail: "a@example.com", memberInitials: "A", date: earlier.addingTimeInterval(Double(day) * 86_400), dayID: "d\(day)", steps: 1, sleepSeconds: 0)
        } + [HealthSnapshot(memberEmail: "b@example.com", memberInitials: "B", date: earlier, dayID: "d1", steps: 1, sleepSeconds: 0)]

        let records = HouseholdRecords.records(from: SharedHouseholdPayload(healthSnapshots: snapshots), updatedBy: "")

        XCTAssertEqual(records.values.filter { $0.kind == .health }.map(\.name).sorted(), ["health:a@example.com", "health:b@example.com"])
    }

    func testShopOrderComesFromTheHouseholdRecordNotRecordOrder() {
        let first = Shop(name: "First")
        let second = Shop(name: "Second")
        let payload = SharedHouseholdPayload(shopping: ShoppingPayload(shops: [first, second], items: [], orderUpdatedAt: later))
        let records = HouseholdRecords.records(from: payload, updatedBy: "")

        let reversed = [records[second.id.uuidString]!, records[first.id.uuidString]!, records[HouseholdRecords.householdRecordName]!]

        XCTAssertEqual(HouseholdRecords.payload(from: reversed).shopping.shops.map(\.name), ["First", "Second"])
    }

    func testDeletionReplacesTheItemUnlessTheItemWasEditedLater() {
        let deleted = FamilyTask(title: "Deleted", updatedAt: earlier)
        let editedAfterDelete = FamilyTask(title: "Edited after delete", updatedAt: later)
        let payload = SharedHouseholdPayload(
            tasks: [deleted, editedAfterDelete],
            deletions: [deleted.id.uuidString: later, editedAfterDelete.id.uuidString: earlier]
        )

        let records = HouseholdRecords.records(from: payload, updatedBy: "")

        XCTAssertEqual(records[deleted.id.uuidString]?.kind, .deleted)
        XCTAssertEqual(records[editedAfterDelete.id.uuidString]?.kind, .task)
    }

    func testRemovedMemberBecomesADeletionAndReAddedMemberIsLive() {
        let removed = SyncLedger.memberKey("old@example.com")
        let readded = SyncLedger.memberKey("back@example.com")
        let payload = SharedHouseholdPayload(
            familyMembers: ["back@example.com"],
            deletions: [removed: earlier, readded: earlier],
            memberAdditions: [readded: later]
        )

        let records = HouseholdRecords.records(from: payload, updatedBy: "")

        XCTAssertEqual(records[removed]?.kind, .deleted)
        XCTAssertEqual(records[readded]?.kind, .member)
    }

    func testOnlyNewOrNewerRecordsAreUploaded() {
        func record(_ name: String, _ date: Date, _ kind: SyncRecord.Kind = .task) -> SyncRecord {
            SyncRecord(name: name, kind: kind, payload: nil, updatedAt: date, updatedBy: "")
        }
        let desired = [
            "new": record("new", earlier),
            "newer": record("newer", later),
            "same": record("same", earlier),
            "older": record("older", earlier),
            "deletedAtEditTime": record("deletedAtEditTime", earlier, .deleted)
        ]
        let current = [
            "newer": record("newer", earlier),
            "same": record("same", earlier),
            "older": record("older", later),
            "deletedAtEditTime": record("deletedAtEditTime", earlier)
        ]

        let changes = HouseholdRecords.changes(desired: desired, current: current)

        XCTAssertEqual(changes.map(\.name), ["deletedAtEditTime", "new", "newer"])
    }

    func testUnchangedHouseholdNeedsNoUpload() {
        let payload = SharedHouseholdPayload(
            tasks: [FamilyTask(title: "Task", updatedAt: earlier)],
            familyMembers: ["a@example.com"],
            shopping: ShoppingPayload(shops: [Shop(name: "Shop")], items: []),
            deletions: ["gone": earlier]
        )
        let uploaded = HouseholdRecords.records(from: payload, updatedBy: "a@example.com")

        let roundTripped = HouseholdRecords.records(from: HouseholdRecords.payload(from: Array(uploaded.values)), updatedBy: "b@example.com")

        XCTAssertTrue(HouseholdRecords.changes(desired: roundTripped, current: uploaded).isEmpty)
    }

    func testOnlyOldDeletionsExpire() {
        let now = Date()
        let records = [
            SyncRecord(name: "old", kind: .deleted, payload: nil, updatedAt: now.addingTimeInterval(-SyncLedger.retention - 60), updatedBy: ""),
            SyncRecord(name: "recent", kind: .deleted, payload: nil, updatedAt: now.addingTimeInterval(-60), updatedBy: ""),
            SyncRecord(name: "oldItem", kind: .task, payload: nil, updatedAt: now.addingTimeInterval(-SyncLedger.retention - 60), updatedBy: "")
        ]

        XCTAssertEqual(HouseholdRecords.expiredDeletions(in: records, now: now), ["old"])
    }

    func testUnreadableRecordsAreSkipped() {
        let records = [SyncRecord(name: "x", kind: .task, payload: Data("not json".utf8), updatedAt: earlier, updatedBy: "")]

        XCTAssertTrue(HouseholdRecords.payload(from: records).tasks.isEmpty)
    }

    func testMergeKeepsLocalOrderWhenAsked() {
        let a = FamilyTask(title: "A", updatedAt: earlier)
        let b = FamilyTask(title: "B", updatedAt: earlier)
        let fromOtherPhone = FamilyTask(title: "C", updatedAt: earlier)
        let local = SharedHouseholdPayload(tasks: [a, b])
        let remote = SharedHouseholdPayload(tasks: [fromOtherPhone, b, a])

        let merged = SharedHouseholdPayload.merged(local: local, remote: remote, keepLocalOrder: true)

        XCTAssertEqual(merged.tasks.map(\.title), ["A", "B", "C"])
    }
}
