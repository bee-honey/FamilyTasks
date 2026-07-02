import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()

    @Published private(set) var statusMessage = "Notification status not checked yet."
    @Published private(set) var pendingAlertCount = 0

    private let center = UNUserNotificationCenter.current()
    private weak var taskStore: TaskStore?
    private weak var organizerStore: OrganizerStore?
    private var changeObserver: NSObjectProtocol?
    private var sharedTaskObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let enabled = "notifications.enabled"
        static let todayDigest = "notifications.todayDigest"
        static let dueSoon = "notifications.dueSoon"
        static let todayDigestHour = "notifications.todayDigestHour"
        static let todayDigestMinute = "notifications.todayDigestMinute"
        static let dueSoonLeadMinutes = "notifications.dueSoonLeadMinutes"
    }

    private enum IdentifierPrefix {
        static let todayDigest = "familytasks.todayDigest."
        static let dueSoon = "familytasks.dueSoon."
        static let recurringDueSoon = "familytasks.recurringDueSoon."
        static let sharedTaskArrival = "familytasks.sharedTaskArrival."
    }

    private init() {
        registerDefaults()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        if let sharedTaskObserver {
            NotificationCenter.default.removeObserver(sharedTaskObserver)
        }
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
                    await self?.reschedule()
                }
            }
        }

        if sharedTaskObserver == nil {
            sharedTaskObserver = NotificationCenter.default.addObserver(
                forName: .sharedTasksDidArrive,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let count = notification.userInfo?["count"] as? Int ?? 1
                let title = notification.userInfo?["title"] as? String
                Task { @MainActor in
                    await self?.scheduleSharedTaskArrival(count: count, title: title)
                }
            }
        }

        Task {
            await reschedule()
            await refreshStatus()
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await reschedule()
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    func reschedule() async {
        guard defaults.bool(forKey: DefaultsKey.enabled) else {
            center.removePendingNotificationRequests(withIdentifiers: await pendingFamilyTaskIdentifiers())
            await refreshStatus()
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: await pendingFamilyTaskIdentifiers())
            await refreshStatus(settings: settings)
            return
        }

        let pendingIdentifiers = await pendingFamilyTaskIdentifiers()
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

        guard let taskStore else { return }
        let activeTasks = taskStore.exportTasks().filter { !$0.isDone }
        let activeRecurringTasks = organizerStore?.exportRecurringTasks().filter(\.isActive) ?? []

        if defaults.bool(forKey: DefaultsKey.todayDigest) {
            scheduleTodayDigests(for: activeTasks)
        }

        scheduleDueSoonAlerts(for: activeTasks)
        scheduleRecurringDueSoonAlerts(for: activeRecurringTasks)

        await refreshStatus(settings: settings)
    }

    func refreshStatus() async {
        await refreshStatus(settings: center.notificationSettings())
    }

    func sendTestNotification() async {
        guard defaults.bool(forKey: DefaultsKey.enabled) else {
            statusMessage = "Turn on Enable Notifications before sending a test."
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            statusMessage = "Notifications are not allowed. Enable them in iOS Settings."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Family Tasks Test"
        content.body = "Notifications are working on this device."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "familytasks.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )

        do {
            try await center.add(request)
            statusMessage = "Test notification scheduled. It should appear in a few seconds."
            await refreshStatus(settings: settings)
        } catch {
            statusMessage = "Could not schedule the test notification: \(error.localizedDescription)"
        }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            DefaultsKey.todayDigest: true,
            DefaultsKey.dueSoon: true,
            DefaultsKey.todayDigestHour: 8,
            DefaultsKey.todayDigestMinute: 0,
            DefaultsKey.dueSoonLeadMinutes: 60
        ])
    }

    private func pendingFamilyTaskIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter {
                $0.hasPrefix(IdentifierPrefix.todayDigest) ||
                $0.hasPrefix(IdentifierPrefix.dueSoon) ||
                $0.hasPrefix(IdentifierPrefix.recurringDueSoon) ||
                $0.hasPrefix(IdentifierPrefix.sharedTaskArrival)
            }
    }

    private func refreshStatus(settings: UNNotificationSettings) async {
        let pendingIdentifiers = await pendingFamilyTaskIdentifiers()
        pendingAlertCount = pendingIdentifiers.count

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            if defaults.bool(forKey: DefaultsKey.enabled) {
                let alertText = pendingAlertCount == 1 ? "1 alert" : "\(pendingAlertCount) alerts"
                statusMessage = "Allowed. \(alertText) scheduled."
            } else {
                statusMessage = "Notifications are off in Family Tasks."
            }
        case .denied:
            statusMessage = "Notifications are blocked in iOS Settings."
        case .notDetermined:
            statusMessage = "Notifications have not been allowed yet."
        case .ephemeral:
            statusMessage = "Notifications are temporarily allowed."
        @unknown default:
            statusMessage = "Notification permission status is unknown."
        }
    }

    private func scheduleTodayDigests(for tasks: [FamilyTask]) {
        let calendar = Calendar.current
        let now = Date()
        let hour = defaults.integer(forKey: DefaultsKey.todayDigestHour)
        let minute = defaults.integer(forKey: DefaultsKey.todayDigestMinute)

        for dayOffset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let triggerDate = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: day
                  ),
                  triggerDate > now else {
                continue
            }

            let dayTasks = tasks
                .filter { task in
                    guard let dueDate = task.dueDate else { return false }
                    return calendar.isDate(dueDate, inSameDayAs: day)
                }
                .sorted { lhs, rhs in
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (left?, right?):
                        return left < right
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    case (.none, .none):
                        return lhs.updatedAt > rhs.updatedAt
                    }
                }

            guard !dayTasks.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Today's Family Tasks"
            content.body = digestBody(for: dayTasks)
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(IdentifierPrefix.todayDigest)\(dayOffset)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func scheduleDueSoonAlerts(for tasks: [FamilyTask]) {
        let now = Date()

        for task in tasks {
            guard let dueDate = task.dueDate else { continue }
            guard dueDate > now else { continue }
            guard let leadMinutes = leadMinutes(for: task.notificationPreference) else { continue }

            let triggerDate = dueDate.addingTimeInterval(TimeInterval(-leadMinutes * 60))
            let effectiveTriggerDate = max(triggerDate, now.addingTimeInterval(3))

            let content = UNMutableNotificationContent()
            content.title = leadMinutes == 0 ? "Task Due Now" : "Task Due Soon"
            content.body = dueSoonBody(for: task, leadMinutes: leadMinutes)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, effectiveTriggerDate.timeIntervalSince(now)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(IdentifierPrefix.dueSoon)\(task.id.uuidString)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func scheduleRecurringDueSoonAlerts(for recurringTasks: [RecurringTask]) {
        let now = Date()

        for task in recurringTasks {
            guard task.nextDueDate > now else { continue }
            guard let leadMinutes = leadMinutes(for: task.notificationPreference) else { continue }

            let triggerDate = task.nextDueDate.addingTimeInterval(TimeInterval(-leadMinutes * 60))
            let effectiveTriggerDate = max(triggerDate, now.addingTimeInterval(3))

            let content = UNMutableNotificationContent()
            content.title = leadMinutes == 0 ? "Recurring Task Due Now" : "Recurring Task Due Soon"
            content.body = dueSoonBody(title: task.title, dueDate: task.nextDueDate, leadMinutes: leadMinutes)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, effectiveTriggerDate.timeIntervalSince(now)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(IdentifierPrefix.recurringDueSoon)\(task.id.uuidString)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func leadMinutes(for preference: TaskNotificationPreference?) -> Int? {
        let preference = preference ?? TaskNotificationPreference()

        if preference.usesDefaultSettings {
            guard defaults.bool(forKey: DefaultsKey.dueSoon) else { return nil }
            return defaults.integer(forKey: DefaultsKey.dueSoonLeadMinutes)
        }

        guard preference.customEnabled else { return nil }
        return preference.leadMinutes
    }

    private func scheduleSharedTaskArrival(count: Int, title: String?) async {
        guard defaults.bool(forKey: DefaultsKey.enabled) else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await refreshStatus(settings: settings)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "New Family Task" : "New Family Tasks"

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if count == 1, !trimmedTitle.isEmpty {
            content.body = "\(trimmedTitle) was added to your shared tasks."
        } else {
            content.body = "\(count) tasks were added to your shared family list."
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(IdentifierPrefix.sharedTaskArrival)\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )

        do {
            try await center.add(request)
            await refreshStatus(settings: settings)
        } catch {
            statusMessage = "Could not schedule shared task notification: \(error.localizedDescription)"
        }
    }

    private func digestBody(for tasks: [FamilyTask]) -> String {
        let countText = tasks.count == 1 ? "1 task" : "\(tasks.count) tasks"
        let titles = tasks.prefix(3).map(\.title).joined(separator: ", ")

        if tasks.count > 3 {
            return "\(countText) scheduled: \(titles), and \(tasks.count - 3) more."
        }

        return "\(countText) scheduled: \(titles)."
    }

    private func dueSoonBody(for task: FamilyTask, leadMinutes: Int) -> String {
        dueSoonBody(title: task.title, dueDate: task.dueDate, leadMinutes: leadMinutes)
    }

    private func dueSoonBody(title: String, dueDate: Date?, leadMinutes: Int) -> String {
        let dueText = dueDate?.formatted(date: .omitted, time: .shortened) ?? "soon"

        switch leadMinutes {
        case 0:
            return "\(title) is due now."
        case 1..<60:
            return "\(title) is due in \(leadMinutes) minutes at \(dueText)."
        case 60:
            return "\(title) is due in 1 hour at \(dueText)."
        case let minutes where minutes % 1_440 == 0:
            let days = minutes / 1_440
            let dayText = days == 1 ? "1 day" : "\(days) days"
            return "\(title) is due in \(dayText)."
        default:
            let hours = leadMinutes / 60
            return "\(title) is due in \(hours) hours at \(dueText)."
        }
    }
}

struct NotificationLeadTimeOption: Identifiable {
    let minutes: Int
    let title: String
    let description: String

    var id: Int { minutes }

    static let options = [
        NotificationLeadTimeOption(minutes: 0, title: "At due time", description: "at the due time"),
        NotificationLeadTimeOption(minutes: 15, title: "15 minutes before", description: "15 minutes before the due time"),
        NotificationLeadTimeOption(minutes: 30, title: "30 minutes before", description: "30 minutes before the due time"),
        NotificationLeadTimeOption(minutes: 60, title: "1 hour before", description: "1 hour before the due time"),
        NotificationLeadTimeOption(minutes: 180, title: "3 hours before", description: "3 hours before the due time"),
        NotificationLeadTimeOption(minutes: 1_440, title: "1 day before", description: "1 day before the due date")
    ]
}
