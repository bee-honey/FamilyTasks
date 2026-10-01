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
    ///
    /// `keepLocalOrder` lists local items first; use it when the remote order carries no
    /// meaning (records fetched from CloudKit come back unordered). Shop order always
    /// follows whichever side reordered shops last.
    static func merged(local: SharedHouseholdPayload, remote: SharedHouseholdPayload, keepLocalOrder: Bool = false) -> SharedHouseholdPayload {
        let deletions = SyncLedger.union(local.deletions, remote.deletions)
        let memberAdditions = SyncLedger.union(local.memberAdditions, remote.memberAdditions)

        let localOrderDate = local.shopping.orderUpdatedAt ?? .distantPast
        let remoteOrderDate = remote.shopping.orderUpdatedAt ?? .distantPast
        let localShopOrderWins = localOrderDate > remoteOrderDate

        return SharedHouseholdPayload(
            updatedAt: Date(),
            updatedBy: local.updatedBy,
            tasks: mergeItems(local.tasks, remote.tasks, deletions: deletions, localOrderWins: keepLocalOrder),
            familyMembers: mergeMembers(local.familyMembers, remote.familyMembers, deletions: deletions, additions: memberAdditions),
            profiles: SharedMemberProfile.merge(existing: remote.profiles, incoming: local.profiles),
            shopping: ShoppingPayload(
                shops: mergeItems(local.shopping.shops, remote.shopping.shops, deletions: deletions, localOrderWins: localShopOrderWins),
                items: mergeItems(local.shopping.items, remote.shopping.items, deletions: deletions, localOrderWins: keepLocalOrder),
                orderUpdatedAt: max(localOrderDate, remoteOrderDate) == .distantPast ? nil : max(localOrderDate, remoteOrderDate)
            ),
            recurringTasks: mergeItems(local.recurringTasks, remote.recurringTasks, deletions: deletions, localOrderWins: keepLocalOrder),
            mealPlan: MealPlanPayload(
                mealIdeas: mergeItems(local.mealPlan.mealIdeas, remote.mealPlan.mealIdeas, deletions: deletions, localOrderWins: keepLocalOrder),
                plannedMeals: mergeItems(local.mealPlan.plannedMeals, remote.mealPlan.plannedMeals, deletions: deletions, localOrderWins: keepLocalOrder)
            ),
            ideas: mergeItems(local.ideas, remote.ideas, deletions: deletions, localOrderWins: keepLocalOrder),
            healthSnapshots: mergeItems(local.healthSnapshots, remote.healthSnapshots, deletions: deletions, localOrderWins: keepLocalOrder),
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
    nonisolated static let retention: TimeInterval = 180 * 86_400

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
        let mergedDeletions = Self.union(deletions, incomingDeletions)
        let mergedAdditions = Self.union(memberAdditions, incomingAdditions)
        guard mergedDeletions != deletions || mergedAdditions != memberAdditions else { return }
        deletions = mergedDeletions
        memberAdditions = mergedAdditions
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
        if var currentProfile = currentProfile() {
            // Keep the stored timestamp when nothing changed, so the profile is not re-uploaded on every sync.
            if let stored = profile(for: currentProfile.email, in: profiles),
               stored.initials == currentProfile.initials,
               stored.imageData == currentProfile.imageData {
                currentProfile.updatedAt = stored.updatedAt
            }
            let merged = merge(existing: profiles, incoming: [currentProfile])
            if merged != profiles {
                saveProfiles(merged)
            }
            profiles = merged
        }
        return profiles
    }

    static func mergeAndSave(_ incoming: [SharedMemberProfile]) {
        let existing = loadProfiles()
        let merged = merge(existing: existing, incoming: incoming)
        guard merged != existing else { return }
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

struct PreparedCloudShare: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Resumes a continuation once, whichever of two tasks finishes first.
@MainActor
private final class FirstOfTwo {
    var continuation: CheckedContinuation<Void, Never>?

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class SharedHouseholdStore: ObservableObject, HouseholdDataSource {
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
    private var subscribedScopes = Set<Int>()
    private var engine: HouseholdSyncEngine?
    private let defaults = UserDefaults.standard
    private let mirrorURL = URL.applicationSupportDirectory.appendingPathComponent("family-cloud-mirror.json")

    private enum DefaultsKey {
        static let recordName = "familySharing.recordName"
        static let zoneName = "familySharing.zoneName"
        static let ownerName = "familySharing.ownerName"
        static let databaseScope = "familySharing.databaseScope"
    }

    private typealias RecordKey = CloudKitHouseholdCloud.RootKey

    private enum CloudKitKey {
        static let rootRecordType = CloudKitHouseholdCloud.rootRecordType
        static let sharedZoneName = "FamilyTasksSharedZone"
        static let subscriptionID = "familytasks-changes"
    }

    private init() {}

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

    /// Fetches what changed in the shared zone, merges it with local data, and uploads
    /// whatever this device has that the cloud is missing.
    func refreshFromCloud() async {
        await synchronize(mode: .merge)
    }

    func uploadNow() async {
        await synchronize(mode: .merge)
    }

    /// Uploads, but returns after `timeout` even if the upload is still running (for Siri,
    /// which gives an action only a few seconds). An unfinished upload carries on, and any
    /// change it misses goes out with the next sync.
    func uploadNow(waitingAtMost timeout: Duration) async {
        guard isSharingConfigured else { return }
        let waiter = FirstOfTwo()
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            Task {
                await uploadNow()
                waiter.finish()
            }
            Task {
                try? await Task.sleep(for: timeout)
                waiter.finish()
            }
        }
    }

    func syncOnAppActivation() async {
        guard isSharingConfigured else { return }
        await refreshFromCloud()
    }

    private enum SyncMode {
        case merge
        /// Used right after joining a share: the family's data replaces this device's local data.
        case adoptRemote
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
        guard let rootID = storedRootRecordID else {
            statusMessage = "Not sharing yet"
            return
        }
        guard taskStore != nil, organizerStore != nil else { return }

        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        do {
            let engineMode: HouseholdSyncEngine.Mode = switch mode {
            case .merge: .merge
            case .adoptRemote: .adoptRemote
            }
            switch try await engine(for: rootID).sync(self, mode: engineMode) {
            case .upToDate:
                statusMessage = "Up to date \(Date().formatted(date: .abbreviated, time: .shortened))"
            case .uploaded:
                statusMessage = "Shared \(Date().formatted(date: .abbreviated, time: .shortened))"
            case nil:
                return
            }
            await ensureSubscription()
        } catch {
            lastErrorMessage = userFacingMessage(for: error)
            statusMessage = "Could not sync family sharing"
        }
    }

    /// The sync engine for the current share, with this device's last-known copy of it.
    private func engine(for rootID: CKRecord.ID) -> HouseholdSyncEngine {
        let zoneKey = Self.zoneKey(rootID: rootID, scope: databaseScope)
        if let engine, engine.mirror.zoneKey == zoneKey {
            return engine
        }

        var mirror = loadMirror()
        if mirror.zoneKey != zoneKey {
            mirror = CloudMirror(zoneKey: zoneKey)
        }
        let engine = HouseholdSyncEngine(
            cloud: CloudKitHouseholdCloud(database: database, rootID: rootID),
            mirror: mirror,
            persist: { [weak self] in self?.saveMirror($0) }
        )
        self.engine = engine
        return engine
    }

    /// Asks CloudKit to wake this device with a silent push when the family's data changes.
    /// Saved once per launch rather than remembered, so a device that switches between
    /// development and App Store builds gets a subscription in each CloudKit environment.
    private func ensureSubscription() async {
        let scope = databaseScope
        guard !subscribedScopes.contains(scope.rawValue) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: CloudKitKey.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            subscribedScopes.insert(scope.rawValue)
        } catch {
            // Not fatal: changes still arrive when the app opens. Retried after the next sync.
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
            Task { await uploadNow() }
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
                store(recordID: try Self.rootRecordID(of: metadata), databaseScope: .shared)
                statusMessage = "Joined shared family list"
                suppressNextSharedTaskArrivalNotification = true
                await synchronize(mode: .adoptRemote)
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
            store(recordID: try Self.rootRecordID(of: metadata), databaseScope: .shared)
            statusMessage = "Joined shared family list"
            suppressNextSharedTaskArrivalNotification = true
            await synchronize(mode: .adoptRemote)
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

    private static func zoneKey(rootID: CKRecord.ID, scope: CKDatabase.Scope) -> String {
        [String(scope.rawValue), rootID.zoneID.ownerName, rootID.zoneID.zoneName, rootID.recordName].joined(separator: "|")
    }

    private func loadMirror() -> CloudMirror {
        guard let data = try? Data(contentsOf: mirrorURL),
              let mirror = try? JSONDecoder().decode(CloudMirror.self, from: data) else {
            return CloudMirror(zoneKey: "")
        }
        return mirror
    }

    private func saveMirror(_ mirror: CloudMirror) {
        guard let data = try? JSONEncoder().encode(mirror) else { return }
        try? FileManager.default.createDirectory(at: mirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: mirrorURL, options: [.atomic])
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
            return try await container.privateCloudDatabase.record(for: recordID)
        }

        try await ensurePrivateSharingZone()

        let zoneID = CKRecordZone.ID(zoneName: CloudKitKey.sharedZoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitKey.rootRecordType, recordID: recordID)
        record[RecordKey.name] = "Family Tasks" as CKRecordValue
        record[RecordKey.schemaVersion] = CloudRoot.recordsSchemaVersion as CKRecordValue
        let saved = try await container.privateCloudDatabase.save(record)
        store(recordID: saved.recordID, databaseScope: .private)
        return saved
    }

    func currentPayload() -> SharedHouseholdPayload? {
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

    func apply(_ payload: SharedHouseholdPayload, changedRecords: [SyncRecord]) {
        let arrival = sharedTaskArrival(from: changedRecords)
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
        postSharedTaskArrival(arrival)
    }

    /// New tasks for this member that someone else added since the last sync.
    private func sharedTaskArrival(from changed: [SyncRecord]) -> (count: Int, title: String?)? {
        if suppressNextSharedTaskArrivalNotification {
            suppressNextSharedTaskArrivalNotification = false
            return nil
        }

        guard let taskStore else { return nil }

        let currentEmail = (defaults.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fromOthers = changed.filter { record in
            record.kind == .task &&
                record.updatedBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != currentEmail
        }

        let existingTaskIDs = Set(taskStore.exportTasks().map(\.id))
        let newTasks = HouseholdRecords.payload(from: fromOthers).tasks.filter { task in
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
        do {
            return try await container.shareMetadata(for: shareURL)
        } catch let error as CKError where error.code == .unknownItem || error.code == .invalidArguments {
            throw NSError(
                domain: "FamilyTasks.CloudSharing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not read the iCloud invite link."]
            )
        }
    }

    /// Family Tasks shares one root record (not a whole zone), so invites always have one.
    private static func rootRecordID(of metadata: CKShare.Metadata) throws -> CKRecord.ID {
        guard let recordID = metadata.hierarchicalRootRecordID else {
            throw NSError(
                domain: "FamilyTasks.CloudSharing",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This iCloud invite is not for a Family Tasks list."]
            )
        }
        return recordID
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

/// Family sharing's CloudKit calls: items are `FamilyItem` records under the shared
/// `FamilyTaskList` root record, in the owner's zone (private database) or the
/// family's shared zone (shared database).
@MainActor
struct CloudKitHouseholdCloud: HouseholdCloud {
    nonisolated static let rootRecordType = "FamilyTaskList"
    nonisolated static let itemRecordType = "FamilyItem"

    enum RootKey {
        static let name = "name"
        static let schemaVersion = "schemaVersion"
        /// Versions before per-item records stored the whole household here.
        static let payload = "payload"
    }

    private enum ItemKey {
        static let kind = "kind"
        static let payload = "payload"
        static let updatedAt = "updatedAt"
        static let updatedBy = "updatedBy"
    }

    let database: CKDatabase
    let rootID: CKRecord.ID

    func fetchChanges(since changeToken: Data?) async throws -> CloudChanges {
        let token = changeToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }

        let result: (
            modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
            deletions: [CKDatabase.RecordZoneChange.Deletion],
            changeToken: CKServerChangeToken,
            moreComing: Bool
        )
        do {
            result = try await database.recordZoneChanges(inZoneWith: rootID.zoneID, since: token)
        } catch let error as CKError where error.code == .changeTokenExpired {
            throw HouseholdCloudError.changeTokenExpired
        }

        var changes = CloudChanges(
            deletedNames: result.deletions.map(\.recordID.recordName),
            changeToken: try? NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true),
            moreComing: result.moreComing
        )
        for case .success(let modification) in result.modificationResultsByID.values {
            let record = modification.record
            if record.recordID == rootID {
                changes.root = root(from: record)
            } else if let entry = entry(from: record) {
                changes.entries.append(entry)
            }
        }
        return changes
    }

    func save(_ entries: [CloudMirror.Entry], root: CloudRoot?) async throws -> (entries: [String: CloudSaveResult<CloudMirror.Entry>], root: CloudSaveResult<CloudRoot>?) {
        var records = entries.map(record(for:))
        if let root {
            records.insert(record(for: root), at: 0)
        }

        var entryResults: [String: CloudSaveResult<CloudMirror.Entry>] = [:]
        var rootResult: CloudSaveResult<CloudRoot>?

        for batch in Self.batches(records) {
            let (saveResults, _) = try await database.modifyRecords(
                saving: batch,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for (recordID, result) in saveResults {
                let isRoot = recordID == rootID
                switch result {
                case .success(let saved):
                    if isRoot {
                        rootResult = .saved(self.root(from: saved))
                    } else if let entry = entry(from: saved) {
                        entryResults[recordID.recordName] = .saved(entry)
                    }
                case .failure(let error as CKError) where error.code == .serverRecordChanged:
                    if isRoot {
                        rootResult = .conflict(error.serverRecord.map(self.root(from:)))
                    } else {
                        entryResults[recordID.recordName] = .conflict(error.serverRecord.flatMap(entry(from:)))
                    }
                case .failure(let error):
                    if isRoot {
                        rootResult = .failed(error)
                    } else {
                        entryResults[recordID.recordName] = .failed(error)
                    }
                }
            }
        }

        return (entryResults, rootResult)
    }

    func delete(_ names: [String]) async throws -> [String] {
        let recordIDs = names.map { CKRecord.ID(recordName: $0, zoneID: rootID.zoneID) }
        let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs, atomically: false)
        return deleteResults.compactMap { recordID, result in
            if case .success = result { recordID.recordName } else { nil }
        }
    }

    private func root(from record: CKRecord) -> CloudRoot {
        let version = record[RootKey.schemaVersion] as? Int ?? 0
        return CloudRoot(
            systemFields: Self.systemFields(of: record),
            schemaVersion: version,
            legacyPayload: version < CloudRoot.recordsSchemaVersion ? record[RootKey.payload] as? Data : nil
        )
    }

    private func entry(from record: CKRecord) -> CloudMirror.Entry? {
        guard record.recordType == Self.itemRecordType,
              let kindValue = record[ItemKey.kind] as? String,
              let kind = SyncRecord.Kind(rawValue: kindValue) else { return nil }

        return CloudMirror.Entry(
            record: SyncRecord(
                name: record.recordID.recordName,
                kind: kind,
                payload: record[ItemKey.payload] as? Data,
                updatedAt: record[ItemKey.updatedAt] as? Date ?? HouseholdRecords.unknownDate,
                updatedBy: record[ItemKey.updatedBy] as? String ?? ""
            ),
            systemFields: Self.systemFields(of: record),
            createdAt: record.creationDate
        )
    }

    private func record(for entry: CloudMirror.Entry) -> CKRecord {
        let record = entry.systemFields.flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: Self.itemRecordType, recordID: CKRecord.ID(recordName: entry.record.name, zoneID: rootID.zoneID))
        record[ItemKey.kind] = entry.record.kind.rawValue as CKRecordValue
        record[ItemKey.payload] = entry.record.payload.map { $0 as NSData }
        record[ItemKey.updatedAt] = entry.record.updatedAt as NSDate
        record[ItemKey.updatedBy] = entry.record.updatedBy as NSString
        // Records under the shared root record are part of the family share.
        record.setParent(rootID)
        return record
    }

    private func record(for root: CloudRoot) -> CKRecord {
        let record = root.systemFields.flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: Self.rootRecordType, recordID: rootID)
        record[RootKey.name] = "Family Tasks" as CKRecordValue
        record[RootKey.schemaVersion] = root.schemaVersion as CKRecordValue
        record[RootKey.payload] = root.legacyPayload.map { $0 as NSData }
        return record
    }

    /// Splits records into requests CloudKit accepts (at most 400 records and about 2 MB each).
    private static func batches(_ records: [CKRecord]) -> [[CKRecord]] {
        let maxCount = 200
        let maxBytes = 1_500_000
        var batches: [[CKRecord]] = []
        var current: [CKRecord] = []
        var currentBytes = 0

        for record in records {
            let size = (record[ItemKey.payload] as? Data)?.count ?? 0
            if !current.isEmpty && (current.count >= maxCount || currentBytes + size > maxBytes) {
                batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(record)
            currentBytes += size
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
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
            WidgetBridge.shared.configure(taskStore: .shared, organizerStore: .shared)
        }
        FamilyTasksShortcuts.updateAppShortcutParameters()
        HealthSyncCoordinator.shared.registerBackgroundRefresh()
        HealthSyncCoordinator.shared.scheduleDailyRefresh()
        // CloudKit sends a silent push when another family member changes something.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil,
              SharedHouseholdStore.shared.isSharingConfigured else { return .noData }
        // Include check-offs made in widgets so they reach the family too.
        WidgetBridge.shared.applyPendingActions()
        await SharedHouseholdStore.shared.refreshFromCloud()
        // Reminders are otherwise only rescheduled for local edits and when the app opens.
        await NotificationScheduler.shared.reschedule()
        return .newData
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            SharedHouseholdStore.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        HealthSyncCoordinator.shared.scheduleDailyRefresh()
    }

    nonisolated func userNotificationCenter(
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
