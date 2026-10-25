import CloudKit
import CryptoKit
import Foundation
import UIKit
import UserNotifications

/// Sends nudges and task news to family members as real pushes, which iOS shows even when
/// the app is closed (the household sync's silent pushes are throttled and are dropped
/// for apps that were swiped away).
///
/// Each alert is a `FamilyAlert` record in the container's public database addressed to a
/// hash of the recipient's email. Every phone subscribes to the alerts addressed to it, and
/// CloudKit turns each new record into a notification. Records carry only the hash, the
/// sender's name and the task title, and the sender deletes them a day later.
@MainActor
final class FamilyAlertService {
    static let shared = FamilyAlertService()

    enum NudgeError: LocalizedError {
        case notSharing
        case nobodyElse
        case tooSoon
        case cloud(Error)

        var errorDescription: String? {
            switch self {
            case .notSharing: "Share your household first, so there's someone to nudge."
            case .nobodyElse: "This task isn't for anyone else."
            case .tooSoon: "You just nudged about this. Give them a few minutes."
            case .cloud(let error): Self.message(for: error)
            }
        }

        private static func message(for error: Error) -> String {
            guard let cloudError = error as? CKError else { return error.localizedDescription }
            switch cloudError.code {
            case .notAuthenticated: return "Sign in to iCloud to send nudges."
            case .networkUnavailable, .networkFailure: return "You're offline. The nudge will go out when you're back online."
            default: return cloudError.localizedDescription
            }
        }
    }

    nonisolated static let recordType = "FamilyAlert"
    private static let subscriptionID = "familytasks-alerts"
    private static let nudgeCooldown: TimeInterval = 5 * 60
    private static let recordLifetime: TimeInterval = 86_400

    private enum Field {
        static let recipient = "recipient"
        static let kind = "kind"
        static let title = "title"
        static let body = "body"
        static let itemID = "itemID"
    }

    private enum DefaultsKey {
        static let sent = "familyAlerts.sent"
        static let unsent = "familyAlerts.unsent"
        static let isSubscribed = "familyAlerts.isSubscribed"
        static let lastSent = "familyAlerts.lastSent"
        static let lastSendError = "familyAlerts.lastSendError"
        static let lastSubscriptionError = "familyAlerts.lastSubscriptionError"
        static let lastNudge = "familyAlerts.lastNudge"
    }

    private struct SentRecord: Codable {
        var name: String
        var sentAt: Date
    }

    private struct UnsentAlert: Codable {
        var alert: FamilyAlert
        var createdAt: Date
    }

    // Created on first use so unit tests, which run unsigned, never touch CloudKit.
    private lazy var database = CKContainer.default().publicCloudDatabase
    private weak var taskStore: TaskStore?
    private var changeObserver: NSObjectProtocol?
    /// The subscription saved this launch; saved again whenever what it asks for changes.
    private var savedSubscriptionKey: String?
    private let defaults = UserDefaults.standard

    private init() {}

