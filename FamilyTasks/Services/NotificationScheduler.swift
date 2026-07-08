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
        static let dueSoonLeadMinutesList = "notifications.dueSoonLeadMinutesList"
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
        let activeTasks = taskStore.exportVisibleTasks().filter { !$0.isDone }
        let activeRecurringTasks = organizerStore?.exportVisibleRecurringTasks().filter(\.isActive) ?? []

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
            DefaultsKey.dueSoonLeadMinutes: 60,
            DefaultsKey.dueSoonLeadMinutesList: "60"
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
                  ) else {
                continue
            }

            let dayTasks = tasksForDigest(on: day, from: tasks, calendar: calendar)
            guard !dayTasks.isEmpty else { continue }

            if triggerDate > now {
                scheduleDigest(for: dayTasks, on: triggerDate, identifierSuffix: digestIdentifierSuffix(for: day, calendar: calendar))
            } else if dayOffset == 0 {
                let catchupDate = now.addingTimeInterval(10)
                scheduleDigest(for: dayTasks, on: catchupDate, identifierSuffix: "\(digestIdentifierSuffix(for: day, calendar: calendar)).catchup")
            }
        }
    }

    private func tasksForDigest(on day: Date, from tasks: [FamilyTask], calendar: Calendar) -> [FamilyTask] {
        tasks
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
    }

    private func scheduleDigest(for tasks: [FamilyTask], on triggerDate: Date, identifierSuffix: String) {
        let calendar = Calendar.current
        let content = UNMutableNotificationContent()
        content.title = "Today's Family Tasks"
        content.body = digestBody(for: tasks)
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(IdentifierPrefix.todayDigest)\(identifierSuffix)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func digestIdentifierSuffix(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func scheduleDueSoonAlerts(for tasks: [FamilyTask]) {
        let now = Date()

        for task in tasks {
            guard let dueDate = task.dueDate else { continue }
            guard dueDate > now else { continue }
            let leadMinuteValues = leadMinutes(for: task.notificationPreference)

            for leadMinutes in leadMinuteValues {
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
                    identifier: "\(IdentifierPrefix.dueSoon)\(task.id.uuidString).\(leadMinutes)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    private func scheduleRecurringDueSoonAlerts(for recurringTasks: [RecurringTask]) {
        let now = Date()

        for task in recurringTasks {
            guard task.nextDueDate > now else { continue }
            let leadMinuteValues = leadMinutes(for: task.notificationPreference)

            for leadMinutes in leadMinuteValues {
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
                    identifier: "\(IdentifierPrefix.recurringDueSoon)\(task.id.uuidString).\(leadMinutes)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    private func leadMinutes(for preference: TaskNotificationPreference?) -> [Int] {
        let preference = preference ?? TaskNotificationPreference()

        if preference.usesDefaultSettings {
            guard defaults.bool(forKey: DefaultsKey.dueSoon) else { return [] }
            return globalDueSoonLeadMinutes
        }

        guard preference.customEnabled else { return [] }
        return preference.selectedLeadMinutes
    }

    private var globalDueSoonLeadMinutes: [Int] {
        let rawList = defaults.string(forKey: DefaultsKey.dueSoonLeadMinutesList) ?? ""
        let parsedList = rawList
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !parsedList.isEmpty {
            return normalizedLeadMinutes(parsedList)
        }
        return normalizedLeadMinutes([defaults.integer(forKey: DefaultsKey.dueSoonLeadMinutes)])
    }

    private func normalizedLeadMinutes(_ values: [Int]) -> [Int] {
        let validValues = Set(NotificationLeadTimeOption.options.map(\.minutes))
        let normalized = Array(Set(values.filter { validValues.contains($0) })).sorted()
        return normalized.isEmpty ? [60] : normalized
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
        case let minutes where minutes % 10_080 == 0:
            let weeks = minutes / 10_080
            let weekText = weeks == 1 ? "1 week" : "\(weeks) weeks"
            return "\(title) is due in \(weekText)."
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

    static let options: [NotificationLeadTimeOption] = {
        let minuteOptions = [15, 30, 45].map { minutes in
            NotificationLeadTimeOption(
                minutes: minutes,
                title: "\(minutes) minutes before",
                description: "\(minutes) minutes before the due time"
            )
        }

        let hourOptions = (1...24).map { hours in
            NotificationLeadTimeOption(
                minutes: hours * 60,
                title: hours == 1 ? "1 hour before" : "\(hours) hours before",
                description: hours == 1 ? "1 hour before the due time" : "\(hours) hours before the due time"
            )
        }

        let dayOptions = (1...7).map { days in
            NotificationLeadTimeOption(
                minutes: days * 1_440,
                title: days == 1 ? "1 day before" : "\(days) days before",
                description: days == 1 ? "1 day before the due date" : "\(days) days before the due date"
            )
        }

        let weekOptions = (1...4).map { weeks in
            NotificationLeadTimeOption(
                minutes: weeks * 10_080,
                title: weeks == 1 ? "1 week before" : "\(weeks) weeks before",
                description: weeks == 1 ? "1 week before the due date" : "\(weeks) weeks before the due date"
            )
        }

        return minuteOptions + hourOptions + dayOptions + weekOptions
    }()
}
