import XCTest
@testable import FamilyTasks

@MainActor
final class OrganizerStoreTests: XCTestCase {
    private var directory: URL!
    private let calendar = Calendar.current

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaultsAreSeededOnlyOnFirstLaunch() {
        let firstLaunch = OrganizerStore(directory: directory)
        XCTAssertEqual(firstLaunch.shops.count, 3)
        XCTAssertEqual(firstLaunch.recurringTasks.count, 2)

        firstLaunch.shops.forEach(firstLaunch.deleteShop)
        firstLaunch.recurringTasks.forEach(firstLaunch.deleteRecurringTask)
        let relaunch = OrganizerStore(directory: directory)

        XCTAssertTrue(relaunch.shops.isEmpty)
        XCTAssertTrue(relaunch.recurringTasks.isEmpty)
    }

    func testCompletingAnOverdueMonthlyTaskKeepsItsDayAndTime() throws {
        let store = emptyStore()
        let originalDue = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: Date()))
        let task = addRecurringTask(to: store, frequency: .monthly, nextDueDate: originalDue)

        store.markRecurringDone(task)

        let next = try XCTUnwrap(store.recurringTasks.first?.nextDueDate)
        XCTAssertEqual(next, calendar.date(byAdding: .month, value: 1, to: originalDue))
    }

    func testCompletingATaskOverdueByManyPeriodsSkipsToTheNextFutureOccurrence() throws {
        let store = emptyStore()
        let originalDue = try XCTUnwrap(calendar.date(byAdding: .hour, value: -(10 * 24 + 1), to: Date()))
        let task = addRecurringTask(to: store, frequency: .daily, nextDueDate: originalDue)

        store.markRecurringDone(task)

        let next = try XCTUnwrap(store.recurringTasks.first?.nextDueDate)
        XCTAssertGreaterThan(next, Date())
        XCTAssertLessThanOrEqual(next, Date().addingTimeInterval(86_400))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: next),
                       calendar.dateComponents([.hour, .minute], from: originalDue))
    }

    func testCompletingEarlyMovesToTheFollowingOccurrence() throws {
        let store = emptyStore()
        let originalDue = try XCTUnwrap(calendar.date(byAdding: .day, value: 10, to: Date()))
        let task = addRecurringTask(to: store, frequency: .weekly, nextDueDate: originalDue)

        store.markRecurringDone(task)

        XCTAssertEqual(store.recurringTasks.first?.nextDueDate, calendar.date(byAdding: .weekOfYear, value: 1, to: originalDue))
    }

    func testRecurringTaskAppearsOnEachOccurrenceOnly() throws {
        let store = emptyStore()
        let start = Date()
        _ = addRecurringTask(to: store, frequency: .weekly, nextDueDate: start)

        let twoWeeksLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: start))
        let thirteenDaysLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 13, to: start))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: start))

        XCTAssertEqual(store.recurringTasks(on: twoWeeksLater).count, 1)
        XCTAssertTrue(store.recurringTasks(on: thirteenDaysLater).isEmpty)
        XCTAssertTrue(store.recurringTasks(on: yesterday).isEmpty)
    }

    func testOnlyChosenIngredientsAreAddedToShopping() throws {
        let store = OrganizerStore(directory: directory)
        let shop = try XCTUnwrap(store.shops.first)
        let pasta = MealIngredient(name: "Pasta", defaultShopID: shop.id)
        let basil = MealIngredient(name: "Basil", defaultShopID: shop.id)
        let meal = MealIdea(name: "Pesto", ingredients: [pasta, basil])
        let before = store.shoppingItems.count

        store.addMealIngredientsToShopping(meal, overrides: [pasta.id: shop.id])

        XCTAssertEqual(store.shoppingItems.count, before + 1)
        XCTAssertEqual(store.shoppingItems.last?.name, "Pasta")
    }

    func testReorderingShopsTimestampsTheOrderForSync() throws {
        let store = OrganizerStore(directory: directory)
        XCTAssertNil(store.exportShoppingPayload().orderUpdatedAt)

        store.moveShopDown(try XCTUnwrap(store.shops.first))

        XCTAssertNotNil(store.exportShoppingPayload().orderUpdatedAt)
        XCTAssertNotNil(OrganizerStore(directory: directory).exportShoppingPayload().orderUpdatedAt)
    }

    func testClosingATripRemovesOnlyPurchasedItems() throws {
        let store = OrganizerStore(directory: directory)
        let shop = try XCTUnwrap(store.shops.first)
        store.addNeededItem("Eggs", to: shop)
        store.addNeededItem("Butter", to: shop)
        let eggs = try XCTUnwrap(store.items(for: shop).first { $0.name == "Eggs" })
        store.togglePurchased(eggs)

        store.closeTrip(for: shop)

        let names = store.items(for: shop).map(\.name)
        XCTAssertFalse(names.contains("Eggs"))
        XCTAssertTrue(names.contains("Butter"))
    }

    // MARK: - Helpers

    private func emptyStore() -> OrganizerStore {
        let store = OrganizerStore(directory: directory)
        store.recurringTasks.forEach(store.deleteRecurringTask)
        return store
    }

    private func addRecurringTask(to store: OrganizerStore, frequency: RecurrenceFrequency, nextDueDate: Date) -> RecurringTask {
        var draft = RecurringTaskDraft()
        draft.title = "Pay bill"
        draft.frequency = frequency
        draft.nextDueDate = nextDueDate
        store.addRecurringTask(draft)
        return store.recurringTasks.last!
    }

    func testApplyingUnchangedSharedDataLeavesTheStoreAlone() {
        let store = OrganizerStore(directory: directory)
        let snapshot = (
            shopping: store.exportShoppingPayload(),
            recurring: store.exportRecurringTasks(),
            mealPlan: store.exportMealPlanPayload(),
            ideas: store.exportIdeas(),
            health: store.exportHealthSnapshots()
        )
        var changes = 0
        let observation = store.objectWillChange.sink { changes += 1 }

        store.applySharedData(shopping: snapshot.shopping, recurringTasks: snapshot.recurring, mealPlan: snapshot.mealPlan, ideas: snapshot.ideas, healthSnapshots: snapshot.health)
        XCTAssertEqual(changes, 0)

        let renamed = snapshot.ideas + [IdeaNote(title: "From the other phone")]
        store.applySharedData(shopping: snapshot.shopping, recurringTasks: snapshot.recurring, mealPlan: snapshot.mealPlan, ideas: renamed, healthSnapshots: snapshot.health)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(OrganizerStore(directory: directory).exportIdeas().map(\.title), renamed.map(\.title))
        observation.cancel()
    }
}
