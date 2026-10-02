import XCTest
@testable import FamilyTasks

@MainActor
final class ChoreTests: XCTestCase {
    private var directory: URL!
    private var savedProfileEmail: String?
    private let calendar = Calendar.current

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedProfileEmail = UserDefaults.standard.string(forKey: "profile.email")
        UserDefaults.standard.set("parent@example.com", forKey: "profile.email")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedProfileEmail, forKey: "profile.email")
        try? FileManager.default.removeItem(at: directory)
    }

    private func storeWithKidAndChore(points: Int = 5, frequency: RecurrenceFrequency = .daily) throws -> (ChoreStore, KidProfile, Chore) {
        let store = ChoreStore(directory: directory)
        store.addKid(named: "Alice")
        let kid = try XCTUnwrap(store.kids.first)
        store.addChore(title: "Make bed", points: points, frequency: frequency, kidIDs: [kid.id])
        return (store, kid, try XCTUnwrap(store.chores.first))
    }

    func testPointsOnlyCountOnceApproved() throws {
        let (store, kid, chore) = try storeWithKidAndChore(points: 5)

        store.markDone(chore, for: kid)
        XCTAssertEqual(store.status(of: chore, for: kid), .waitingForApproval)
        XCTAssertEqual(store.balance(for: kid), 0)

        store.approve(try XCTUnwrap(store.waitingForApproval.first))
        XCTAssertEqual(store.status(of: chore, for: kid), .done)
        XCTAssertEqual(store.balance(for: kid), 5)
        XCTAssertEqual(store.completions.first?.approvedBy, "parent@example.com")
    }

    func testNotDonePutsTheChoreBackWithNoPoints() throws {
        let (store, kid, chore) = try storeWithKidAndChore()

        store.markDone(chore, for: kid)
        store.reject(try XCTUnwrap(store.waitingForApproval.first))

        XCTAssertEqual(store.status(of: chore, for: kid), .toDo)
        XCTAssertEqual(store.balance(for: kid), 0)
    }

    func testAChoreCanOnlyBeDoneOncePerPeriod() throws {
        let (store, kid, chore) = try storeWithKidAndChore(frequency: .daily)

        store.markDone(chore, for: kid)
        store.markDone(chore, for: kid)
        XCTAssertEqual(store.completions.count, 1)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        XCTAssertEqual(store.status(of: chore, for: kid, now: tomorrow), .toDo)
        store.markDone(chore, for: kid, at: tomorrow)
        XCTAssertEqual(store.completions.count, 2)
    }

    func testWeeklyChoreStaysDoneAllWeek() throws {
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date())).start
        let chore = Chore(title: "Mow", points: 10, frequency: .weekly)
        let kid = UUID()
        let completion = ChoreCompletion(choreID: chore.id, kidID: kid, choreTitle: chore.title, points: 10, status: .approved, completedAt: weekStart.addingTimeInterval(3_600))

        XCTAssertEqual(ChoreMath.status(of: chore, for: kid, completions: [completion], now: weekStart.addingTimeInterval(5 * 86_400)), .done)
        XCTAssertEqual(ChoreMath.status(of: chore, for: kid, completions: [completion], now: weekStart.addingTimeInterval(8 * 86_400)), .toDo)
    }

    func testPayingOutComesOffTheRunningTotal() throws {
        let (store, kid, chore) = try storeWithKidAndChore(points: 30)
        store.markDone(chore, for: kid)
        store.approve(try XCTUnwrap(store.waitingForApproval.first))

        store.payOut(20, to: kid)

        XCTAssertEqual(store.balance(for: kid), 10)
    }

    func testPointsConvertToMoneyAtTheFamilyRate() {
        let rate = ChoreSettings(pointsPerCurrencyUnit: 10)
        XCTAssertEqual(ChoreMath.money(for: 45, settings: rate), Decimal(string: "4.5"))
        XCTAssertEqual(ChoreMath.formattedMoney(for: 45, settings: rate, locale: Locale(identifier: "en_US")), "$4.50")
        XCTAssertEqual(ChoreMath.money(for: 3, settings: ChoreSettings(pointsPerCurrencyUnit: 0)), 3, "A zero rate must not divide by zero")
    }

    func testRemovingAKidRemovesTheirAssignmentsAndHistory() throws {
        let (store, kid, chore) = try storeWithKidAndChore()
        store.markDone(chore, for: kid)
        store.payOut(1, to: kid)

        store.deleteKid(kid)

        XCTAssertTrue(store.kids.isEmpty)
        XCTAssertEqual(store.chores.first?.kidIDs, [])
        XCTAssertTrue(store.completions.isEmpty)
        XCTAssertTrue(store.payouts.isEmpty)
    }

    func testChoresSurviveARelaunch() throws {
        let (store, kid, chore) = try storeWithKidAndChore()
        store.markDone(chore, for: kid)
        store.setPointsPerCurrencyUnit(20)

        let relaunched = ChoreStore(directory: directory)

        XCTAssertEqual(relaunched.exportPayload(), store.exportPayload())
    }

    func testChoresRoundTripThroughSyncRecords() {
        let kid = KidProfile(name: "Alice")
        let chore = Chore(title: "Make bed", points: 5, kidIDs: [kid.id])
        let chores = ChoresPayload(
            kids: [kid],
            chores: [chore],
            completions: [ChoreCompletion(choreID: chore.id, kidID: kid.id, choreTitle: chore.title, points: 5)],
            payouts: [ChorePayout(kidID: kid.id, points: 2)],
            settings: ChoreSettings(pointsPerCurrencyUnit: 20, updatedAt: Date())
        )

        let records = HouseholdRecords.records(from: SharedHouseholdPayload(chores: chores), updatedBy: "")
        let restored = HouseholdRecords.payload(from: Array(records.values)).chores

        XCTAssertEqual(restored, chores)
    }

    func testCompletionApprovedOnOnePhoneIsNotUndoneByAnOlderCopy() {
        let kid = KidProfile(name: "Alice")
        let waiting = ChoreCompletion(choreID: UUID(), kidID: kid.id, choreTitle: "Make bed", points: 5, updatedAt: Date().addingTimeInterval(-60))
        var approved = waiting
        approved.status = .approved
        approved.updatedAt = Date()

        let merged = SharedHouseholdPayload.merged(
            local: SharedHouseholdPayload(chores: ChoresPayload(kids: [kid], completions: [waiting])),
            remote: SharedHouseholdPayload(chores: ChoresPayload(kids: [kid], completions: [approved]))
        )

        XCTAssertEqual(merged.chores.completions.map(\.status), [.approved])
    }
}
