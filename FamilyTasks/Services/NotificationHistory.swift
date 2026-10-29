import CloudKit
import Foundation
import UserNotifications

/// The notifications this phone showed in the last week, for looking back at what was said.
///
/// iOS keeps no history an app can read, so notifications are saved as they're seen: when
/// one arrives with the app open, when one is tapped, and when the app opens (anything still
/// in Notification Center). One swiped away before the app next opens can't be recovered.
@MainActor
final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory()

    struct Entry: Identifiable, Codable, Equatable, Sendable {
        /// The notification request's identifier, so one notification is kept once.
        var id: String
        var title: String
        var body: String
        var date: Date
        var kind: Kind
    }

    enum Kind: String, Codable, Sendable {
        case dailyList
        case dueSoon
        case recurringDueSoon
        case shopping
        case nudge
        case assigned
        case updated
        case completed
        case habit
        case cheer
        case healthGoal
        case windDown
        case healthTip
        case other

        var systemImage: String {
            switch self {
            case .dailyList: "list.bullet.clipboard"
            case .dueSoon: "clock"
            case .recurringDueSoon: "repeat"
            case .shopping: "cart"
            case .nudge: "bell.and.waves.left.and.right"
            case .assigned: "plus.circle"
            case .updated: "square.and.pencil"
            case .completed: "checkmark.circle"
            case .habit: "flame"
            case .cheer: "hands.clap"
            case .healthGoal: "trophy"
            case .windDown: "moon.zzz"
            case .healthTip: "lightbulb"
            case .other: "bell"
            }
        }
    }

    nonisolated static let retention: TimeInterval = 7 * 86_400
    private nonisolated static let maxEntries = 300

    @Published private(set) var entries: [Entry] = []
    private let storageURL: URL

    init(storageURL: URL = URL.applicationSupportDirectory.appendingPathComponent("notification-history.json")) {
        self.storageURL = storageURL
        if let data = try? Data(contentsOf: storageURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Self.merged(saved, with: [], now: Date())
        }
    }

    func record(_ newEntries: [Entry], now: Date = Date()) {
        let updated = Self.merged(entries, with: newEntries, now: now)
        guard updated != entries else { return }
        entries = updated
        save()
    }

    /// Saves everything still showing in Notification Center.
    func collectDelivered() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        record(delivered.compactMap(Self.entry(for:)))
    }

    func clear() {
        entries = []
        save()
    }

    /// Newest first, one per identifier, nothing older than a week.
    nonisolated static func merged(_ existing: [Entry], with new: [Entry], now: Date) -> [Entry] {
        let cutoff = now.addingTimeInterval(-retention)
        var byID: [String: Entry] = [:]
        for entry in existing + new where entry.date >= cutoff {
            byID[entry.id] = byID[entry.id] ?? entry
        }
        return Array(byID.values.sorted { $0.date > $1.date }.prefix(maxEntries))
    }

    /// The history entry for a notification, or nil for test notifications.
    nonisolated static func entry(for notification: UNNotification) -> Entry? {
        let request = notification.request
        guard !request.identifier.hasPrefix("familytasks.test.") else { return nil }
        let content = request.content
        guard !content.title.isEmpty || !content.body.isEmpty else { return nil }
        return Entry(
            id: request.identifier,
            title: content.title,
            body: content.body,
            date: notification.date,
            kind: kind(identifier: request.identifier, userInfo: content.userInfo)
        )
    }

    /// What a notification was about, from the identifier this app gives local ones or the
    /// `kind` field of a family alert push.
    nonisolated static func kind(identifier: String, userInfo: [AnyHashable: Any]) -> Kind {
        if identifier.hasPrefix("familytasks.todayDigest.") { return .dailyList }
        if identifier.hasPrefix("familytasks.dueSoon.") { return .dueSoon }
        if identifier.hasPrefix("familytasks.recurringDueSoon.") { return .recurringDueSoon }
        if identifier.hasPrefix("familytasks.shoppingDone.") { return .shopping }
        if identifier.hasPrefix("familytasks.windDown.") { return .windDown }
        if identifier.hasPrefix("familytasks.healthTip.") { return .healthTip }
        if let query = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           let raw = query.recordFields?["kind"] as? String,
           let kind = Kind(rawValue: raw) {
            return kind
        }
        return .other
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: [.atomic])
    }
}
