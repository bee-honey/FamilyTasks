import BackgroundTasks
import CloudKit
import SwiftUI
import UIKit
import UserNotifications

struct SharedHouseholdPayload: Codable {
    static let currentSchemaVersion = 2

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
    var deletions: [String: Date]
    var memberAdditions: [String: Date]

    init(
        schemaVersion: Int = SharedHouseholdPayload.currentSchemaVersion,
        updatedAt: Date = Date(),
        updatedBy: String = "",
        tasks: [FamilyTask] = [],
        familyMembers: [String] = [],
        profiles: [SharedMemberProfile] = [],
        shopping: ShoppingPayload = ShoppingPayload(shops: [], items: []),
        recurringTasks: [RecurringTask] = [],
        mealPlan: MealPlanPayload = MealPlanPayload(mealIdeas: [], plannedMeals: []),
        ideas: [IdeaNote] = [],
        healthSnapshots: [HealthSnapshot] = [],
        deletions: [String: Date] = [:],
        memberAdditions: [String: Date] = [:]
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
        self.deletions = deletions
        self.memberAdditions = memberAdditions
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
        case deletions
        case memberAdditions
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
        deletions = (try? container.decode([String: Date].self, forKey: .deletions)) ?? [:]
        memberAdditions = (try? container.decode([String: Date].self, forKey: .memberAdditions)) ?? [:]
    }

    /// Merges two copies of the household item by item: the newer `updatedAt` wins,
    /// and anything deleted after its last edit stays deleted.
    static func merged(local: SharedHouseholdPayload, remote: SharedHouseholdPayload) -> SharedHouseholdPayload {
        let deletions = SyncLedger.union(local.deletions, remote.deletions)
        let memberAdditions = SyncLedger.union(local.memberAdditions, remote.memberAdditions)

        let localOrderDate = local.shopping.orderUpdatedAt ?? .distantPast
        let remoteOrderDate = remote.shopping.orderUpdatedAt ?? .distantPast
        let localShopOrderWins = localOrderDate > remoteOrderDate

        return SharedHouseholdPayload(
            updatedAt: Date(),
            updatedBy: local.updatedBy,
            tasks: mergeItems(local.tasks, remote.tasks, deletions: deletions),
            familyMembers: mergeMembers(local.familyMembers, remote.familyMembers, deletions: deletions, additions: memberAdditions),
            profiles: SharedMemberProfile.merge(existing: remote.profiles, incoming: local.profiles),
            shopping: ShoppingPayload(
                shops: mergeItems(local.shopping.shops, remote.shopping.shops, deletions: deletions, localOrderWins: localShopOrderWins),
                items: mergeItems(local.shopping.items, remote.shopping.items, deletions: deletions),
                orderUpdatedAt: max(localOrderDate, remoteOrderDate) == .distantPast ? nil : max(localOrderDate, remoteOrderDate)
            ),
            recurringTasks: mergeItems(local.recurringTasks, remote.recurringTasks, deletions: deletions),
            mealPlan: MealPlanPayload(
                mealIdeas: mergeItems(local.mealPlan.mealIdeas, remote.mealPlan.mealIdeas, deletions: deletions),
                plannedMeals: mergeItems(local.mealPlan.plannedMeals, remote.mealPlan.plannedMeals, deletions: deletions)
            ),
            ideas: mergeItems(local.ideas, remote.ideas, deletions: deletions),
            healthSnapshots: mergeItems(local.healthSnapshots, remote.healthSnapshots, deletions: deletions),
            deletions: deletions,
            memberAdditions: memberAdditions
        )
    }

    private static func mergeItems<Item: SyncMergeable>(
        _ local: [Item],
        _ remote: [Item],
        deletions: [String: Date],
        localOrderWins: Bool = false
    ) -> [Item] {
        var winners: [String: Item] = [:]
        for item in remote {
            winners[item.syncID] = item
        }
        for item in local {
            if let current = winners[item.syncID], current.updatedAt >= item.updatedAt {
                continue
            }
            winners[item.syncID] = item
        }

        let orderedIDs = (localOrderWins ? local + remote : remote + local).map(\.syncID)
        var seen = Set<String>()
        return orderedIDs.compactMap { id in
            guard seen.insert(id).inserted, let item = winners[id] else { return nil }
            if let deletedAt = deletions[id], deletedAt >= item.updatedAt {
                return nil
            }
            return item
        }
    }

