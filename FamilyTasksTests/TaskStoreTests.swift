import XCTest
@testable import FamilyTasks

@MainActor
final class TaskStoreTests: XCTestCase {
    private var directory: URL!
    private var tasksURL: URL { directory.appendingPathComponent("family-tasks.json") }
    private var savedProfileEmail: String?

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

    func testSampleTasksAreSeededOnlyOnFirstLaunch() {
        let firstLaunch = TaskStore(storageURL: tasksURL)
        XCTAssertEqual(firstLaunch.tasks.count, 3)

        firstLaunch.tasks.forEach(firstLaunch.delete)
        let relaunch = TaskStore(storageURL: tasksURL)

        XCTAssertTrue(relaunch.tasks.isEmpty)
    }

    func testFamilyMembersAreStoredNextToTheTasksFile() {
        let store = TaskStore(storageURL: tasksURL)
        store.addFamilyMember(named: "Kid@Example.com ")

        XCTAssertTrue(store.familyMembers.contains("kid@example.com"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("family-members.json").path))
    }

    func testUnreadableTasksFileIsBackedUpAndNotReseeded() throws {
        try Data("not json".utf8).write(to: tasksURL)

        let store = TaskStore(storageURL: tasksURL)

        XCTAssertTrue(store.tasks.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.contains("unreadable") }, "\(files)")
    }

    func testDeletingATaskRecordsItForSync() throws {
        let store = TaskStore(storageURL: tasksURL)
        let task = try XCTUnwrap(store.tasks.first)

        store.delete(task)

        XCTAssertNotNil(SyncLedger.shared.deletions[task.id.uuidString])
    }

    func testAssigningSpecificMembersAlsoIncludesTheCreator() throws {
        let store = TaskStore(storageURL: tasksURL)
        var draft = TaskDraft()
        draft.title = "  Pack lunches  "
        draft.assignsToEveryone = false
        draft.assignedToEmails = ["kid@example.com"]

        store.add(draft)

        let task = try XCTUnwrap(store.tasks.last)
        XCTAssertEqual(task.title, "Pack lunches")
        XCTAssertEqual(task.assigneeEmails, ["kid@example.com", "parent@example.com"])
        XCTAssertEqual(task.createdBy, "parent@example.com")
    }

    func testTasksAssignedToOthersAreHiddenFromMyLists() {
        let store = TaskStore(storageURL: tasksURL)
        store.tasks.forEach(store.delete)
        var draft = TaskDraft()
        draft.title = "Mine"
        store.add(draft)

        UserDefaults.standard.set("other@example.com", forKey: "profile.email")
        var othersTask = TaskDraft()
        othersTask.title = "Other's private"
        othersTask.assignsToEveryone = false
        store.add(othersTask)
        UserDefaults.standard.set("parent@example.com", forKey: "profile.email")

        XCTAssertEqual(store.visibleTasks.map(\.title), ["Mine"])
    }

    func testApplyingUnchangedSharedDataLeavesTheStoreAlone() {
        let store = TaskStore(storageURL: tasksURL)
        let tasks = store.exportTasks()
        let members = store.exportFamilyMembers()
        // The first apply stores the normalized member list (sorted, including this device's profile).
        store.applySharedData(tasks: tasks, familyMembers: members)
        var changes = 0
        let observation = store.objectWillChange.sink { changes += 1 }

        store.applySharedData(tasks: tasks, familyMembers: members)
        XCTAssertEqual(changes, 0)

        store.applySharedData(tasks: tasks + [FamilyTask(title: "From the other phone")], familyMembers: members)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(TaskStore(storageURL: tasksURL).exportTasks().contains { $0.title == "From the other phone" })
        observation.cancel()
    }
}
