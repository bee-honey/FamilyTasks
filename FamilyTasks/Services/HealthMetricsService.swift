import Foundation
import HealthKit
import BackgroundTasks


struct HealthSnapshot: Identifiable, Codable, Equatable {
    var id: String
    var memberEmail: String
    var memberInitials: String
    var date: Date
    var dayID: String
    var steps: Double
    var sleepSeconds: TimeInterval
    var updatedAt: Date

    init(
        memberEmail: String,
        memberInitials: String,
        date: Date,
        dayID: String,
        steps: Double,
        sleepSeconds: TimeInterval,
        updatedAt: Date = Date()
    ) {
        let normalizedEmail = memberEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.id = "\(normalizedEmail)|\(dayID)"
        self.memberEmail = normalizedEmail
        self.memberInitials = memberInitials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.date = date
        self.dayID = dayID
        self.steps = steps
        self.sleepSeconds = sleepSeconds
        self.updatedAt = updatedAt
    }

    var displayInitials: String {
        let trimmed = memberInitials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(3)).uppercased()
        }

        let localPart = memberEmail.split(separator: "@").first.map(String.init) ?? ""
        let parts = localPart.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == " " })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }
}

struct HealthMetricSummary: Identifiable, Equatable {
    var id: String { scope.rawValue }
    let scope: HealthMetricScope
    let steps: Double
    let sleepSeconds: TimeInterval
    let points: [HealthMetricPoint]

    var stepText: String {
        Self.stepText(for: steps)
    }

    var sleepText: String {
        Self.sleepText(for: sleepSeconds)
    }

    static func stepText(for steps: Double) -> String {
        steps.formatted(.number.precision(.fractionLength(0)))
    }

    static func sleepText(for sleepSeconds: TimeInterval) -> String {
        let hours = sleepSeconds / 3_600
        return hours.formatted(.number.precision(.fractionLength(1))) + " hr"
    }
}

struct HealthMetricPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let steps: Double
    let sleepSeconds: TimeInterval
}

enum HealthMetricScope: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
}


