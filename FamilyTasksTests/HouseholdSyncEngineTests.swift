import XCTest
@testable import FamilyTasks

/// An in-memory stand-in for the shared CloudKit zone. Like CloudKit, it hands out
/// change tokens, rejects saves based on an outdated copy of a record, and can expire tokens.
@MainActor
private final class FakeCloudServer {
    struct Stored {
        var entry: CloudMirror.Entry
        var version: Int
        var sequence: Int
    }

    var items: [String: Stored] = [:]
    var deletions: [String: Int] = [:]
    var root = CloudRoot()
    var rootVersion = 0
    var rootSequence = 0
    var sequence = 0
    var expireNextToken = false
    /// Runs once just before the next save is processed, to simulate another phone saving in between.
    var beforeNextSave: (() -> Void)?

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func nextSequence() -> Int {
        sequence += 1
        return sequence
    }

    /// Writes a record the way another phone would, bypassing any engine.
    func write(_ record: SyncRecord) {
        let version = (items[record.name]?.version ?? 0) + 1
        let createdAt = items[record.name]?.entry.createdAt ?? epoch.addingTimeInterval(Double(sequence))
        items[record.name] = Stored(
            entry: CloudMirror.Entry(record: record, systemFields: Self.tag(version), createdAt: createdAt),
            version: version,
            sequence: nextSequence()
        )
    }

    /// The household as an older app version stored it, on the root record.
    func writeLegacyRoot(_ payload: SharedHouseholdPayload, schemaVersion: Int = 2) throws {
        rootVersion += 1
        root = CloudRoot(systemFields: Self.tag(rootVersion), schemaVersion: schemaVersion, legacyPayload: try JSONEncoder().encode(payload))
        rootSequence = nextSequence()
    }

    func record(named name: String) -> SyncRecord? {
        items[name]?.entry.record
    }

    static func tag(_ version: Int) -> Data { Data("\(version)".utf8) }
    static func version(of tag: Data?) -> Int? { tag.flatMap { Int(String(decoding: $0, as: UTF8.self)) } }
}

@MainActor
private struct FakeCloud: HouseholdCloud {
    let server: FakeCloudServer

    func fetchChanges(since changeToken: Data?) async throws -> CloudChanges {
        if server.expireNextToken, changeToken != nil {
            server.expireNextToken = false
            throw HouseholdCloudError.changeTokenExpired
        }

        let since = FakeCloudServer.version(of: changeToken) ?? 0
        return CloudChanges(
            entries: server.items.values.filter { $0.sequence > since }.map(\.entry),
            root: server.rootSequence > since ? server.root : nil,
            deletedNames: server.deletions.filter { $0.value > since }.map(\.key),
            changeToken: FakeCloudServer.tag(server.sequence)
        )
    }

    func save(_ entries: [CloudMirror.Entry], root: CloudRoot?) async throws -> (entries: [String: CloudSaveResult<CloudMirror.Entry>], root: CloudSaveResult<CloudRoot>?) {
        server.beforeNextSave?()
        server.beforeNextSave = nil

        var results: [String: CloudSaveResult<CloudMirror.Entry>] = [:]
        for entry in entries {
            let name = entry.record.name
            let current = server.items[name]
            guard current?.version == FakeCloudServer.version(of: entry.systemFields) || (current == nil && entry.systemFields == nil) else {
                results[name] = .conflict(current?.entry)
                continue
            }
            server.write(entry.record)
            results[name] = .saved(server.items[name]!.entry)
        }

        var rootResult: CloudSaveResult<CloudRoot>?
        if var root {
            if FakeCloudServer.version(of: root.systemFields) ?? 0 == server.rootVersion {
                server.rootVersion += 1
                root.systemFields = FakeCloudServer.tag(server.rootVersion)
                server.root = root
                server.rootSequence = server.nextSequence()
                rootResult = .saved(root)
            } else {
                rootResult = .conflict(server.root)
            }
        }
        return (results, rootResult)
    }

    func delete(_ names: [String]) async throws -> [String] {
        for name in names {
            server.items[name] = nil
            server.deletions[name] = server.nextSequence()
        }
        return names
    }
}

/// One family member's device: its local household and its sync engine.
@MainActor
private final class FakePhone: HouseholdDataSource {
    let email: String
    var payload: SharedHouseholdPayload
    let engine: HouseholdSyncEngine

