import BackgroundTasks
import CloudKit
import SwiftUI
import UIKit
import UserNotifications

struct SharedHouseholdPayload: Codable {
    var schemaVersion: Int
    var updatedAt: Date
    var updatedBy: String
    var tasks: [FamilyTask]
    var familyMembers: [String]
    var profiles: [SharedMemberProfile]
    var shopping: ShoppingPayload
    var recurringTasks: [RecurringTask]
    var mealPlan: MealPlanPayload
    var ideas: [IdeaNote]
    var healthSnapshots: [HealthSnapshot]

    init(
        schemaVersion: Int = 1,
        updatedAt: Date = Date(),
        updatedBy: String = "",
        tasks: [FamilyTask] = [],
        familyMembers: [String] = [],
        profiles: [SharedMemberProfile] = [],
        shopping: ShoppingPayload = ShoppingPayload(shops: [], items: []),
        recurringTasks: [RecurringTask] = [],
        mealPlan: MealPlanPayload = MealPlanPayload(mealIdeas: [], plannedMeals: []),
        ideas: [IdeaNote] = [],
        healthSnapshots: [HealthSnapshot] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.tasks = tasks
        self.familyMembers = familyMembers
        self.profiles = profiles
        self.shopping = shopping
        self.recurringTasks = recurringTasks
        self.mealPlan = mealPlan
        self.ideas = ideas
        self.healthSnapshots = healthSnapshots
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case updatedBy
        case tasks
        case familyMembers
        case profiles
        case shopping
        case recurringTasks
        case mealPlan
        case ideas
        case healthSnapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date()
        updatedBy = (try? container.decode(String.self, forKey: .updatedBy)) ?? ""
        tasks = (try? container.decode([FamilyTask].self, forKey: .tasks)) ?? []
        familyMembers = (try? container.decode([String].self, forKey: .familyMembers)) ?? []
        profiles = (try? container.decode([SharedMemberProfile].self, forKey: .profiles)) ?? []
        shopping = (try? container.decode(ShoppingPayload.self, forKey: .shopping)) ?? ShoppingPayload(shops: [], items: [])
        recurringTasks = (try? container.decode([RecurringTask].self, forKey: .recurringTasks)) ?? []
        mealPlan = (try? container.decode(MealPlanPayload.self, forKey: .mealPlan)) ?? MealPlanPayload(mealIdeas: [], plannedMeals: [])
        ideas = (try? container.decode([IdeaNote].self, forKey: .ideas)) ?? []
        healthSnapshots = (try? container.decode([HealthSnapshot].self, forKey: .healthSnapshots)) ?? []
    }
}

struct SharedMemberProfile: Codable, Identifiable, Equatable {
    static let storageKey = "familySharing.memberProfiles"

    var email: String
    var initials: String
    var imageData: Data?
    var updatedAt: Date

    var id: String { normalizedEmail }

    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func loadProfiles() -> [SharedMemberProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([SharedMemberProfile].self, from: data) else {
            return []
        }

        return profiles
    }

