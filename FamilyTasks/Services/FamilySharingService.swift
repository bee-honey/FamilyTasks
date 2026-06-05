import CloudKit
import SwiftUI
import UIKit

struct SharedHouseholdPayload: Codable {
    var schemaVersion: Int
    var updatedAt: Date
    var updatedBy: String
    var tasks: [FamilyTask]
    var familyMembers: [String]
    var shopping: ShoppingPayload
    var recurringTasks: [RecurringTask]
    var mealPlan: MealPlanPayload

    init(
        schemaVersion: Int = 1,
        updatedAt: Date = Date(),
        updatedBy: String = "",
        tasks: [FamilyTask] = [],
        familyMembers: [String] = [],
        shopping: ShoppingPayload = ShoppingPayload(shops: [], items: []),
        recurringTasks: [RecurringTask] = [],
        mealPlan: MealPlanPayload = MealPlanPayload(mealIdeas: [], plannedMeals: [])
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.tasks = tasks
        self.familyMembers = familyMembers
        self.shopping = shopping
        self.recurringTasks = recurringTasks
        self.mealPlan = mealPlan
    }
}

extension Notification.Name {
    static let familyDataDidChange = Notification.Name("FamilyDataDidChange")
}

enum FamilySharingDefaults {
    static let localIntentChangeFlagKey = "familySharing.hasLocalIntentChanges"
}

struct PreparedCloudShare: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

@MainActor
final class SharedHouseholdStore: ObservableObject {
    static let shared = SharedHouseholdStore()

    @Published private(set) var isSyncing = false
    @Published private(set) var statusMessage = "Not sharing yet"
    @Published private(set) var lastErrorMessage: String?