    init(_ email: String, server: FakeCloudServer, payload: SharedHouseholdPayload = SharedHouseholdPayload()) {
        self.email = email
        self.payload = payload
        self.payload.updatedBy = email
        engine = HouseholdSyncEngine(cloud: FakeCloud(server: server), mirror: CloudMirror(zoneKey: "zone"))
    }

    func currentPayload() -> SharedHouseholdPayload? { payload }

    func apply(_ payload: SharedHouseholdPayload, changedRecords: [SyncRecord]) {
        self.payload = payload
        self.payload.updatedBy = email
    }

    @discardableResult
    func sync(_ mode: HouseholdSyncEngine.Mode = .merge) async throws -> HouseholdSyncEngine.Outcome? {
        try await engine.sync(self, mode: mode)
    }

    var taskTitles: Set<String> { Set(payload.tasks.map(\.title)) }

    func edit(_ id: UUID, title: String, at date: Date) {
        guard let index = payload.tasks.firstIndex(where: { $0.id == id }) else { return XCTFail("No task \(id)") }
        payload.tasks[index].title = title
        payload.tasks[index].updatedAt = date
    }

    func delete(_ id: UUID, at date: Date) {
        payload.tasks.removeAll { $0.id == id }
        payload.deletions[id.uuidString] = date
    }
}

@MainActor
final class HouseholdSyncEngineTests: XCTestCase {
    private let base = Date().addingTimeInterval(-3_600)
    private var earlier: Date { base }
    private var later: Date { base.addingTimeInterval(120) }
    private var latest: Date { base.addingTimeInterval(240) }

    private var server: FakeCloudServer!

    override func setUp() async throws {
        server = FakeCloudServer()
    }

    func testJoiningPhoneTakesTheFamilysDataInsteadOfItsOwn() async throws {
        let owner = FakePhone("owner@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "Family task")]))
        let joiner = FakePhone("joiner@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "Sample task")]))

        try await owner.sync()
        try await joiner.sync(.adoptRemote)

        XCTAssertEqual(joiner.taskTitles, ["Family task"])
    }

    func testEditsToDifferentItemsOnTwoPhonesBothSurvive() async throws {
        let shared = FamilyTask(title: "Shared", updatedAt: earlier)
        let phoneA = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [shared]))
        let phoneB = FakePhone("b@example.com", server: server)
        try await phoneA.sync()
        try await phoneB.sync(.adoptRemote)

        phoneA.payload.tasks.append(FamilyTask(title: "Added on A"))
        phoneB.payload.tasks.append(FamilyTask(title: "Added on B"))
        try await phoneA.sync()
        try await phoneB.sync()
        try await phoneA.sync()

        XCTAssertEqual(phoneA.taskTitles, ["Shared", "Added on A", "Added on B"])
        XCTAssertEqual(phoneB.taskTitles, phoneA.taskTitles)
    }

