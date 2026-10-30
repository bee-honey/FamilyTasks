import XCTest
@testable import FamilyTasks

@MainActor
final class BudgetTests: XCTestCase {
    private func makeStore() throws -> (BudgetStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (BudgetStore(directory: directory, ownerEmail: { "me@example.com" }), directory)
    }

    func testAmountsReadTheWayPeopleTypeThem() {
        XCTAssertEqual(Money.parse("$2,400"), 2_400)
        XCTAssertEqual(Money.parse("2400.50"), Decimal(string: "2400.50"))
        XCTAssertEqual(Money.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Money.parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Money.parse("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(Money.parse("₹ 1,20,000"), 120_000)
        XCTAssertEqual(Money.parse("1.200.000"), 1_200_000)
        XCTAssertNil(Money.parse("monthly"))
        XCTAssertNil(Money.parse(""))
    }

    func testJustMeMoneyNeverReachesTheFamily() throws {
        let (store, directory) = try makeStore()
        let mine = try XCTUnwrap(store.add(Expense(title: "Gift for Asha", amount: 80, visibility: .justMe)))
        store.add(Expense(title: "Groceries", amount: 120, category: .groceries, visibility: .family))
        store.setLimit(500, category: .groceries, visibility: .justMe)

        XCTAssertEqual(store.exportPayload().expenses.map(\.title), ["Groceries"])
        XCTAssertTrue(store.exportPayload().limits.isEmpty)
        XCTAssertEqual(store.expenses.count, 2)
        XCTAssertEqual(mine.paidBy, "me@example.com")

        // Household records never carry private items, even if one slipped into a payload.
        var payload = SharedHouseholdPayload()
        payload.budget = BudgetPayload(expenses: store.expenses, limits: store.limits)
        let records = HouseholdRecords.records(from: payload, updatedBy: "me@example.com")
        XCTAssertNil(records[mine.id.uuidString])
        XCTAssertEqual(HouseholdRecords.payload(from: Array(records.values)).budget.expenses.map(\.title), ["Groceries"])

        // Both kinds come back after a relaunch.
        let reloaded = BudgetStore(directory: directory)
        XCTAssertEqual(Set(reloaded.expenses.map(\.title)), ["Gift for Asha", "Groceries"])
        XCTAssertEqual(reloaded.privateLimits.count, 1)
    }

    func testMakingAnExpensePrivateRemovesItFromTheFamily() throws {
        let (store, _) = try makeStore()
        var expense = try XCTUnwrap(store.add(Expense(title: "Dinner", amount: 60, visibility: .family)))
        XCTAssertEqual(store.exportPayload().expenses.count, 1)

        expense.visibility = .justMe
        store.update(expense)
        XCTAssertTrue(store.exportPayload().expenses.isEmpty)
        XCTAssertEqual(store.privateExpenses.map(\.id), [expense.id])
        XCTAssertNotNil(SyncLedger.shared.deletions[expense.id.uuidString], "Others delete their copy")

        // Family data arriving later can't overwrite private items.
        store.applySharedData(BudgetPayload(expenses: [Expense(title: "Someone's lunch", amount: 15, visibility: .family)]))
        XCTAssertEqual(store.privateExpenses.map(\.id), [expense.id])
        XCTAssertEqual(store.familyExpenses.map(\.title), ["Someone's lunch"])
    }

    func testMonthTotalsCategoriesAndScopes() throws {
        let (store, _) = try makeStore()
        let calendar = Calendar.current
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        store.add(Expense(title: "Costco", amount: 200, date: october, category: .groceries, visibility: .family))
        store.add(Expense(title: "Trader Joe's", amount: 50, date: october, category: .groceries, visibility: .justMe))
        store.add(Expense(title: "Movies", amount: 40, date: october, category: .fun, visibility: .family))
        store.add(Expense(title: "Old", amount: 999, date: september, category: .fun, visibility: .family))

        let month = BudgetMath.month(containing: october)
        XCTAssertEqual(BudgetMath.total(store.expenses(in: month)), 290)
        XCTAssertEqual(BudgetMath.total(store.expenses(in: month, scope: .family)), 240)
        XCTAssertEqual(BudgetMath.total(store.expenses(in: month, scope: .justMe)), 50)

        let categories = BudgetMath.byCategory(store.expenses(in: month))
        XCTAssertEqual(categories.first?.category, .groceries)
        XCTAssertEqual(categories.first?.total, 250)
        XCTAssertEqual(BudgetMath.progress(spent: 250, limit: 200), 1.25, accuracy: 0.001)
    }

    func testLimitsAreSetChangedAndCleared() throws {
        let (store, _) = try makeStore()
        store.setLimit(3_000, visibility: .family)
        store.setLimit(600, category: .groceries, visibility: .family)
        XCTAssertEqual(store.monthlyLimit()?.amount, 3_000)
        XCTAssertEqual(store.categoryLimit(.groceries)?.amount, 600)

        store.setLimit(3_500, visibility: .justMe)
        XCTAssertEqual(store.monthlyLimit()?.amount, 3_500)
        XCTAssertEqual(store.monthlyLimit()?.visibility, .justMe)
        XCTAssertEqual(store.limits.filter { $0.category == nil && $0.isMonthly }.count, 1)

        store.setLimit(nil, category: .groceries, visibility: .family)
        XCTAssertNil(store.categoryLimit(.groceries))
    }

    func testTaskCostsAndTripSpending() throws {
        let (store, _) = try makeStore()
        let taskID = UUID()
        store.setCost(45, taskID: taskID, title: "Fix the sink", date: nil, category: .home, visibility: .family)
        XCTAssertEqual(store.expense(forTask: taskID)?.amount, 45)
        store.setCost(60, taskID: taskID, title: "Fix the kitchen sink", date: nil, category: .home, visibility: .justMe)
        XCTAssertEqual(store.expenses.count, 1)
        XCTAssertEqual(store.expense(forTask: taskID)?.title, "Fix the kitchen sink")
        XCTAssertEqual(store.expense(forTask: taskID)?.visibility, .justMe)
        store.setCost(nil, taskID: taskID, title: "", date: nil, category: .home, visibility: .justMe)
        XCTAssertNil(store.expense(forTask: taskID))

        let trip = Trip(name: "Thanksgiving", destination: "San Diego", startDate: Date(), endDate: Date().addingTimeInterval(4 * 86_400))
        store.add(Expense(title: "Flights", amount: 640, category: .travel, tripID: trip.id))
        store.add(Expense(title: "Zoo", amount: 120, category: .fun, tripID: trip.id))
        store.setLimit(2_000, tripID: trip.id, visibility: .family)
        XCTAssertEqual(BudgetMath.total(store.expenses(for: trip)), 760)
        XCTAssertEqual(store.tripLimit(for: trip)?.amount, 2_000)
        XCTAssertNil(store.monthlyLimit(), "A trip budget isn't the monthly one")
    }

    func testRecurringPaymentsAreDueAndRecordedWhenPaid() throws {
        let (store, _) = try makeStore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let organizer = OrganizerStore(directory: directory)
        let due = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        organizer.addRecurringTask({
            var draft = RecurringTaskDraft()
            draft.title = "Mortgage"
            draft.amount = "$2,400"
            draft.nextDueDate = due
            return draft
        }())
        let mortgage = try XCTUnwrap(organizer.recurringTasks.first { $0.title == "Mortgage" })

        let month = BudgetMath.month(containing: due)
        XCTAssertEqual(BudgetMath.upcomingPayments([mortgage], in: month).first?.amount, 2_400)

        let paid = try XCTUnwrap(store.markPaid(mortgage, organizer: organizer, visibility: .family))
        XCTAssertEqual(paid.amount, 2_400)
        XCTAssertEqual(paid.category, .bills)
        XCTAssertEqual(paid.recurringTaskID, mortgage.id)
        XCTAssertLessThanOrEqual(paid.date, Date(), "Paid early is dated today")
        XCTAssertGreaterThan(try XCTUnwrap(organizer.recurringTasks.first { $0.id == mortgage.id }).nextDueDate, due)
    }

    func testOlderHouseholdsWithoutBudgetsStillLoad() throws {
        let old = try JSONDecoder().decode(SharedHouseholdPayload.self, from: Data(#"{"tasks":[]}"#.utf8))
        XCTAssertEqual(old.budget, BudgetPayload())
    }
}