    private let container = CKContainer.default()
    private weak var taskStore: TaskStore?
    private weak var organizerStore: OrganizerStore?
    private var changeObserver: NSObjectProtocol?
    private var pendingUploadTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let recordName = "familySharing.recordName"
        static let zoneName = "familySharing.zoneName"
        static let ownerName = "familySharing.ownerName"
        static let databaseScope = "familySharing.databaseScope"
    }

    private enum RecordKey {
        static let name = "name"
        static let payload = "payload"
        static let updatedAt = "updatedAt"
        static let updatedBy = "updatedBy"
    }

    private enum CloudKitKey {
        static let rootRecordType = "FamilyTaskList"
        static let sharedZoneName = "FamilyTasksSharedZone"
    }

    private init() {}

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var isSharingConfigured: Bool {
        storedRootRecordID != nil
    }

    func configure(taskStore: TaskStore, organizerStore: OrganizerStore) {
        self.taskStore = taskStore
        self.organizerStore = organizerStore

        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .familyDataDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleUpload()
                }
            }
        }

        if isSharingConfigured {
            statusMessage = "Family sharing enabled"
            taskStore.ensureProfileMember()
            Task { await refreshFromCloud() }
        }
    }

    func refreshFromCloud() async {
        guard let recordID = storedRootRecordID else {
            statusMessage = "Not sharing yet"
            return
        }

        isSyncing = true
        lastErrorMessage = nil

        do {
            let record = try await database.record(for: recordID)
            guard let payload = decodePayload(from: record) else {
                statusMessage = "Shared list is empty"
                isSyncing = false
                return
            }

            apply(payload)
            taskStore?.ensureProfileMember()
            statusMessage = "Updated \(payload.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not refresh sharing"
        }

        isSyncing = false
    }

    func uploadNow() async {
        guard let recordID = storedRootRecordID else { return }
        guard let payload = currentPayload() else { return }

        isSyncing = true
        lastErrorMessage = nil

        do {
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch {
                record = CKRecord(recordType: CloudKitKey.rootRecordType, recordID: recordID)
            }

            encode(payload, into: record)
            _ = try await database.save(record)
            statusMessage = "Shared \(payload.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not update shared list"
        }

        isSyncing = false
    }

    func syncOnAppActivation() async {
        guard isSharingConfigured else { return }

        if defaults.bool(forKey: FamilySharingDefaults.localIntentChangeFlagKey) {
            await uploadNow()
            if lastErrorMessage == nil {
                defaults.set(false, forKey: FamilySharingDefaults.localIntentChangeFlagKey)
            }
        } else {
            await refreshFromCloud()
        }
    }

    func prepareCloudShare() async throws -> PreparedCloudShare {
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        do {
            let rootRecord = try await rootRecordForSharing()
            let share: CKShare
            if let existingShare = try await existingShare(for: rootRecord) {
                share = existingShare
            } else {
                share = CKShare(rootRecord: rootRecord)
                share[CKShare.SystemFieldKey.title] = "Family Tasks" as CKRecordValue
                share.publicPermission = .none
                try await save(records: [rootRecord, share], in: container.privateCloudDatabase)
            }

            store(recordID: rootRecord.recordID, databaseScope: .private)
            statusMessage = "Family sharing enabled"
            return PreparedCloudShare(share: share, container: container)
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not start sharing"
            throw error
        }
    }

    func acceptShare(metadata: CKShare.Metadata) {
        Task {
            isSyncing = true
            lastErrorMessage = nil

            do {
                try await accept(metadata)
                store(recordID: metadata.rootRecordID, databaseScope: .shared)
                statusMessage = "Joined shared family list"
                await refreshFromCloud()
                await uploadNow()
            } catch {
                lastErrorMessage = userFacingMessage(for: error)
                statusMessage = "Could not join shared list"
            }

            isSyncing = false
        }
    }

    func acceptShareLink(_ link: String) async {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shareURL = URL(string: trimmedLink),
              shareURL.scheme?.lowercased().hasPrefix("http") == true else {
            lastErrorMessage = "Paste a valid iCloud invite link."
            statusMessage = "Could not join shared list"
            return
        }

        isSyncing = true
        lastErrorMessage = nil

        do {
            let metadata = try await shareMetadata(for: shareURL)
            try await accept(metadata)
            store(recordID: metadata.rootRecordID, databaseScope: .shared)
            statusMessage = "Joined shared family list"
            await refreshFromCloud()
            await uploadNow()
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not join shared list"
        }

        isSyncing = false
    }

    private var databaseScope: CKDatabase.Scope {
        let rawValue = defaults.integer(forKey: DefaultsKey.databaseScope)
        return CKDatabase.Scope(rawValue: rawValue) ?? .private
    }

    private var database: CKDatabase {
        switch databaseScope {
        case .shared:
            container.sharedCloudDatabase
        default:
            container.privateCloudDatabase
        }
    }

    private var storedRootRecordID: CKRecord.ID? {
        guard let recordName = defaults.string(forKey: DefaultsKey.recordName),
              let zoneName = defaults.string(forKey: DefaultsKey.zoneName),
              let ownerName = defaults.string(forKey: DefaultsKey.ownerName) else {
            return nil
        }

        return CKRecord.ID(recordName: recordName, zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName))
    }

    private func store(recordID: CKRecord.ID, databaseScope: CKDatabase.Scope) {
        defaults.set(recordID.recordName, forKey: DefaultsKey.recordName)
        defaults.set(recordID.zoneID.zoneName, forKey: DefaultsKey.zoneName)
        defaults.set(recordID.zoneID.ownerName, forKey: DefaultsKey.ownerName)
        defaults.set(databaseScope.rawValue, forKey: DefaultsKey.databaseScope)
    }

    private func scheduleUpload() {
        guard isSharingConfigured else { return }

        pendingUploadTask?.cancel()
        pendingUploadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.uploadNow()
        }
    }

    private func rootRecordForSharing() async throws -> CKRecord {
        if let recordID = storedRootRecordID {
            let record = try await container.privateCloudDatabase.record(for: recordID)
            if let payload = currentPayload() {
                encode(payload, into: record)
            }
            return record
        }

        try await ensurePrivateSharingZone()

        let zoneID = CKRecordZone.ID(zoneName: CloudKitKey.sharedZoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitKey.rootRecordType, recordID: recordID)
        record[RecordKey.name] = "Family Tasks" as CKRecordValue
        if let payload = currentPayload() {
            encode(payload, into: record)
        }
        let saved = try await container.privateCloudDatabase.save(record)
        store(recordID: saved.recordID, databaseScope: .private)
        return saved
    }

    private func currentPayload() -> SharedHouseholdPayload? {
        guard let taskStore, let organizerStore else { return nil }
        taskStore.ensureProfileMember()

        return SharedHouseholdPayload(
            updatedAt: Date(),
            updatedBy: UserDefaults.standard.string(forKey: "profile.email") ?? "",
            tasks: taskStore.exportTasks(),
            familyMembers: taskStore.exportFamilyMembers(),
            shopping: organizerStore.exportShoppingPayload(),
            recurringTasks: organizerStore.recurringTasks,
            mealPlan: organizerStore.exportMealPlanPayload()
        )
    }

    private func apply(_ payload: SharedHouseholdPayload) {
        taskStore?.applySharedData(tasks: payload.tasks, familyMembers: payload.familyMembers)
        organizerStore?.applySharedData(
            shopping: payload.shopping,
            recurringTasks: payload.recurringTasks,
            mealPlan: payload.mealPlan
        )
    }

    private func encode(_ payload: SharedHouseholdPayload, into record: CKRecord) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        record[RecordKey.name] = "Family Tasks" as CKRecordValue
        record[RecordKey.payload] = data as NSData
        record[RecordKey.updatedAt] = payload.updatedAt as NSDate
        record[RecordKey.updatedBy] = payload.updatedBy as NSString
    }

    private func decodePayload(from record: CKRecord) -> SharedHouseholdPayload? {
        let data: Data?
        if let value = record[RecordKey.payload] as? Data {
            data = value
        } else if let value = record[RecordKey.payload] as? NSData {
            data = value as Data
        } else {
            data = nil
        }

        guard let data else { return nil }
        return try? JSONDecoder().decode(SharedHouseholdPayload.self, from: data)
    }

    private func userFacingMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }

        switch cloudError.code {
        case .quotaExceeded:
            return "iCloud storage is full. Free up iCloud storage or upgrade the storage plan, then try sharing again."
        case .notAuthenticated:
            return "Sign in to iCloud on this device, then try sharing again."
        case .permissionFailure:
            return "This iCloud share does not allow changes from this device."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return "iCloud is temporarily unavailable. Check your connection and try again."
        default:
            return cloudError.localizedDescription
        }
    }

    private func shareMetadata(for shareURL: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            var fetchedMetadata: CKShare.Metadata?

            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.shouldFetchRootRecord = true
            operation.perShareMetadataBlock = { _, metadata, _ in
                fetchedMetadata = metadata
            }
            operation.fetchShareMetadataCompletionBlock = { error in
                if let fetchedMetadata {
                    continuation.resume(returning: fetchedMetadata)
                    return
                }

                continuation.resume(throwing: error ?? NSError(
                    domain: "FamilyTasks.CloudSharing",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not read the iCloud invite link."]
                ))
            }
            operation.qualityOfService = .userInitiated
            container.add(operation)
        }
    }

    private func save(records: [CKRecord], in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func existingShare(for rootRecord: CKRecord) async throws -> CKShare? {
        guard let shareReference = rootRecord.share else { return nil }
        return try await container.privateCloudDatabase.record(for: shareReference.recordID) as? CKShare
    }

    private func ensurePrivateSharingZone() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let zone = CKRecordZone(zoneName: CloudKitKey.sharedZoneName)
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    private func accept(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            CKContainer(identifier: metadata.containerIdentifier).add(operation)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharedHouseholdStore.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let preparedShare: PreparedCloudShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: preparedShare.share, container: preparedShare.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
