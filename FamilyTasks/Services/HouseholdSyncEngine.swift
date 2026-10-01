import Foundation

/// This device's copy of the shared zone as of the last sync: every record with the
/// CloudKit metadata needed to update it, plus the token for fetching only newer changes.
struct CloudMirror: Codable {
    struct Entry: Codable, Equatable {
        var record: SyncRecord
        /// CloudKit's own bookkeeping for the record (including its change tag), opaque to the engine.
        var systemFields: Data?
        var createdAt: Date?
    }

    var zoneKey: String
    var changeToken: Data?
    var records: [String: Entry] = [:]
    var root = CloudRoot()

    /// Records oldest first, so items keep a stable order across devices.
    var orderedRecords: [SyncRecord] {
        records.values
            .sorted { lhs, rhs in
                let left = lhs.createdAt ?? .distantFuture
                let right = rhs.createdAt ?? .distantFuture
                return left != right ? left < right : lhs.record.name < rhs.record.name
            }
            .map(\.record)
    }

    var currentRecords: [String: SyncRecord] {
        records.mapValues(\.record)
    }
}

/// The shared root record that every family member's records hang off.
struct CloudRoot: Codable, Equatable {
    /// Root records at this version hold no data; everything lives in item records.
    static let recordsSchemaVersion = 3

    var systemFields: Data?
    var schemaVersion = 0
    /// The whole household as older app versions stored it, kept until merged and cleared.
    var legacyPayload: Data?
}

struct CloudChanges {
    var entries: [CloudMirror.Entry] = []
    var root: CloudRoot?
    var deletedNames: [String] = []
    var changeToken: Data?
    var moreComing = false
}

enum CloudSaveResult<Value> {
    case saved(Value)
    /// Someone else changed it since this device last saw it; carries their version when known.
    case conflict(Value?)
    case failed(Error)
}

enum HouseholdCloudError: Error {
    case changeTokenExpired
}

/// The few CloudKit calls family sharing needs, so the sync logic can be tested
/// against an in-memory server.
@MainActor
protocol HouseholdCloud {
    func fetchChanges(since changeToken: Data?) async throws -> CloudChanges
    /// Saves only records unchanged on the server since `systemFields` were read.
    func save(_ entries: [CloudMirror.Entry], root: CloudRoot?) async throws -> (entries: [String: CloudSaveResult<CloudMirror.Entry>], root: CloudSaveResult<CloudRoot>?)
    /// Returns the names that were deleted.
    func delete(_ names: [String]) async throws -> [String]
}

@MainActor
protocol HouseholdDataSource: AnyObject {
    /// This device's household, or nil when the stores are not set up yet.
    func currentPayload() -> SharedHouseholdPayload?
    /// Replaces local data with the merged household. `changedRecords` are the records
    /// fetched in this sync, for noticing what other family members added.
    func apply(_ payload: SharedHouseholdPayload, changedRecords: [SyncRecord])
}

/// Keeps local data and the shared CloudKit zone in step: fetches what changed,
/// merges it with local data, and uploads whatever the cloud is missing.
@MainActor
final class HouseholdSyncEngine {
    enum Mode {
        case merge
        /// Used right after joining a share: the family's data replaces this device's local data.
        case adoptRemote
    }

    enum Outcome: Equatable {
        case upToDate
        case uploaded(count: Int)
    }

    private let cloud: HouseholdCloud
    private let persist: (CloudMirror) -> Void
    private(set) var mirror: CloudMirror

    init(cloud: HouseholdCloud, mirror: CloudMirror, persist: @escaping (CloudMirror) -> Void = { _ in }) {
        self.cloud = cloud
        self.mirror = mirror
        self.persist = persist
    }