    private static func mergeMembers(
        _ local: [String],
        _ remote: [String],
        deletions: [String: Date],
        additions: [String: Date]
    ) -> [String] {
        let members = Set((local + remote).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return members
            .filter { member in
                guard let deletedAt = deletions[SyncLedger.memberKey(member)] else { return true }
                guard let addedAt = additions[SyncLedger.memberKey(member)] else { return false }
                return addedAt > deletedAt
            }
            .sorted()
    }
}

protocol SyncMergeable {
    var syncID: String { get }
    var updatedAt: Date { get }
}

extension FamilyTask: SyncMergeable { var syncID: String { id.uuidString } }
extension Shop: SyncMergeable { var syncID: String { id.uuidString } }
extension ShoppingItem: SyncMergeable { var syncID: String { id.uuidString } }
extension RecurringTask: SyncMergeable { var syncID: String { id.uuidString } }
extension MealIdea: SyncMergeable { var syncID: String { id.uuidString } }
extension PlannedMeal: SyncMergeable { var syncID: String { id.uuidString } }
extension IdeaNote: SyncMergeable { var syncID: String { id.uuidString } }
extension HealthSnapshot: SyncMergeable { var syncID: String { id } }

/// Remembers what this device deleted (and which family members it re-added) so a
/// merge with an older copy of the household does not bring removed items back.
@MainActor
final class SyncLedger {
    static let shared = SyncLedger()

    private(set) var deletions: [String: Date] = [:]
    private(set) var memberAdditions: [String: Date] = [:]

    private let storageURL = URL.documentsDirectory.appendingPathComponent("family-sync-ledger.json")
    private static let retention: TimeInterval = 180 * 86_400

    private struct Stored: Codable {
        var deletions: [String: Date]
        var memberAdditions: [String: Date]
    }

    private init() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        deletions = stored.deletions
        memberAdditions = stored.memberAdditions
    }

    nonisolated static func memberKey(_ email: String) -> String {
        "member:\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    nonisolated static func union(_ lhs: [String: Date], _ rhs: [String: Date]) -> [String: Date] {
        let cutoff = Date().addingTimeInterval(-retention)
        return lhs.merging(rhs, uniquingKeysWith: max).filter { $0.value >= cutoff }
    }

    func recordRemovals<Item: SyncMergeable>(from oldItems: [Item], to newItems: [Item]) {
        let remaining = Set(newItems.map(\.syncID))
        let removed = oldItems.map(\.syncID).filter { !remaining.contains($0) }
        guard !removed.isEmpty else { return }
        let now = Date()
        removed.forEach { deletions[$0] = now }
        save()
    }

    func recordMemberRemoved(_ email: String) {
        deletions[Self.memberKey(email)] = Date()
        save()
    }

    func recordMemberAdded(_ email: String) {
        memberAdditions[Self.memberKey(email)] = Date()
        save()
    }

    func apply(deletions incomingDeletions: [String: Date], memberAdditions incomingAdditions: [String: Date]) {
        deletions = Self.union(deletions, incomingDeletions)
        memberAdditions = Self.union(memberAdditions, incomingAdditions)
        save()
    }

    private func save() {
        let stored = Stored(deletions: deletions, memberAdditions: memberAdditions)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storageURL, options: [.atomic])
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
        let imageData = defaults.data(forKey: "profile.imageData").flatMap { data in
            data.count <= maxStoredImageBytes ? data : compressedImageData(from: data)
        }

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

    /// Photos at or under this size have already been scaled down to avatar size.
    static let maxStoredImageBytes = 64 * 1_024

