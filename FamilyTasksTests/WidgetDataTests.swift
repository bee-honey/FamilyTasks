import XCTest
@testable import FamilyTasks

@MainActor
final class WidgetDataTests: XCTestCase {
    private var directory: URL!
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3_600) }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    func testSnapshotHasOpenTasksForTheComingWeekAndNeededItems() {
        let shop = Shop(name: "Grocer")
        let otherShop = Shop(name: "Hardware")
        let tasks = [
            FamilyTask(title: "Overdue", dueDate: day(-2)),
            FamilyTask(title: "Today", dueDate: day(0)),
            FamilyTask(title: "Next week", dueDate: day(6)),
            FamilyTask(title: "Too far", dueDate: day(10)),
            FamilyTask(title: "No date"),
            FamilyTask(title: "Done", dueDate: day(0), isDone: true)
        ]
        let items = [
            ShoppingItem(name: "Milk", shopID: shop.id),
            ShoppingItem(name: "Bought", shopID: shop.id, isNeeded: false, isPurchased: true),
            ShoppingItem(name: "Usual, not needed", shopID: shop.id, isNeeded: false),
            ShoppingItem(name: "Nails", shopID: otherShop.id)
        ]

        let snapshot = WidgetBridge.snapshot(tasks: tasks, shops: [shop, otherShop], items: items, now: today)

        XCTAssertEqual(Set(snapshot.tasks.map(\.title)), ["Overdue", "Today", "Next week"])
        XCTAssertEqual(snapshot.shops.map(\.name), ["Grocer", "Hardware"])
        XCTAssertEqual(snapshot.shops[0].items.map(\.name), ["Milk"])
        XCTAssertEqual(snapshot.shops[1].items.map(\.name), ["Nails"])
    }

    func testTasksForADaySplitDueAndOverdue() {
        let snapshot = WidgetBridge.snapshot(
            tasks: [FamilyTask(title: "Overdue", dueDate: day(-1)), FamilyTask(title: "Today", dueDate: day(0)), FamilyTask(title: "Tomorrow", dueDate: day(1))],
            shops: [],
            items: [],
            now: today
        )

        let todays = snapshot.tasks(for: today)
        XCTAssertEqual(todays.due.map(\.title), ["Today"])
        XCTAssertEqual(todays.overdue.map(\.title), ["Overdue"])

        // After midnight, today's open task counts as overdue and tomorrow's is due.
        let tomorrows = snapshot.tasks(for: day(1))
        XCTAssertEqual(tomorrows.due.map(\.title), ["Tomorrow"])
        XCTAssertEqual(Set(tomorrows.overdue.map(\.title)), ["Overdue", "Today"])
    }

    func testWidgetCheckOffsAreAppliedToTheStoresAndCleared() throws {
        let storage = WidgetStorage(directory: directory)
        let taskStore = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let organizerStore = OrganizerStore(directory: directory)
        let task = try XCTUnwrap(taskStore.tasks.first { !$0.isDone })
        let shop = try XCTUnwrap(organizerStore.shops.first)
        organizerStore.addNeededItem("Milk", to: shop)
        let item = try XCTUnwrap(organizerStore.shoppingItems.first { $0.name == "Milk" })

        let tappedAt = Date().addingTimeInterval(1)
        try storage.record(WidgetAction(kind: .completeTask, id: task.id, date: tappedAt))
        try storage.record(WidgetAction(kind: .purchaseItem, id: item.id, date: tappedAt))

        let bridge = WidgetBridge(storage: storage)
        bridge.configure(taskStore: taskStore, organizerStore: organizerStore)

        let doneTask = try XCTUnwrap(taskStore.tasks.first { $0.id == task.id })
        XCTAssertTrue(doneTask.isDone)
        XCTAssertEqual(doneTask.updatedAt, tappedAt)
        let boughtItem = try XCTUnwrap(organizerStore.shoppingItems.first { $0.id == item.id })
        XCTAssertTrue(boughtItem.isPurchased)
        XCTAssertFalse(boughtItem.isNeeded)
        XCTAssertTrue(storage.pendingActions().isEmpty)
        XCTAssertFalse(storage.loadSnapshot().tasks.contains { $0.id == task.id })
    }

    func testCheckOffIsSkippedWhenTheItemWasEditedAfterTheTap() throws {
        let taskStore = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let task = try XCTUnwrap(taskStore.tasks.first { !$0.isDone })

        taskStore.markDone(taskID: task.id, at: task.updatedAt.addingTimeInterval(-60))

        XCTAssertFalse(taskStore.tasks.first { $0.id == task.id }!.isDone)
    }

    func testPublishedSnapshotStillHidesCheckOffsNotYetApplied() throws {
        let storage = WidgetStorage(directory: directory)
        let task = FamilyTask(title: "Tapped in widget", dueDate: today)
        var snapshot = WidgetBridge.snapshot(tasks: [task], shops: [], items: [], now: today)

        snapshot.apply(WidgetAction(kind: .completeTask, id: task.id, date: today))
        storage.save(snapshot)

        XCTAssertTrue(storage.loadSnapshot().tasks.isEmpty)
    }
}
