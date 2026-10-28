import XCTest
@testable import FamilyTasks

@MainActor
final class HabitStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(owner: String = "me@example.com") -> HabitStore {
        HabitStore(directory: directory, ownerEmail: { owner })
    }

    func testLoggingCountsUpToTheDailyTarget() throws {
        let store = store()
        store.add(name: "Drink water", symbol: "drop", color: .blue, timesPerDay: 3, weekdays: [], isShared: false)
        let habit = try XCTUnwrap(store.habits.first)

        store.log(habit)
        store.log(habit)
        XCTAssertEqual(store.count(of: habit), 2)
        XCTAssertFalse(store.isDone(habit))

        store.log(habit)
        store.log(habit)
        XCTAssertEqual(store.count(of: habit), 3)
        XCTAssertTrue(store.isDone(habit))

        store.undo(habit)
        XCTAssertEqual(store.count(of: habit), 2)
    }

    func testLogsAreKeptAfterRelaunch() throws {
        let first = store()
        first.add(name: "Read", symbol: "book", color: .purple, timesPerDay: 1, weekdays: [], isShared: false)
        first.log(try XCTUnwrap(first.habits.first))

        let relaunched = store()
        XCTAssertTrue(relaunched.isDone(try XCTUnwrap(relaunched.habits.first)))
    }

    func testReachingTodaysTargetOnASharedHabitIsAnnouncedOnce() throws {
        let store = store()
        store.add(name: "Water", symbol: "drop", color: .blue, timesPerDay: 2, weekdays: [], isShared: true)
        store.add(name: "Diary", symbol: "book", color: .purple, timesPerDay: 1, weekdays: [], isShared: false)
        let water = try XCTUnwrap(store.habits.first { $0.name == "Water" })
        let diary = try XCTUnwrap(store.habits.first { $0.name == "Diary" })

        var announced: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .familyItemChangedLocally, object: nil, queue: nil) { note in
            if case let .habitDone(habit, _, _) = note.userInfo?["change"] as? LocalItemChange {
                announced.append(habit.name)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.log(water)
        XCTAssertEqual(announced, [])
        store.log(water)
        XCTAssertEqual(announced, ["Water"])
        store.log(diary)
        // Fixing yesterday in the history doesn't count as news.
        store.cycle(water, on: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        store.cycle(water, on: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        XCTAssertEqual(announced, ["Water"])
    }

    func testSomeoneElsesHabitCannotBeLogged() throws {
        let theirs = store(owner: "partner@example.com")
        theirs.add(name: "Walk", symbol: "pawprint", color: .green, timesPerDay: 1, weekdays: [], isShared: true)

        let mine = store()
        let habit = try XCTUnwrap(mine.habits.first)
        mine.log(habit)
        XCTAssertEqual(mine.count(of: habit), 0)
    }
}
