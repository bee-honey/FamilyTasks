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
    // Optional, so summaries from older versions still read. Heart and body numbers are
    // only shared when their owner turns that on.
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var sleepScore: Int?
    var restingHeartRate: Double?
    var hrv: Double?
    var vo2Max: Double?
    var weightKg: Double?
    var bmi: Double?

    init(
        memberEmail: String,
        memberInitials: String,
        date: Date,
        dayID: String,
        steps: Double,
        sleepSeconds: TimeInterval,
        updatedAt: Date = Date(),
        activeEnergy: Double? = nil,
        exerciseMinutes: Double? = nil,
        sleepScore: Int? = nil,
        restingHeartRate: Double? = nil,
        hrv: Double? = nil,
        vo2Max: Double? = nil,
        weightKg: Double? = nil,
        bmi: Double? = nil
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
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.sleepScore = sleepScore
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.vo2Max = vo2Max
        self.weightKg = weightKg
        self.bmi = bmi
    }

    /// The same day with heart or body numbers left out, for sharing.
    func sharing(heart: Bool, body: Bool) -> HealthSnapshot {
        var copy = self
        if !heart {
            copy.restingHeartRate = nil
            copy.hrv = nil
            copy.vo2Max = nil
        }
        if !body {
            copy.weightKg = nil
            copy.bmi = nil
        }
        return copy
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
        static let lastQuickSync = "health.lastQuickSync"
    }

    static let shareHeartKey = "health.share.heart"
    static let shareBodyKey = "health.share.body"
    /// How often opening Health sends today's numbers, so the family dashboard keeps up
    /// during the day without uploading on every visit.
    private static let quickSyncInterval: TimeInterval = 20 * 60

    private init() {}

    var isHealthSharingEnabled: Bool {
        defaults.bool(forKey: DefaultsKey.healthSectionEnabled) && defaults.bool(forKey: DefaultsKey.healthSharingEnabled)
    }

    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: .main) { task in
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

    /// Sends the last week, today included, if it's been a while since the last send.
    func syncRecentIfStale(
        taskStore: TaskStore,
        organizerStore: OrganizerStore,
        sharedHouseholdStore: SharedHouseholdStore
    ) async {
        guard isHealthSharingEnabled else { return }
        if let last = defaults.object(forKey: DefaultsKey.lastQuickSync) as? Date,
           Date().timeIntervalSince(last) < Self.quickSyncInterval {
            return
        }
        defaults.set(Date(), forKey: DefaultsKey.lastQuickSync)
        await publishSnapshots(taskStore: taskStore, organizerStore: organizerStore, sharedHouseholdStore: sharedHouseholdStore, daysBack: 7)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask?) async {
        scheduleDailyRefresh()

        let taskStore = TaskStore.shared
        let organizerStore = OrganizerStore.shared
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
        sharedHouseholdStore: SharedHouseholdStore,
        daysBack: Int = 370
    ) async {
        let email = (defaults.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard TaskStore.isValidEmail(email) else { return }

        let initials = defaults.string(forKey: "profile.initials") ?? ""
        let service = HealthMetricsService()
        let shareHeart = defaults.bool(forKey: Self.shareHeartKey)
        let shareBody = defaults.bool(forKey: Self.shareBodyKey)
        let snapshots = await service.dailySnapshots(memberEmail: email, memberInitials: initials, daysBack: daysBack)
            .map { $0.sharing(heart: shareHeart, body: shareBody) }
        guard !snapshots.isEmpty else {
            scheduleDailyRefresh()
            return
        }

        organizerStore.upsertHealthSnapshots(snapshots)
        if sharedHouseholdStore.isSharingConfigured {
            await sharedHouseholdStore.uploadNow()
        }

        if daysBack >= 370 {
            defaults.set(todayDayID(), forKey: DefaultsKey.lastDailySyncDayID)
        }
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

/// A measurement and when it was taken, such as the latest weight.
struct HealthReading: Equatable {
    var value: Double
    var date: Date
}

@MainActor
final class HealthMetricsService: ObservableObject {
    @Published private(set) var authorizationStatus = "Health access not requested."
    @Published private(set) var summaries: [HealthMetricSummary] = []
    /// This person's last five weeks, one summary a day, today last.
    @Published private(set) var recentDays: [HealthSnapshot] = []
    /// The night that ended this morning, with stages when the watch recorded them.
    @Published private(set) var lastNight: SleepNight?
    @Published private(set) var height: HealthReading?
    @Published private(set) var weight: HealthReading?
    /// Whether any recent night came with deep or REM sleep.
    @Published private(set) var receivesSleepStages = false
    @Published private(set) var isLoading = false

    private let healthStore = HKHealthStore()

    /// Raised when more kinds of data are read, so people who allowed the earlier ones are
    /// asked once about the new ones.
    private static let readTypesVersion = 2
    private static let readTypesVersionKey = "health.readTypesVersion"
    static let recentDayCount = 35

    var isHealthAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .appleExerciseTime,
            .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
            .bodyMass, .height,
        ]
        var types = Set<HKObjectType>(quantities.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAccessAndRefresh() async {
        guard isHealthAvailable else {
            authorizationStatus = "Health data is not available on this device."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(Self.readTypesVersion, forKey: Self.readTypesVersionKey)
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

        if UserDefaults.standard.integer(forKey: Self.readTypesVersionKey) < Self.readTypesVersion {
            // iOS only asks about the kinds not answered yet.
            try? await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(Self.readTypesVersion, forKey: Self.readTypesVersionKey)
        }

        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -(Self.recentDayCount - 1), to: today) ?? today
        let intervalsByScope = HealthMetricScope.allCases.map { scope in
            (scope, detailIntervals(for: scope, now: now, calendar: calendar))
        }
        let earliest = min(intervalsByScope.flatMap(\.1).map(\.interval.start).min() ?? today, recentStart)
        async let latestHeight = latestReading(.height, unit: .meter())
        async let latestWeight = latestReading(.bodyMass, unit: .gramUnit(with: .kilo))
        let data = await fetchHealthData(from: earliest, now: now, calendar: calendar)
        let height = await latestHeight
        let weight = await latestWeight

        summaries = intervalsByScope.map { scope, intervals in
            let points = intervals.map { interval in
                HealthMetricPoint(
                    id: interval.id,
                    date: interval.interval.start,
                    title: interval.title,
                    steps: data.steps(in: interval.interval, calendar: calendar),
                    sleepSeconds: data.sleep(in: interval.interval, now: now)
                )
            }
            let totalSteps = points.reduce(0) { $0 + $1.steps }
            let totalSleep = points.reduce(0) { $0 + $1.sleepSeconds }
            return HealthMetricSummary(scope: scope, steps: totalSteps, sleepSeconds: totalSleep, points: points)
        }
        recentDays = dayIntervals(from: recentStart, through: now, calendar: calendar, style: .dayNumber).map {
            snapshot(for: $0, data: data, memberEmail: HabitStore.currentProfileEmail(), memberInitials: "", heightMeters: height?.value, now: now)
        }
        lastNight = data.night(in: DateInterval(start: today, end: now), now: now)
        receivesSleepStages = !data.restorative.isEmpty
        self.height = height
        self.weight = weight
        await refreshAccessStatus()
    }

    /// Whether Family Tasks has asked for everything it reads. iOS doesn't say what was
    /// allowed, only whether there's anything left to ask.
    func refreshAccessStatus() async {
        guard isHealthAvailable else { return }
        let status = try? await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        switch status {
        case .unnecessary:
            authorizationStatus = "You've answered Family Tasks' request for Health access. To change what it can read, use the Health app."
        case .shouldRequest:
            authorizationStatus = "Some Health data hasn't been asked for yet. Tap Allow Health Access."
        default:
            authorizationStatus = "Health access status is unknown."
        }
    }

    func dailySnapshots(memberEmail: String, memberInitials: String, daysBack: Int = 370) async -> [HealthSnapshot] {
        guard isHealthAvailable else { return [] }

        let trimmedEmail = memberEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -max(daysBack, 0), to: today) ?? today
        let intervals = dayIntervals(from: start, through: now, calendar: calendar, style: .dayNumber)
        async let height = latestReading(.height, unit: .meter())
        let data = await fetchHealthData(from: start, now: now, calendar: calendar)
        let heightMeters = await height?.value

        return intervals.map {
            snapshot(for: $0, data: data, memberEmail: trimmedEmail, memberInitials: memberInitials, heightMeters: heightMeters, now: now)
        }
    }

    private func snapshot(
        for interval: HealthDetailInterval,
        data: HealthRangeData,
        memberEmail: String,
        memberInitials: String,
        heightMeters: Double?,
        now: Date
    ) -> HealthSnapshot {
        let day = interval.interval.start
        let night = data.night(in: interval.interval, now: now)
        let weight = data.weightByDay[day]
        return HealthSnapshot(
            memberEmail: memberEmail,
            memberInitials: memberInitials,
            date: day,
            dayID: interval.id,
            steps: data.stepsByDay[day] ?? 0,
            sleepSeconds: night.asleep,
            activeEnergy: data.activeEnergyByDay[day],
            exerciseMinutes: data.exerciseByDay[day],
            sleepScore: SleepScore.score(for: night),
            restingHeartRate: data.restingHeartRateByDay[day],
            hrv: data.hrvByDay[day],
            vo2Max: data.vo2MaxByDay[day],
            weightKg: weight,
            bmi: weight.flatMap { kg in heightMeters.flatMap { BodyMath.bmi(weightKg: kg, heightMeters: $0) } }
        )
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

    /// Daily totals and averages plus merged sleep periods for the whole range, fetched
    /// once; per-day/week/month numbers are then worked out in memory.
    struct HealthRangeData {
        let stepsByDay: [Date: Double]
        let asleep: [DateInterval]
        /// Deep and REM sleep, from sources that record stages.
        var restorative: [DateInterval] = []
        /// Awake in the night, from sources that record stages.
        var awake: [DateInterval] = []
        var activeEnergyByDay: [Date: Double] = [:]
        var exerciseByDay: [Date: Double] = [:]
        var restingHeartRateByDay: [Date: Double] = [:]
        var hrvByDay: [Date: Double] = [:]
        var vo2MaxByDay: [Date: Double] = [:]
        var weightByDay: [Date: Double] = [:]

        func steps(in interval: DateInterval, calendar: Calendar) -> Double {
            stepsByDay.reduce(0) { total, entry in
                entry.key >= interval.start && entry.key < interval.end ? total + entry.value : total
            }
        }

        func sleep(in interval: DateInterval, now: Date) -> TimeInterval {
            let window = HealthMetricsService.sleepWindow(start: interval.start, end: interval.end, now: now)
            return HealthMetricsService.totalDuration(of: asleep, in: window)
        }

        /// The night counted toward the day `interval` starts on. Stages only count when
        /// that night has some deep or REM sleep recorded, since sources without stages
        /// record neither.
        func night(in interval: DateInterval, now: Date) -> SleepNight {
            let window = HealthMetricsService.sleepWindow(start: interval.start, end: interval.end, now: now)
            let asleepTime = HealthMetricsService.totalDuration(of: asleep, in: window)
            let restorativeTime = HealthMetricsService.totalDuration(of: restorative, in: window)
            guard restorativeTime > 0 else { return SleepNight(asleep: asleepTime) }
            let inBed = HealthMetricsService.totalDuration(of: HealthMetricsService.mergedIntervals(asleep + awake), in: window)
            return SleepNight(asleep: asleepTime, deepAndREM: restorativeTime, awake: max(0, inBed - asleepTime))
        }
    }

    private func fetchHealthData(from start: Date, now: Date, calendar: Calendar) async -> HealthRangeData {
        let dayStart = calendar.startOfDay(for: start)
        let end = max(now, dayStart)
        async let steps = dailyStatistics(.stepCount, unit: .count(), cumulative: true, from: dayStart, to: end, calendar: calendar)
        async let energy = dailyStatistics(.activeEnergyBurned, unit: .kilocalorie(), cumulative: true, from: dayStart, to: end, calendar: calendar)
        async let exercise = dailyStatistics(.appleExerciseTime, unit: .minute(), cumulative: true, from: dayStart, to: end, calendar: calendar)
        async let resting = dailyStatistics(.restingHeartRate, unit: .count().unitDivided(by: .minute()), cumulative: false, from: dayStart, to: end, calendar: calendar)
        async let hrv = dailyStatistics(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), cumulative: false, from: dayStart, to: end, calendar: calendar)
        async let vo2Max = dailyStatistics(.vo2Max, unit: HKUnit(from: "ml/kg*min"), cumulative: false, from: dayStart, to: end, calendar: calendar)
        async let weight = dailyStatistics(.bodyMass, unit: .gramUnit(with: .kilo), cumulative: false, from: dayStart, to: end, calendar: calendar)
        async let sleep = sleepPeriods(overlapping: DateInterval(start: dayStart.addingTimeInterval(Self.sleepDayOffset), end: end))
        let periods = await sleep
        return await HealthRangeData(
            stepsByDay: steps,
            asleep: periods.asleep,
            restorative: periods.restorative,
            awake: periods.awake,
            activeEnergyByDay: energy,
            exerciseByDay: exercise,
            restingHeartRateByDay: resting,
            hrvByDay: hrv,
            vo2MaxByDay: vo2Max,
            weightByDay: weight
        )
    }

    /// A value per day from `start` to `end`: the day's total for steps and the like, the
    /// day's average for heart rate and weight. Days with no data are left out.
    private func dailyStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        cumulative: Bool,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) async -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: cumulative ? .cumulativeSum : .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity() else { return }
                    values[calendar.startOfDay(for: statistics.startDate), default: 0] += quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// The most recent sample of a measurement, such as height.
    private func latestReading(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> HealthReading? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [newestFirst]) { _, samples, _ in
                let reading = (samples?.first as? HKQuantitySample).map {
                    HealthReading(value: $0.quantity.doubleValue(for: unit), date: $0.endDate)
                }
                continuation.resume(returning: reading)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static let sleepDayOffset: TimeInterval = -6 * 3_600

    nonisolated static func sleepWindow(start: Date, end: Date, now: Date) -> DateInterval {
        let shiftedStart = start.addingTimeInterval(sleepDayOffset)
        let shiftedEnd = end >= now ? now : end.addingTimeInterval(sleepDayOffset)
        return DateInterval(start: shiftedStart, end: max(shiftedStart, shiftedEnd))
    }

    private struct SleepPeriods: Sendable {
        var asleep: [DateInterval]
        var restorative: [DateInterval]
        var awake: [DateInterval]
    }

    /// Asleep, deep-or-REM and awake periods overlapping the window, each with overlaps
    /// from different sources (Watch, iPhone, third-party apps) merged so time is only
    /// counted once.
    private func sleepPeriods(overlapping window: DateInterval) async -> SleepPeriods {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return SleepPeriods(asleep: [], restorative: [], awake: [])
        }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let restorativeValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let valid = ((samples as? [HKCategorySample]) ?? []).filter { $0.endDate > $0.startDate }
                func periods(_ values: Set<Int>) -> [DateInterval] {
                    Self.mergedIntervals(valid.filter { values.contains($0.value) }.map { DateInterval(start: $0.startDate, end: $0.endDate) })
                }
                continuation.resume(returning: SleepPeriods(
                    asleep: periods(asleepValues),
                    restorative: periods(restorativeValues),
                    awake: periods([HKCategoryValueSleepAnalysis.awake.rawValue])
                ))
            }
            healthStore.execute(query)
        }
    }

    nonisolated static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    nonisolated static func totalDuration(of intervals: [DateInterval], in window: DateInterval) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            return total + max(0, end.timeIntervalSince(start))
        }
    }
}