    static func saveProfiles(_ profiles: [SharedMemberProfile]) {
        guard let data = try? JSONEncoder().encode(deduplicated(profiles)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func profile(for email: String, in profiles: [SharedMemberProfile] = loadProfiles()) -> SharedMemberProfile? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { return nil }
        return profiles.first { $0.normalizedEmail == normalizedEmail }
    }

    static func currentProfile() -> SharedMemberProfile? {
        let defaults = UserDefaults.standard
        let email = (defaults.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isValidEmail(email) else { return nil }

        let initials = (defaults.string(forKey: "profile.initials") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let imageData = compressedImageData(from: defaults.data(forKey: "profile.imageData") ?? Data())

        return SharedMemberProfile(
            email: email,
            initials: initials,
            imageData: imageData,
            updatedAt: Date()
        )
    }

    static func profilesForUpload() -> [SharedMemberProfile] {
        var profiles = loadProfiles()
        if let currentProfile = currentProfile() {
            profiles = merge(existing: profiles, incoming: [currentProfile])
            saveProfiles(profiles)
        }
        return profiles
    }

    static func mergeAndSave(_ incoming: [SharedMemberProfile]) {
        let merged = merge(existing: loadProfiles(), incoming: incoming)
        saveProfiles(merged)
    }

    static func merge(existing: [SharedMemberProfile], incoming: [SharedMemberProfile]) -> [SharedMemberProfile] {
        deduplicated(existing + incoming)
    }

    private static func deduplicated(_ profiles: [SharedMemberProfile]) -> [SharedMemberProfile] {
        var profilesByEmail: [String: SharedMemberProfile] = [:]

        for profile in profiles {
            let email = profile.normalizedEmail
            guard isValidEmail(email) else { continue }

            if let existing = profilesByEmail[email], existing.updatedAt > profile.updatedAt {
                continue
            }

            var normalized = profile
            normalized.email = email
            profilesByEmail[email] = normalized
        }

        return profilesByEmail.values.sorted { lhs, rhs in
            lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }
    }

    private static func compressedImageData(from data: Data) -> Data? {
        guard !data.isEmpty, let image = UIImage(data: data) else { return nil }

        let maxSide: CGFloat = 180
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > 0 ? min(1, maxSide / largestSide) : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.72)
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Notification.Name {
    static let familyDataDidChange = Notification.Name("FamilyDataDidChange")
    static let sharedTasksDidArrive = Notification.Name("SharedTasksDidArrive")
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
    private var suppressNextSharedTaskArrivalNotification = false
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

            let sharedTaskArrival = sharedTaskArrival(from: payload)
            apply(payload)
            postSharedTaskArrival(sharedTaskArrival)
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
                suppressNextSharedTaskArrivalNotification = true
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
            suppressNextSharedTaskArrivalNotification = true
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
            profiles: SharedMemberProfile.profilesForUpload(),
            shopping: organizerStore.exportShoppingPayload(),
            recurringTasks: organizerStore.recurringTasks,
            mealPlan: organizerStore.exportMealPlanPayload(),
            ideas: organizerStore.exportIdeas(),
            healthSnapshots: organizerStore.exportHealthSnapshots()
        )
    }

    private func apply(_ payload: SharedHouseholdPayload) {
        SharedMemberProfile.mergeAndSave(payload.profiles)
        taskStore?.applySharedData(tasks: payload.tasks, familyMembers: payload.familyMembers)
        organizerStore?.applySharedData(
            shopping: payload.shopping,
            recurringTasks: payload.recurringTasks,
            mealPlan: payload.mealPlan,
            ideas: payload.ideas,
            healthSnapshots: payload.healthSnapshots
        )
    }

    private func sharedTaskArrival(from payload: SharedHouseholdPayload) -> (count: Int, title: String?)? {
        if suppressNextSharedTaskArrivalNotification {
            suppressNextSharedTaskArrivalNotification = false
            return nil
        }

        guard let taskStore else { return nil }

        let currentEmail = (defaults.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let updatedBy = payload.updatedBy
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if !currentEmail.isEmpty, !updatedBy.isEmpty, currentEmail == updatedBy {
            return nil
        }

        let existingTaskIDs = Set(taskStore.exportTasks().map(\.id))
        let newTasks = payload.tasks.filter { !existingTaskIDs.contains($0.id) }
        guard !newTasks.isEmpty else { return nil }

        return (newTasks.count, newTasks.first?.title)
    }

    private func postSharedTaskArrival(_ arrival: (count: Int, title: String?)?) {
        guard let arrival else { return }

        NotificationCenter.default.post(
            name: .sharedTasksDidArrive,
            object: self,
            userInfo: [
                "count": arrival.count,
                "title": arrival.title ?? ""
            ]
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
            return "Need to clean up some space in your iCloud to share."
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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        HealthSyncCoordinator.shared.registerBackgroundRefresh()
        HealthSyncCoordinator.shared.scheduleDailyRefresh()
        return true
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharedHouseholdStore.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        HealthSyncCoordinator.shared.scheduleDailyRefresh()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier

        if identifier.hasPrefix("familytasks.test.") || identifier.hasPrefix("familytasks.sharedTaskArrival.") {
            return [.banner, .list, .sound, .badge]
        }

        if identifier.hasPrefix("familytasks.todayDigest.") ||
            identifier.hasPrefix("familytasks.dueSoon.") ||
            identifier.hasPrefix("familytasks.recurringDueSoon.") {
            return [.list, .badge]
        }

        return [.banner, .list, .sound, .badge]
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
