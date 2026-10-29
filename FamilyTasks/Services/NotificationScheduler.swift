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
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let enabled = "notifications.enabled"
        static let todayDigest = "notifications.todayDigest"
        static let dueSoon = "notifications.dueSoon"
        static let todayDigestHour = "notifications.todayDigestHour"
        static let todayDigestMinute = "notifications.todayDigestMinute"
        static let eveningDigest = "notifications.eveningDigest"
        static let eveningDigestHour = "notifications.eveningDigestHour"
        static let eveningDigestMinute = "notifications.eveningDigestMinute"
        static let dueSoonLeadMinutes = "notifications.dueSoonLeadMinutes"
        static let dueSoonLeadMinutesList = "notifications.dueSoonLeadMinutesList"
        /// Today's lists ("2026-10-13.morning") already scheduled or caught up, so none is sent twice.
        static let dailyListsHandled = "notifications.dailyListsHandled"
        static let familyCompletions = "notifications.familyCompletions"
        static let taskChanges = "notifications.taskChanges"
        static let familyShopping = "notifications.familyShopping"
        static let familyHabits = "notifications.familyHabits"
        static let familyHealth = "notifications.familyHealth"
    }

    /// iOS keeps at most 64 pending local notifications per app; leave room for
    /// test and shared-task alerts. Health reminders come out of this too.
    private static let maxScheduledAlerts = 58
    /// Tips are scheduled a few days ahead, each its own notification so each day's differs.
    private static let tipDays = 3

    private enum IdentifierPrefix {
        static let todayDigest = "familytasks.todayDigest."
        static let dueSoon = "familytasks.dueSoon."
        static let recurringDueSoon = "familytasks.recurringDueSoon."
        static let shoppingDone = "familytasks.shoppingDone."
        static let windDown = "familytasks.windDown."
        static let healthTip = "familytasks.healthTip."
    }

    private init() {
        registerDefaults()
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

        // A catch-up digest is a one-off for the day; leave it alone if it is still pending.
        let pendingIdentifiers = await pendingFamilyTaskIdentifiers()
            .filter { !$0.hasSuffix(".catchup") }
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)

        let healthRequests = healthRoutineRequests(now: Date())
        for request in healthRequests {
            try? await center.add(request)
        }

        guard let taskStore else { return }
        let activeTasks = taskStore.exportVisibleTasks().filter { !$0.isDone }
        let activeRecurringTasks = organizerStore?.exportVisibleRecurringTasks().filter(\.isActive) ?? []

        var alerts = dailyListAlerts(tasks: activeTasks, recurringTasks: activeRecurringTasks)
        alerts += dueSoonAlerts(for: activeTasks)
        alerts += recurringDueSoonAlerts(for: activeRecurringTasks)

        for alert in alerts.sorted(by: { $0.fireDate < $1.fireDate }).prefix(Self.maxScheduledAlerts - healthRequests.count) {
            try? await center.add(alert.request)
        }

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
            DefaultsKey.familyCompletions: true,
            DefaultsKey.familyShopping: true,
            DefaultsKey.familyHabits: true,
            DefaultsKey.familyHealth: true,
            WindDownSettings.bedtimeHourKey: WindDownSettings.defaultBedtimeHour,
            WindDownSettings.bedtimeMinuteKey: WindDownSettings.defaultBedtimeMinute,
            WindDownSettings.dailyTipHourKey: WindDownSettings.defaultTipHour,
            WindDownStep.food.settingsKey: true,
            WindDownStep.drinks.settingsKey: true,
            WindDownStep.screens.settingsKey: true,
            DefaultsKey.todayDigestHour: 8,
            DefaultsKey.todayDigestMinute: 0,
            DefaultsKey.eveningDigest: true,
            DefaultsKey.eveningDigestHour: 20,
            DefaultsKey.eveningDigestMinute: 0,
            DefaultsKey.taskChanges: true,
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
                $0.hasPrefix(IdentifierPrefix.shoppingDone) ||
                $0.hasPrefix(IdentifierPrefix.windDown) ||
                $0.hasPrefix(IdentifierPrefix.healthTip)
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

    private struct ScheduledAlert {
        let fireDate: Date
        let request: UNNotificationRequest
    }

    /// A morning or evening reminder of this person's open tasks.
    private struct DailyListSlot {
        var id: String
        var hour: Int
        var minute: Int
        var title: (Int) -> String
    }

    private var dailyListSlots: [DailyListSlot] {
        var slots: [DailyListSlot] = []
        if defaults.bool(forKey: DefaultsKey.todayDigest) {
            slots.append(DailyListSlot(
                id: "morning",
                hour: defaults.integer(forKey: DefaultsKey.todayDigestHour),
                minute: defaults.integer(forKey: DefaultsKey.todayDigestMinute),
                title: { $0 == 1 ? "Your task today" : "Your \($0) tasks today" }
            ))
        }
        if defaults.bool(forKey: DefaultsKey.eveningDigest) {
            slots.append(DailyListSlot(
                id: "evening",
                hour: defaults.integer(forKey: DefaultsKey.eveningDigestHour),
                minute: defaults.integer(forKey: DefaultsKey.eveningDigestMinute),
                title: { $0 == 1 ? "Still to do: 1 task" : "Still to do: \($0) tasks" }
            ))
        }
        return slots
    }

    /// Two weeks of morning and evening lists, each holding what will still be open then
    /// if nothing changes. Any change reschedules them, so a finished task drops off.
    private func dailyListAlerts(tasks: [FamilyTask], recurringTasks: [RecurringTask]) -> [ScheduledAlert] {
        let calendar = Calendar.current
        let now = Date()
        let viewer = defaults.string(forKey: "profile.email") ?? ""
        let todaySuffix = digestIdentifierSuffix(for: now, calendar: calendar)
        var handled = (defaults.stringArray(forKey: DefaultsKey.dailyListsHandled) ?? []).filter { $0.hasPrefix(todaySuffix) }
        var alerts: [ScheduledAlert] = []
        var latestMissedToday: (slot: DailyListSlot, list: DailyTaskList, time: Date)?

        for dayOffset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let list = DailyTaskList.make(on: day, tasks: tasks, recurringTasks: recurringTasks, viewer: viewer, calendar: calendar)
            guard !list.entries.isEmpty else { continue }
            let daySuffix = digestIdentifierSuffix(for: day, calendar: calendar)

            for slot in dailyListSlots {
                guard let triggerDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day) else { continue }
                if triggerDate > now {
                    if dayOffset == 0 { handled.append("\(daySuffix).\(slot.id)") }
                    alerts.append(dailyListAlert(list, title: slot.title(list.entries.count), on: triggerDate, identifierSuffix: "\(daySuffix).\(slot.id)"))
                } else if dayOffset == 0, triggerDate > latestMissedToday?.time ?? .distantPast {
                    latestMissedToday = (slot, list, triggerDate)
                }
            }
        }

        // Today's latest list time passed before one was scheduled for it (e.g. first launch
        // after it): send it once.
        if let missed = latestMissedToday {
            let catchupKey = "\(todaySuffix).\(missed.slot.id)"
            if !handled.contains(catchupKey) {
                handled.append(catchupKey)
                alerts.append(dailyListAlert(
                    missed.list,
                    title: missed.slot.title(missed.list.entries.count),
                    on: now.addingTimeInterval(10),
                    identifierSuffix: "\(catchupKey).catchup"
                ))
            }
        }

        defaults.set(Array(Set(handled)).sorted(), forKey: DefaultsKey.dailyListsHandled)
        return alerts
    }

    // MARK: Health

    /// The 3-2-1 wind-down reminders, repeating every night, and the next few days' tips.
    private func healthRoutineRequests(now: Date) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        var requests: [UNNotificationRequest] = []

        if defaults.bool(forKey: WindDownSettings.enabledKey) {
            let hour = defaults.integer(forKey: WindDownSettings.bedtimeHourKey)
            let minute = defaults.integer(forKey: WindDownSettings.bedtimeMinuteKey)
            let bedtime = WindDownSettings.timeText(hour: hour, minute: minute, calendar: calendar)
            for step in WindDownStep.allCases where defaults.bool(forKey: step.settingsKey) {
                let time = step.time(bedtimeHour: hour, bedtimeMinute: minute)
                let content = UNMutableNotificationContent()
                content.title = step.notificationTitle
                content.body = step.notificationBody(bedtime: bedtime)
                content.sound = .default
                requests.append(UNNotificationRequest(
                    identifier: "\(IdentifierPrefix.windDown)\(step.rawValue)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
                ))
            }
        }

        if defaults.bool(forKey: WindDownSettings.dailyTipKey) {
            let hour = defaults.integer(forKey: WindDownSettings.dailyTipHourKey)
            let minute = defaults.integer(forKey: WindDownSettings.dailyTipMinuteKey)
            for offset in 0..<Self.tipDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      fireDate > now else { continue }
                let tip = HealthTips.tip(for: day, calendar: calendar)
                let content = UNMutableNotificationContent()
                content.title = "Tip: \(tip.title)"
                content.body = tip.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                requests.append(UNNotificationRequest(
                    identifier: "\(IdentifierPrefix.healthTip)\(digestIdentifierSuffix(for: day, calendar: calendar))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }
        }
        return requests
    }

    private func dailyListAlert(_ list: DailyTaskList, title: String, on triggerDate: Date, identifierSuffix: String) -> ScheduledAlert {
        let calendar = Calendar.current
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = list.body
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(IdentifierPrefix.todayDigest)\(identifierSuffix)",
            content: content,
            trigger: trigger
        )
        return ScheduledAlert(fireDate: triggerDate, request: request)
    }

    private func digestIdentifierSuffix(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dueSoonAlerts(for tasks: [FamilyTask]) -> [ScheduledAlert] {
        tasks.flatMap { task -> [ScheduledAlert] in
            guard let dueDate = task.dueDate else { return [] }
            return leadTimeAlerts(
                identifierBase: "\(IdentifierPrefix.dueSoon)\(task.id.uuidString)",
                title: task.title,
                dueDate: dueDate,
                leadMinuteValues: leadMinutes(for: task.notificationPreference),
                titles: (now: "Task Due Now", soon: "Task Due Soon")
            )
        }
    }

    private func recurringDueSoonAlerts(for recurringTasks: [RecurringTask]) -> [ScheduledAlert] {
        recurringTasks.flatMap { task in
            leadTimeAlerts(
                identifierBase: "\(IdentifierPrefix.recurringDueSoon)\(task.id.uuidString)",
                title: task.title,
                dueDate: task.nextDueDate,
                leadMinuteValues: leadMinutes(for: task.notificationPreference),
                titles: (now: "Recurring Task Due Now", soon: "Recurring Task Due Soon")
            )
        }
    }

    /// Builds one alert per lead time that is still in the future. Lead times that have
    /// already passed are skipped (rescheduling happens on every change, so firing them
    /// "now" would repeat them); if none remain, a single alert fires at the due time.
    private func leadTimeAlerts(
        identifierBase: String,
        title: String,
        dueDate: Date,
        leadMinuteValues: [Int],
        titles: (now: String, soon: String)
    ) -> [ScheduledAlert] {
        let now = Date()
        return Self.leadTimeFireDates(dueDate: dueDate, leadMinuteValues: leadMinuteValues, now: now).map { leadMinutes, triggerDate in
            let content = UNMutableNotificationContent()
            content.title = leadMinutes == 0 ? titles.now : titles.soon
            content.body = dueSoonBody(title: title, dueDate: dueDate, leadMinutes: leadMinutes)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(identifierBase).\(leadMinutes)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, triggerDate.timeIntervalSince(now)), repeats: false)
            )
            return ScheduledAlert(fireDate: triggerDate, request: request)
        }
    }

    /// Which lead-time alerts to schedule and when. Lead times that have already passed
    /// are dropped; if none remain but the task is still upcoming, one alert fires at the
    /// due time.
    nonisolated static func leadTimeFireDates(
        dueDate: Date,
        leadMinuteValues: [Int],
        now: Date
    ) -> [(leadMinutes: Int, fireDate: Date)] {
        guard dueDate > now, !leadMinuteValues.isEmpty else { return [] }

        var upcoming = leadMinuteValues.filter { dueDate.addingTimeInterval(TimeInterval(-$0 * 60)) > now }
        if upcoming.isEmpty {
            upcoming = [0]
        }
        return upcoming.map { ($0, dueDate.addingTimeInterval(TimeInterval(-$0 * 60))) }
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