    /// Returns nil when there is no local data to sync yet.
    func sync(_ dataSource: HouseholdDataSource, mode: Mode = .merge) async throws -> Outcome? {
        for attempt in 1...3 {
            let changed = try await fetchChanges()
            guard let localPayload = dataSource.currentPayload() else { return nil }

            var remotePayload = HouseholdRecords.payload(from: mirror.orderedRecords)
            let legacyPayload = mirror.root.legacyPayload.flatMap { try? JSONDecoder().decode(SharedHouseholdPayload.self, from: $0) }
            if let legacyPayload {
                remotePayload = SharedHouseholdPayload.merged(local: remotePayload, remote: legacyPayload, keepLocalOrder: true)
            }

            if !mirror.records.isEmpty || legacyPayload != nil {
                let merged = switch mode {
                case .adoptRemote: remotePayload
                case .merge: SharedHouseholdPayload.merged(local: localPayload, remote: remotePayload, keepLocalOrder: true)
                }
                dataSource.apply(merged, changedRecords: changed)
            }

            // Re-read after apply so the upload includes this device's profile and member entry.
            guard let uploadPayload = dataSource.currentPayload() else { return nil }
            let desired = HouseholdRecords.records(from: uploadPayload, updatedBy: uploadPayload.updatedBy)
            let toSave = HouseholdRecords.changes(desired: desired, current: mirror.currentRecords)
            let toDelete = HouseholdRecords.expiredDeletions(in: Array(mirror.currentRecords.values))
            let needsRootUpdate = mirror.root.schemaVersion < CloudRoot.recordsSchemaVersion

            guard !toSave.isEmpty || !toDelete.isEmpty || needsRootUpdate else { return .upToDate }

            let hadConflicts = try await save(toSave, deleting: toDelete, updatingRoot: needsRootUpdate)
            if !hadConflicts || attempt == 3 {
                return .uploaded(count: toSave.count)
            }
            // Someone else saved some of the same records in between; merge their versions and retry.
        }
        return .upToDate
    }

    /// Fetches records changed since the last sync into the mirror and returns them.
    private func fetchChanges() async throws -> [SyncRecord] {
        var changed: [SyncRecord] = []
        var moreComing = true

        while moreComing {
            let changes: CloudChanges
            do {
                changes = try await cloud.fetchChanges(since: mirror.changeToken)
            } catch HouseholdCloudError.changeTokenExpired where mirror.changeToken != nil {
                mirror = CloudMirror(zoneKey: mirror.zoneKey)
                changed = []
                continue
            }

            if let root = changes.root {
                ingest(root)
            }
            for entry in changes.entries {
                mirror.records[entry.record.name] = entry
                changed.append(entry.record)
            }
            for name in changes.deletedNames {
                mirror.records[name] = nil
            }
            mirror.changeToken = changes.changeToken
            moreComing = changes.moreComing
        }

        persist(mirror)
        return changed
    }

    private func ingest(_ root: CloudRoot) {
        let legacy = mirror.root.legacyPayload
        mirror.root = root
        if root.schemaVersion >= CloudRoot.recordsSchemaVersion {
            mirror.root.legacyPayload = nil
        } else if root.legacyPayload == nil {
            // Keep an old payload already fetched but not yet migrated.
            mirror.root.legacyPayload = legacy
        }
    }

    /// Saves records only if nobody changed them since this device last saw them.
    /// Returns true when some were changed elsewhere; their newer versions are then in the mirror.
    private func save(_ records: [SyncRecord], deleting expired: [String], updatingRoot: Bool) async throws -> Bool {
        let entries = records.map { record in
            CloudMirror.Entry(record: record, systemFields: mirror.records[record.name]?.systemFields, createdAt: mirror.records[record.name]?.createdAt)
        }
        let root = updatingRoot
            ? CloudRoot(systemFields: mirror.root.systemFields, schemaVersion: CloudRoot.recordsSchemaVersion, legacyPayload: nil)
            : nil

        var hadConflicts = false
        var firstError: Error?
        let results = try await cloud.save(entries, root: root)

        switch results.root {
        case .saved(let saved):
            mirror.root = saved
        case .conflict(let server):
            hadConflicts = true
            server.map(ingest)
        case .failed(let error):
            firstError = error
        case nil:
            break
        }

        for (name, result) in results.entries {
            switch result {
            case .saved(let saved):
                mirror.records[name] = saved
            case .conflict(let server):
                hadConflicts = true
                if let server {
                    mirror.records[name] = server
                }
            case .failed(let error):
                firstError = firstError ?? error
            }
        }

        if !expired.isEmpty {
            for name in try await cloud.delete(expired) {
                mirror.records[name] = nil
            }
        }

        persist(mirror)
        if let firstError { throw firstError }
        return hadConflicts
    }
}