    func testNewerEditOfTheSameItemWinsOnBothPhones() async throws {
        let task = FamilyTask(title: "Original", updatedAt: earlier)
        let phoneA = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [task]))
        let phoneB = FakePhone("b@example.com", server: server)
        try await phoneA.sync()
        try await phoneB.sync(.adoptRemote)

        phoneA.edit(task.id, title: "Newer edit on A", at: latest)
        phoneB.edit(task.id, title: "Older edit on B", at: later)
        try await phoneA.sync()
        try await phoneB.sync()

        XCTAssertEqual(phoneA.taskTitles, ["Newer edit on A"])
        XCTAssertEqual(phoneB.taskTitles, ["Newer edit on A"])
        XCTAssertEqual(server.record(named: task.id.uuidString)?.updatedAt, latest)
    }

    func testNewerEditSavedInBetweenIsMergedNotOverwritten() async throws {
        let task = FamilyTask(title: "Original", updatedAt: earlier)
        let phone = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [task]))
        try await phone.sync()

        var newer = task
        newer.title = "Saved by B in between"
        newer.updatedAt = latest
        let newerRecord = HouseholdRecords.records(from: SharedHouseholdPayload(tasks: [newer]), updatedBy: "b@example.com")[task.id.uuidString]!
        server.beforeNextSave = { [server] in server!.write(newerRecord) }

        phone.edit(task.id, title: "Older edit on A", at: later)
        try await phone.sync()

        XCTAssertEqual(phone.taskTitles, ["Saved by B in between"])
        XCTAssertEqual(server.record(named: task.id.uuidString)?.updatedAt, latest)
    }

    func testOlderEditSavedInBetweenIsOverwrittenAfterRetry() async throws {
        let task = FamilyTask(title: "Original", updatedAt: earlier)
        let phone = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [task]))
        try await phone.sync()

        var older = task
        older.title = "Older edit saved by B"
        older.updatedAt = later
        let olderRecord = HouseholdRecords.records(from: SharedHouseholdPayload(tasks: [older]), updatedBy: "b@example.com")[task.id.uuidString]!
        server.beforeNextSave = { [server] in server!.write(olderRecord) }

        phone.edit(task.id, title: "Newer edit on A", at: latest)
        try await phone.sync()

        XCTAssertEqual(phone.taskTitles, ["Newer edit on A"])
        XCTAssertEqual(server.record(named: task.id.uuidString)?.updatedAt, latest)
    }

    func testDeletionReachesTheOtherPhoneAndAnOlderEditDoesNotBringItBack() async throws {
        let task = FamilyTask(title: "Doomed", updatedAt: earlier)
        let phoneA = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [task]))
        let phoneB = FakePhone("b@example.com", server: server)
        try await phoneA.sync()
        try await phoneB.sync(.adoptRemote)

        phoneB.edit(task.id, title: "Edited before the delete", at: later)
        phoneA.delete(task.id, at: latest)
        try await phoneA.sync()
        try await phoneB.sync()
        try await phoneA.sync()

        XCTAssertTrue(phoneA.payload.tasks.isEmpty)
        XCTAssertTrue(phoneB.payload.tasks.isEmpty)
        XCTAssertEqual(server.record(named: task.id.uuidString)?.kind, .deleted)
    }

    func testOldSingleRecordHouseholdIsMigratedToRecords() async throws {
        try server.writeLegacyRoot(SharedHouseholdPayload(tasks: [FamilyTask(title: "From the old version")]))
        let updated = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "Local")]))

        try await updated.sync()

        XCTAssertEqual(updated.taskTitles, ["From the old version", "Local"])
        XCTAssertEqual(server.root.schemaVersion, CloudRoot.recordsSchemaVersion)
        XCTAssertNil(server.root.legacyPayload)
        XCTAssertEqual(server.items.values.filter { $0.entry.record.kind == .task }.count, 2)

        let joiner = FakePhone("b@example.com", server: server)
        try await joiner.sync(.adoptRemote)
        XCTAssertEqual(joiner.taskTitles, ["From the old version", "Local"])
    }

    func testOldVersionWritingAfterMigrationIsIgnored() async throws {
        let phone = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "Current")]))
        try await phone.sync()

        // An old phone rewrites its payload but does not know about schemaVersion, so it stays at 3.
        try server.writeLegacyRoot(SharedHouseholdPayload(tasks: [FamilyTask(title: "From an old phone")]), schemaVersion: CloudRoot.recordsSchemaVersion)
        try await phone.sync()

        XCTAssertEqual(phone.taskTitles, ["Current"])
    }

    func testSyncWithNothingNewUploadsNothing() async throws {
        let phone = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "Task")]))

        let first = try await phone.sync()
        let second = try await phone.sync()

        XCTAssertEqual(first, .uploaded(count: 2)) // the task and the household record
        XCTAssertEqual(second, .upToDate)
    }

    func testExpiredChangeTokenRefetchesEverything() async throws {
        let phoneA = FakePhone("a@example.com", server: server, payload: SharedHouseholdPayload(tasks: [FamilyTask(title: "First")]))
        try await phoneA.sync()

        let fromB = FamilyTask(title: "From B", updatedAt: later)
        server.write(HouseholdRecords.records(from: SharedHouseholdPayload(tasks: [fromB]), updatedBy: "b@example.com")[fromB.id.uuidString]!)
        server.expireNextToken = true
        try await phoneA.sync()

        XCTAssertEqual(phoneA.taskTitles, ["First", "From B"])
        XCTAssertEqual(phoneA.engine.mirror.records.count, server.items.count)
    }
}