    func configure(taskStore: TaskStore) {
        self.taskStore = taskStore

        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .familyItemChangedLocally,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let change = notification.userInfo?["change"] as? LocalItemChange else { return }
                MainActor.assumeIsolated {
                    self?.handle(change)
                }
            }
        }

        Task {
            await refresh()
        }
    }

    /// Updates this phone's subscription, resends alerts that failed offline and deletes old ones.
    func refresh() async {
        await updateSubscription()
        await sendUnsent()
        await deleteExpiredRecords()
    }

    // MARK: Sending

    /// When each item was last nudged from this phone, by item ID.
    private var lastNudge: [String: Date] {
        get { defaults.dictionary(forKey: DefaultsKey.lastNudge) as? [String: Date] ?? [:] }
        set {
            // A day is as far back as anything asks.
            let cutoff = Date().addingTimeInterval(-86_400)
            defaults.set(newValue.filter { $0.value > cutoff }, forKey: DefaultsKey.lastNudge)
        }
    }

    /// Whether this phone nudged about `item` today.
    func wasNudgedToday(_ item: some AssignedItem, calendar: Calendar = .current) -> Bool {
        guard let date = lastNudge[item.id.uuidString] else { return false }
        return calendar.isDateInToday(date)
    }

    func canNudge(_ item: some AssignedItem) -> Bool {
        guard SharedHouseholdStore.shared.isSharingConfigured else { return false }
        return !FamilyAlert.nudgeRecipients(for: item, sender: senderEmail, familyMembers: familyMembers).isEmpty
    }

    /// Nudges everyone `item` is for. Returns their names.
    func nudge(_ item: some AssignedItem, dueDate: Date?) async throws(NudgeError) -> [String] {
        guard SharedHouseholdStore.shared.isSharingConfigured else { throw .notSharing }
        let alerts = FamilyAlert.nudges(
            for: item,
            dueDate: dueDate,
            sender: senderEmail,
            senderName: senderName,
            familyMembers: familyMembers
        )
        guard !alerts.isEmpty else { throw .nobodyElse }

        let key = item.id.uuidString
        if let last = lastNudge[key], Date().timeIntervalSince(last) < Self.nudgeCooldown {
            throw .tooSoon
        }
        lastNudge[key] = Date()

        do {
            try await save(alerts)
        } catch {
            lastNudge[key] = nil
            if Self.isRetryable(error) { queue(alerts) }
            throw .cloud(error)
        }
        return alerts.map { Assignee.memberName(for: $0.recipient) }
    }

    private func handle(_ change: LocalItemChange) {
        guard SharedHouseholdStore.shared.isSharingConfigured else { return }
        let alerts: [FamilyAlert] = switch change {
        case let .task(before, after):
            FamilyAlert.taskAlerts(
                before: before,
                after: after,
                sender: senderEmail,
                senderName: senderName,
                familyMembers: familyMembers
            )
        case let .recurring(before, after, completedOccurrence):
            FamilyAlert.recurringAlerts(
                before: before,
                after: after,
                completedOccurrence: completedOccurrence,
                sender: senderEmail,
                senderName: senderName,
                familyMembers: familyMembers
            )
        case let .shoppingTrip(shopID, shopName, itemCount):
            FamilyAlert.shoppingDone(
                trip: ShoppingTripNews(who: senderName, shopName: shopName, itemCount: itemCount),
                shopID: shopID,
                sender: senderEmail,
                familyMembers: familyMembers
            )
        }
        guard !alerts.isEmpty else { return }

        Task {
            do {
                try await save(alerts)
            } catch where Self.isRetryable(error) {
                queue(alerts)
            } catch {
                // Not retryable (for example, no iCloud account): the change itself still syncs.
            }
        }
    }

    private func save(_ alerts: [FamilyAlert]) async throws {
        do {
            try await saveRecords(alerts)
            defaults.set(Date(), forKey: DefaultsKey.lastSent)
            defaults.removeObject(forKey: DefaultsKey.lastSendError)
        } catch {
            defaults.set(Self.describe(error), forKey: DefaultsKey.lastSendError)
            throw error
        }
    }

    private func saveRecords(_ alerts: [FamilyAlert]) async throws {
        let records = alerts.map(record(for:))
        let (results, _) = try await database.modifyRecords(saving: records, deleting: [])
        var sent = loadSent()
        var firstError: Error?
        for (id, result) in results {
            switch result {
            case .success: sent.append(SentRecord(name: id.recordName, sentAt: Date()))
            case .failure(let error): firstError = firstError ?? error
            }
        }
        saveSent(sent)
        if let firstError { throw firstError }
    }

    private func record(for alert: FamilyAlert) -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record[Field.recipient] = Self.recipientKey(for: alert.recipient) as CKRecordValue
        record[Field.kind] = alert.kind.rawValue as CKRecordValue
        record[Field.title] = alert.title as CKRecordValue
        record[Field.body] = alert.body as CKRecordValue
        record[Field.itemID] = alert.itemID as CKRecordValue
        return record
    }

    /// Who an alert is for, without putting their email in the public database.
    nonisolated static func recipientKey(for email: String) -> String {
        let digest = SHA256.hash(data: Data("familytasks:\(FamilyAlert.normalized(email))".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        return [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy]
            .contains(cloudError.code)
    }

    // MARK: Offline queue

    private func queue(_ alerts: [FamilyAlert]) {
        var unsent = loadUnsent()
        unsent += alerts.map { UnsentAlert(alert: $0, createdAt: Date()) }
        saveUnsent(unsent)
    }

    private func sendUnsent() async {
        // News older than a day isn't worth a push any more.
        let unsent = loadUnsent().filter { Date().timeIntervalSince($0.createdAt) < Self.recordLifetime }
        saveUnsent([])
        guard !unsent.isEmpty, SharedHouseholdStore.shared.isSharingConfigured else { return }
        do {
            try await save(unsent.map(\.alert))
        } catch where Self.isRetryable(error) {
            saveUnsent(unsent)
        } catch {}
    }

    private func loadUnsent() -> [UnsentAlert] {
        defaults.data(forKey: DefaultsKey.unsent).flatMap { try? JSONDecoder().decode([UnsentAlert].self, from: $0) } ?? []
    }

    private func saveUnsent(_ unsent: [UnsentAlert]) {
        defaults.set(try? JSONEncoder().encode(unsent), forKey: DefaultsKey.unsent)
    }

    // MARK: Cleanup

    private func deleteExpiredRecords() async {
        let sent = loadSent()
        let cutoff = Date().addingTimeInterval(-Self.recordLifetime)
        let expired = sent.filter { $0.sentAt < cutoff }
        guard !expired.isEmpty else { return }

        let ids = expired.map { CKRecord.ID(recordName: $0.name) }
        guard let (_, results) = try? await database.modifyRecords(saving: [], deleting: ids) else { return }
        // Forget records that are gone; keep ones that failed for a later try.
        let gone = Set(results.compactMap { id, result -> String? in
            switch result {
            case .success: return id.recordName
            case .failure(let error): return (error as? CKError)?.code == .unknownItem ? id.recordName : nil
            }
        })
        saveSent(loadSent().filter { !gone.contains($0.name) })
    }

    private func loadSent() -> [SentRecord] {
        defaults.data(forKey: DefaultsKey.sent).flatMap { try? JSONDecoder().decode([SentRecord].self, from: $0) } ?? []
    }

    private func saveSent(_ sent: [SentRecord]) {
        defaults.set(try? JSONEncoder().encode(sent), forKey: DefaultsKey.sent)
    }

    // MARK: Subscription

    /// Which kinds of alert this person wants, from Notification settings. Nudges always
    /// come through while notifications are on.
    nonisolated static func wantedKinds(defaults: UserDefaults) -> [FamilyAlert.Kind] {
        guard defaults.bool(forKey: "notifications.enabled") else { return [] }
        var kinds: [FamilyAlert.Kind] = [.nudge]
        if defaults.object(forKey: "notifications.taskChanges") as? Bool ?? true {
            kinds += [.assigned, .updated]
        }
        if defaults.object(forKey: "notifications.familyCompletions") as? Bool ?? true {
            kinds.append(.completed)
        }
        if defaults.object(forKey: "notifications.familyShopping") as? Bool ?? true {
            kinds.append(.shopping)
        }
        return kinds
    }

    /// Subscribes this phone to the alerts addressed to its profile email, or removes the
    /// subscription when there's nothing to receive.
    func updateSubscription() async {
        let email = senderEmail
        let kinds = SharedHouseholdStore.shared.isSharingConfigured && TaskStore.isValidEmail(email)
            ? Self.wantedKinds(defaults: defaults)
            : []
        let key = kinds.isEmpty ? "none" : "\(Self.recipientKey(for: email))|\(kinds.map(\.rawValue).joined(separator: ","))"
        guard key != savedSubscriptionKey else { return }
        // Nothing to remove on a phone that never subscribed (and no CloudKit for unsigned test runs).
        guard !kinds.isEmpty || defaults.bool(forKey: DefaultsKey.isSubscribed) else {
            savedSubscriptionKey = key
            return
        }

        do {
            if kinds.isEmpty {
                _ = try await database.deleteSubscription(withID: Self.subscriptionID)
            } else {
                // Saving under the same ID replaces the old predicate.
                _ = try await database.save(subscription(for: email, kinds: kinds))
            }
            savedSubscriptionKey = key
            defaults.set(!kinds.isEmpty, forKey: DefaultsKey.isSubscribed)
            defaults.removeObject(forKey: DefaultsKey.lastSubscriptionError)
        } catch let error as CKError where error.code == .unknownItem {
            savedSubscriptionKey = key
            defaults.set(false, forKey: DefaultsKey.isSubscribed)
        } catch {
            // Tried again next launch or settings change.
            defaults.set(Self.describe(error), forKey: DefaultsKey.lastSubscriptionError)
        }
    }

    private func subscription(for email: String, kinds: [FamilyAlert.Kind]) -> CKQuerySubscription {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K IN %@",
            Field.recipient, Self.recipientKey(for: email),
            Field.kind, kinds.map(\.rawValue)
        )
        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: predicate,
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation]
        )

        // The alert text is the record's own title and body: a localization key of "%1$@"
        // with the field as its argument shows the field as-is.
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = [Field.title]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = [Field.body]
        info.soundName = "default"
        info.desiredKeys = [Field.kind, Field.itemID]
        // Also wake the app so it syncs the change the alert is about.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        return subscription
    }

    // MARK: Checking

    /// One step family alerts depend on, for Settings to show when alerts don't arrive.
    struct Check: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var isOK: Bool
    }

    /// Checks everything a family alert needs on this phone, saving the subscription again
    /// so its error, if any, is current.
    func runChecks() async -> [Check] {
        var checks: [Check] = []

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = settings.authorizationStatus == .authorized
        let enabled = defaults.bool(forKey: "notifications.enabled")
        checks.append(Check(
            title: "Notifications On",
            detail: !allowed ? "Allow notifications for Family Tasks in the iPhone Settings app."
                : !enabled ? "Turn on Enable Notifications above."
                : "Allowed and turned on.",
            isOK: allowed && enabled
        ))

        let registered = UIApplication.shared.isRegisteredForRemoteNotifications
        checks.append(Check(
            title: "Push Registration",
            detail: registered ? "This phone can receive pushes." : "iOS hasn't registered this phone for pushes yet. Restart the app.",
            isOK: registered
        ))

        let account: CKAccountStatus? = try? await CKContainer.default().accountStatus()
        checks.append(Check(
            title: "iCloud Account",
            detail: account == .available ? "Signed in." : "Sign in to iCloud in the iPhone Settings app.",
            isOK: account == .available
        ))

        let sharing = SharedHouseholdStore.shared.isSharingConfigured
        checks.append(Check(
            title: "Household Sharing",
            detail: sharing ? "Sharing with your family." : "Share your household in Family & Sharing.",
            isOK: sharing
        ))

        let email = senderEmail
        let validEmail = TaskStore.isValidEmail(email)
        checks.append(Check(
            title: "Your Email",
            detail: validEmail ? "\(email). Family members must list you with exactly this email." : "Add your email in Profile. Alerts are addressed to it.",
            isOK: validEmail
        ))

        let others = familyMembers.map(FamilyAlert.normalized).filter { $0 != email }
        checks.append(Check(
            title: "Family Emails",
            detail: others.isEmpty ? "No one else is in your family list." : others.joined(separator: ", "),
            isOK: !others.isEmpty
        ))

        if allowed && enabled && account == .available && sharing && validEmail {
            savedSubscriptionKey = nil
            await updateSubscription()
            let error = defaults.string(forKey: DefaultsKey.lastSubscriptionError)
            checks.append(Check(
                title: "Alert Subscription",
                detail: error ?? "Saved. Alerts for \(email) come to this phone.",
                isOK: error == nil
            ))

            // Fails when the FamilyAlert type or its Queryable indexes aren't in this environment.
            let query = CKQuery(
                recordType: Self.recordType,
                predicate: NSPredicate(format: "%K == %@", Field.recipient, Self.recipientKey(for: email))
            )
            do {
                _ = try await database.records(matching: query, resultsLimit: 1)
                checks.append(Check(title: "CloudKit Schema", detail: "FamilyAlert is set up.", isOK: true))
            } catch {
                checks.append(Check(title: "CloudKit Schema", detail: Self.describe(error), isOK: false))
            }
        }

        if let error = defaults.string(forKey: DefaultsKey.lastSendError) {
            checks.append(Check(title: "Last Alert Sent", detail: "Failed: \(error)", isOK: false))
        } else if let date = defaults.object(forKey: DefaultsKey.lastSent) as? Date {
            checks.append(Check(
                title: "Last Alert Sent",
                detail: "Sent \(date.formatted(date: .abbreviated, time: .shortened)).",
                isOK: true
            ))
        }

        return checks
    }

    /// Family members a test alert can go to.
    var testRecipients: [String] {
        familyMembers.map(FamilyAlert.normalized).filter { $0 != senderEmail && TaskStore.isValidEmail($0) }
    }

    /// Sends `email` an alert that only says it's a test.
    func sendTestAlert(to email: String) async throws {
        try await save([FamilyAlert(
            kind: .nudge,
            recipient: email,
            title: "Test from \(senderName)",
            body: "Family alerts reach this phone.",
            itemID: UUID().uuidString
        )])
    }

    private static func describe(_ error: Error) -> String {
        guard let cloudError = error as? CKError else { return error.localizedDescription }
        if let partial = cloudError.partialErrorsByItemID?.values.first {
            return describe(partial)
        }
        return "\(cloudError.localizedDescription) (CloudKit error \(cloudError.code.rawValue))"
    }

    // MARK: Who's sending

    private var senderEmail: String {
        FamilyAlert.normalized(defaults.string(forKey: "profile.email") ?? "")
    }

    private var senderName: String {
        FamilyAlert.senderName(email: senderEmail, profileName: defaults.string(forKey: "profile.name") ?? "")
    }

    private var familyMembers: [String] {
        taskStore?.exportFamilyMembers() ?? []
    }
}