    /// Older versions stored the full-size picked photo in UserDefaults; scale it down once.
    static func shrinkStoredProfileImageIfNeeded() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "profile.imageData"),
              data.count > maxStoredImageBytes,
              let compressed = compressedImageData(from: data) else { return }
        defaults.set(compressed, forKey: "profile.imageData")
    }

    /// Scales a photo down to avatar size (180pt longest side) as JPEG.
    static func compressedImageData(from data: Data) -> Data? {
        guard !data.isEmpty, let image = UIImage(data: data) else { return nil }

        let maxSide: CGFloat = 180
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > 0 ? min(1, maxSide / largestSide) : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Fixed 2x scale keeps the output small (~360px) regardless of the device's screen scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
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
    /// Set whenever this device has changes the shared record has not received yet
    /// (including items added through Siri while the app was not running).
    static let pendingLocalChangesKey = "familySharing.hasLocalIntentChanges"
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

    // Created on first use so launching (and unit tests, which run unsigned) does not require CloudKit.
    private lazy var container = CKContainer.default()
    private weak var taskStore: TaskStore?
    private weak var organizerStore: OrganizerStore?
    private var changeObserver: NSObjectProtocol?
    private var pendingUploadTask: Task<Void, Never>?
    private var suppressNextSharedTaskArrivalNotification = false
    private var syncChain: Task<Void, Never>?
    private var localChangeGeneration = 0
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
        guard self.taskStore !== taskStore || self.organizerStore !== organizerStore else { return }
        self.taskStore = taskStore
        self.organizerStore = organizerStore

        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .familyDataDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.noteLocalChange()
                }
            }
        }

        if isSharingConfigured {
            statusMessage = "Family sharing enabled"
            taskStore.ensureProfileMember()
            Task { await refreshFromCloud() }
        }
    }

    /// Pulls the shared household, merges it with local changes, and uploads the
    /// result if this device has anything the shared copy is missing.
    func refreshFromCloud() async {
        await synchronize(mode: .mergeAndUploadIfNeeded)
    }

    /// Merges with the shared household and always writes the result back.
    func uploadNow() async {
        await synchronize(mode: .mergeAndUpload)
    }

    func syncOnAppActivation() async {
        guard isSharingConfigured else { return }
        await refreshFromCloud()
    }

    private enum SyncMode {
        case mergeAndUploadIfNeeded
        case mergeAndUpload
        /// Used right after joining a share: the family's data replaces this device's local data.
        case adoptRemoteAndUpload
    }

    private var hasPendingLocalChanges: Bool {
        get { defaults.bool(forKey: FamilySharingDefaults.pendingLocalChangesKey) }
        set { defaults.set(newValue, forKey: FamilySharingDefaults.pendingLocalChangesKey) }
    }

    private func noteLocalChange() {
        localChangeGeneration += 1
        hasPendingLocalChanges = true
        scheduleUpload()
    }

    /// Runs sync operations one at a time so overlapping triggers cannot interleave
    /// their fetch/merge/save steps.
    private func synchronize(mode: SyncMode) async {
        let previous = syncChain
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performSync(mode: mode)
        }
        syncChain = operation
        await operation.value
    }

    private func performSync(mode: SyncMode) async {
        guard let recordID = storedRootRecordID else {
            statusMessage = "Not sharing yet"
            return
        }
        guard taskStore != nil, organizerStore != nil else { return }

        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        do {
            for attempt in 1...3 {
                let record = try await fetchRootRecord(recordID)
                let remotePayload = record.flatMap(decodePayload(from:))
                guard let localPayload = currentPayload() else { return }
                let changeGeneration = localChangeGeneration

                let merged: SharedHouseholdPayload
                if let remotePayload {
                    if case .adoptRemoteAndUpload = mode {
                        merged = remotePayload
                    } else {
                        merged = SharedHouseholdPayload.merged(local: localPayload, remote: remotePayload)
                    }
                    let arrival = sharedTaskArrival(from: remotePayload)
                    apply(merged)
                    postSharedTaskArrival(arrival)
                } else {
                    merged = localPayload
                }

                let needsUpload: Bool
                switch mode {
                case .mergeAndUploadIfNeeded:
                    needsUpload = remotePayload == nil || hasPendingLocalChanges
                case .mergeAndUpload, .adoptRemoteAndUpload:
                    needsUpload = true
                }

                guard needsUpload else {
                    if let remotePayload {
                        statusMessage = "Updated \(remotePayload.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                    }
                    return
                }

                // Re-read after apply so the upload includes this device's profile and member entry.
                guard var uploadPayload = currentPayload() else { return }
                uploadPayload.updatedAt = Date()
                let target = record ?? CKRecord(recordType: CloudKitKey.rootRecordType, recordID: recordID)
                encode(uploadPayload, into: target)

                do {
                    _ = try await database.save(target)
                    if changeGeneration == localChangeGeneration {
                        hasPendingLocalChanges = false
                    }
                    statusMessage = "Shared \(uploadPayload.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                    return
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                    // Someone else saved in between; fetch their version and merge again.
                    continue
                }
            }
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not sync family sharing"
        }
    }

    private func fetchRootRecord(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem && databaseScope == .private {
            return nil
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
                await synchronize(mode: .adoptRemoteAndUpload)
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
            await synchronize(mode: .adoptRemoteAndUpload)
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
            if let localPayload = currentPayload() {
                let payload = decodePayload(from: record)
                    .map { SharedHouseholdPayload.merged(local: localPayload, remote: $0) } ?? localPayload
                apply(payload)
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
            healthSnapshots: organizerStore.exportHealthSnapshots(),
            deletions: SyncLedger.shared.deletions,
            memberAdditions: SyncLedger.shared.memberAdditions
        )
    }

    private func apply(_ payload: SharedHouseholdPayload) {
        SyncLedger.shared.apply(deletions: payload.deletions, memberAdditions: payload.memberAdditions)
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
        let newTasks = payload.tasks.filter { task in
            !existingTaskIDs.contains(task.id) && task.isVisible(to: currentEmail)
        }
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
        SharedMemberProfile.shrinkStoredProfileImageIfNeeded()
        // Wire the shared stores up at launch (not on first view appearance) so
        // background launches, such as the daily Health refresh, can sync too.
        MainActor.assumeIsolated {
            SharedHouseholdStore.shared.configure(taskStore: .shared, organizerStore: .shared)
            NotificationScheduler.shared.configure(taskStore: .shared, organizerStore: .shared)
        }
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