@MainActor
final class HealthSyncCoordinator {
    static let shared = HealthSyncCoordinator()
    static let backgroundTaskIdentifier = "com.naveenkeerthy.FamilyTasks.healthDailySync"

    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let healthSectionEnabled = "health.section.enabled"
        static let healthSharingEnabled = "health.share.enabled"
        static let lastDailySyncDayID = "health.lastDailySyncDayID"
    }

    private init() {}

    var isHealthSharingEnabled: Bool {
        defaults.bool(forKey: DefaultsKey.healthSectionEnabled) && defaults.bool(forKey: DefaultsKey.healthSharingEnabled)
    }

    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                await self.handleBackgroundRefresh(task: task as? BGAppRefreshTask)
            }
        }
    }

    func scheduleDailyRefresh() {
        guard isHealthSharingEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = nextSixAM(after: Date())
        try? BGTaskScheduler.shared.submit(request)
    }

    func syncIfNeeded(
        taskStore: TaskStore,
        organizerStore: OrganizerStore,
        sharedHouseholdStore: SharedHouseholdStore,
        force: Bool = false
    ) async {
        guard isHealthSharingEnabled else { return }
        guard shouldSyncToday(force: force) else {
            scheduleDailyRefresh()
            return
        }

        await publishSnapshots(taskStore: taskStore, organizerStore: organizerStore, sharedHouseholdStore: sharedHouseholdStore)
    }

    func syncNow(
        taskStore: TaskStore,
        organizerStore: OrganizerStore,
        sharedHouseholdStore: SharedHouseholdStore
    ) async {
        guard isHealthSharingEnabled else { return }
        await publishSnapshots(taskStore: taskStore, organizerStore: organizerStore, sharedHouseholdStore: sharedHouseholdStore)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask?) async {
        scheduleDailyRefresh()

        let taskStore = TaskStore()
        let organizerStore = OrganizerStore()
        let sharedHouseholdStore = SharedHouseholdStore.shared
        sharedHouseholdStore.configure(taskStore: taskStore, organizerStore: organizerStore)

        let syncTask = Task { @MainActor in
            await self.syncIfNeeded(
                taskStore: taskStore,
                organizerStore: organizerStore,
                sharedHouseholdStore: sharedHouseholdStore,
                force: true
            )
        }

        task?.expirationHandler = {
            syncTask.cancel()
        }

        await syncTask.value
        task?.setTaskCompleted(success: !syncTask.isCancelled)
    }

    private func publishSnapshots(
        taskStore: TaskStore,
        organizerStore: OrganizerStore,
        sharedHouseholdStore: SharedHouseholdStore
    ) async {
        let email = (defaults.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard TaskStore.isValidEmail(email) else { return }

        let initials = defaults.string(forKey: "profile.initials") ?? ""
        let service = HealthMetricsService()
        let snapshots = await service.dailySnapshots(memberEmail: email, memberInitials: initials)
        guard !snapshots.isEmpty else {
            scheduleDailyRefresh()
            return
        }

        await sharedHouseholdStore.refreshFromCloud()
        organizerStore.upsertHealthSnapshots(snapshots)
        if sharedHouseholdStore.isSharingConfigured {
            await sharedHouseholdStore.uploadNow()
        }

        defaults.set(todayDayID(), forKey: DefaultsKey.lastDailySyncDayID)
        scheduleDailyRefresh()
    }

    private func shouldSyncToday(force: Bool) -> Bool {
        if force { return true }

        let now = Date()
        guard now >= sixAM(on: now) else { return false }
        return defaults.string(forKey: DefaultsKey.lastDailySyncDayID) != todayDayID()
    }

    private func sixAM(on date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 6
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    private func nextSixAM(after date: Date) -> Date {
        let todaySix = sixAM(on: date)
        if date < todaySix { return todaySix }
        return Calendar.current.date(byAdding: .day, value: 1, to: todaySix) ?? date.addingTimeInterval(86_400)
    }

    private func todayDayID() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

@MainActor
final class HealthMetricsService: ObservableObject {
    @Published private(set) var authorizationStatus = "Health access not requested."
    @Published private(set) var summaries: [HealthMetricSummary] = []
    @Published private(set) var isLoading = false

    private let healthStore = HKHealthStore()

    var isHealthAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAccessAndRefresh() async {
        guard isHealthAvailable else {
            authorizationStatus = "Health data is not available on this device."
            return
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            authorizationStatus = "Steps or sleep data is not available."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType, sleepType])
            authorizationStatus = "Health access allowed for this device."
            await refresh()
        } catch {
            authorizationStatus = "Health access failed: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard isHealthAvailable else {
            authorizationStatus = "Health data is not available on this device."
            return
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            authorizationStatus = "Steps or sleep data is not available."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()
        var nextSummaries: [HealthMetricSummary] = []

        for scope in HealthMetricScope.allCases {
            let intervals = detailIntervals(for: scope, now: now, calendar: calendar)
            var points: [HealthMetricPoint] = []

            for interval in intervals {
                async let steps = stepCount(type: stepType, start: interval.interval.start, end: interval.interval.end)
                async let sleep = sleepDuration(type: sleepType, start: interval.interval.start, end: interval.interval.end)
                points.append(await HealthMetricPoint(
                    id: interval.id,
                    date: interval.interval.start,
                    title: interval.title,
                    steps: steps,
                    sleepSeconds: sleep
                ))
            }

            let totalSteps = points.reduce(0) { $0 + $1.steps }
            let totalSleep = points.reduce(0) { $0 + $1.sleepSeconds }
            nextSummaries.append(HealthMetricSummary(scope: scope, steps: totalSteps, sleepSeconds: totalSleep, points: points))
        }

        summaries = nextSummaries
    }

    func dailySnapshots(memberEmail: String, memberInitials: String, daysBack: Int = 370) async -> [HealthSnapshot] {
        guard isHealthAvailable else { return [] }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let trimmedEmail = memberEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -max(daysBack, 0), to: today) ?? today
        let intervals = dayIntervals(from: start, through: now, calendar: calendar, style: .dayNumber)

        var snapshots: [HealthSnapshot] = []
        for interval in intervals {
            async let steps = stepCount(type: stepType, start: interval.interval.start, end: interval.interval.end)
            async let sleep = sleepDuration(type: sleepType, start: interval.interval.start, end: interval.interval.end)
            snapshots.append(await HealthSnapshot(
                memberEmail: trimmedEmail,
                memberInitials: memberInitials,
                date: interval.interval.start,
                dayID: interval.id,
                steps: steps,
                sleepSeconds: sleep
            ))
        }

        return snapshots
    }

    private func detailIntervals(for scope: HealthMetricScope, now: Date, calendar: Calendar) -> [HealthDetailInterval] {
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: now)
            return [HealthDetailInterval(id: dayID(for: start, calendar: calendar), title: "Today", interval: DateInterval(start: start, end: now))]
        case .week:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return dayIntervals(from: weekStart, through: now, calendar: calendar, style: .weekdayAndDate)
        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            return dayIntervals(from: monthStart, through: now, calendar: calendar, style: .dayNumber)
        case .year:
            let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            return monthIntervals(from: yearStart, through: now, calendar: calendar)
        }
    }

    private func dayIntervals(from start: Date, through now: Date, calendar: Calendar, style: DayTitleStyle) -> [HealthDetailInterval] {
        var values: [HealthDetailInterval] = []
        var day = calendar.startOfDay(for: start)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE M/d"

        while day <= now {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let end = min(nextDay, now)
            let dayNumber = calendar.component(.day, from: day)
            let title = style == .weekdayAndDate ? weekdayFormatter.string(from: day) : "\(dayNumber)"
            values.append(HealthDetailInterval(id: dayID(for: day, calendar: calendar), title: title, interval: DateInterval(start: day, end: end)))
            day = nextDay
        }
        return values
    }

    private func monthIntervals(from start: Date, through now: Date, calendar: Calendar) -> [HealthDetailInterval] {
        var values: [HealthDetailInterval] = []
        var month = calendar.dateInterval(of: .month, for: start)?.start ?? start
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        while month <= now {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) ?? month.addingTimeInterval(2_592_000)
            let end = min(nextMonth, now)
            values.append(HealthDetailInterval(id: monthID(for: month, calendar: calendar), title: formatter.string(from: month), interval: DateInterval(start: month, end: end)))
            month = nextMonth
        }
        return values
    }

    private func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func monthID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private enum DayTitleStyle {
        case dayNumber
        case weekdayAndDate
    }

    private struct HealthDetailInterval {
        let id: String
        let title: String
        let interval: DateInterval
    }
    private func stepCount(type: HKQuantityType, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func sleepDuration(type: HKCategoryType, start: Date, end: Date) async -> TimeInterval {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]

                let duration = sleepSamples.reduce(TimeInterval(0)) { total, sample in
                    guard asleepValues.contains(sample.value) else { return total }
                    let clippedStart = max(sample.startDate, start)
                    let clippedEnd = min(sample.endDate, end)
                    return total + max(0, clippedEnd.timeIntervalSince(clippedStart))
                }
                continuation.resume(returning: duration)
            }
            healthStore.execute(query)
        }
    }
}
