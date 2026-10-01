import Foundation

/// What the widgets show. The app writes it to the shared App Group container
/// whenever tasks or shopping change; the widgets only read it (and check items off).
/// Compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    struct TaskRow: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var dueDate: Date
        var isUrgent: Bool
        var isImportant: Bool
    }

    struct ItemRow: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }

    struct ShopRow: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var items: [ItemRow]
    }

    /// Open tasks for this family member that are overdue or due within the next week,
    /// so the widget stays correct across midnight without the app running.
    var tasks: [TaskRow] = []
    /// Shops in the app's order, each with the items still needed there.
    var shops: [ShopRow] = []

    /// Tasks due on `day` and tasks from earlier days that are still open.
    func tasks(for day: Date, calendar: Calendar = .current) -> (due: [TaskRow], overdue: [TaskRow]) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let due = tasks.filter { $0.dueDate >= start && $0.dueDate < end }
        let overdue = tasks.filter { $0.dueDate < start }
        return (due, overdue)
    }

    /// Reflects a check-off made in a widget before the app has applied it.
    mutating func apply(_ action: WidgetAction) {
        switch action.kind {
        case .completeTask:
            tasks.removeAll { $0.id == action.id }
        case .purchaseItem:
            for index in shops.indices {
                shops[index].items.removeAll { $0.id == action.id }
            }
        }
    }
}

/// A check-off made in a widget, waiting for the app to apply it to its data.
struct WidgetAction: Codable, Equatable {
    enum Kind: String, Codable {
        case completeTask
        case purchaseItem
    }

    var kind: Kind
    var id: UUID
    var date: Date
}

/// Files shared between the app and the widget extension through the App Group.
struct WidgetStorage: Sendable {
    static let appGroupID = "group.com.naveenkeerthy.FamilyTasks"

    /// Nil when the App Group is unavailable (for example in unsigned test builds).
    static var shared: WidgetStorage? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            .map(WidgetStorage.init(directory:))
    }

    let directory: URL

    private var snapshotURL: URL { directory.appendingPathComponent("widget-snapshot.json") }
    /// One file per action, so the widget can add actions while the app removes applied ones.
    private var actionsDirectory: URL { directory.appendingPathComponent("widget-actions", isDirectory: true) }

    func loadSnapshot() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: [.atomic])
    }

    func record(_ action: WidgetAction) throws {
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        let url = actionsDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try JSONEncoder().encode(action).write(to: url, options: [.atomic])
    }

    /// Recorded actions, oldest first, with the file each came from.
    func pendingActions() -> [(url: URL, action: WidgetAction)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: actionsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let action = try? JSONDecoder().decode(WidgetAction.self, from: data) else { return nil }
                return (url, action)
            }
            .sorted { $0.action.date < $1.action.date }
    }

    func removeAction(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
