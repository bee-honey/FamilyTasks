import Foundation

// MARK: Sleep score

/// One night's sleep, the parts a sleep score is made from.
struct SleepNight: Equatable {
    var asleep: TimeInterval
    /// Deep and REM sleep, when the source records sleep stages (Apple Watch does).
    var deepAndREM: TimeInterval?
    /// Time awake in the night, when the source records sleep stages.
    var awake: TimeInterval?

    var hasStages: Bool { deepAndREM != nil && awake != nil }
}

/// A 0–100 score for one night: mostly how long you slept, and, when the watch records
/// stages, how much of it was deep or REM sleep and how often you woke.
enum SleepScore {
    /// About this share of a night is deep or REM sleep for most adults.
    static let typicalRestorativeShare = 0.35

    static func score(for night: SleepNight) -> Int? {
        // Under half an hour is a nap or a watch left on the nightstand.
        guard night.asleep >= 30 * 60 else { return nil }
        let duration = durationPart(hours: night.asleep / 3_600)
        guard let deepAndREM = night.deepAndREM, let awake = night.awake else {
            return Int((duration * 100).rounded())
        }
        let restorative = min(deepAndREM / night.asleep / typicalRestorativeShare, 1)
        // An hour or more awake in the night scores nothing for continuity.
        let continuity = 1 - min(awake / 3_600, 1)
        return Int(((duration * 0.5 + restorative * 0.25 + continuity * 0.25) * 100).rounded())
    }

    /// 7 to 9 hours is full marks; 3 hours or less is none; long lie-ins lose a little.
    static func durationPart(hours: Double) -> Double {
        switch hours {
        case ..<7: max(0, (hours - 3) / 4)
        case ...9: 1
        default: max(0.8, 1 - (hours - 9) * 0.1)
        }
    }

    static func label(for score: Int) -> String {
        switch score {
        case 85...: "Excellent"
        case 70..<85: "Good"
        case 50..<70: "Fair"
        default: "Poor"
        }
    }
}

// MARK: Body

enum BodyMath {
    enum BMICategory: String, CaseIterable {
        case underweight, healthy, overweight, obese

        var title: String {
            switch self {
            case .underweight: "Underweight"
            case .healthy: "Healthy range"
            case .overweight: "Overweight"
            case .obese: "Obese range"
            }
        }

        /// The WHO adult bands.
        init(bmi: Double) {
            switch bmi {
            case ..<18.5: self = .underweight
            case ..<25: self = .healthy
            case ..<30: self = .overweight
            default: self = .obese
            }
        }
    }

    /// Weight in kilograms over height in meters squared, or nil for a height or weight
    /// that can't be right.
    static func bmi(weightKg: Double, heightMeters: Double) -> Double? {
        guard (0.5...2.6).contains(heightMeters), (2...400).contains(weightKg) else { return nil }
        return weightKg / (heightMeters * heightMeters)
    }

    static func weightText(kg: Double) -> String {
        Measurement(value: kg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func heightText(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .personHeight))
    }
}

// MARK: Goals

/// What a goal measures, read from a day's health summary.
enum HealthMetric: String, Codable, CaseIterable, Identifiable {
    case steps
    case exerciseMinutes
    case activeEnergy
    case sleepHours
    case sleepScore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .exerciseMinutes: "Exercise"
        case .activeEnergy: "Active Energy"
        case .sleepHours: "Sleep"
        case .sleepScore: "Sleep Score"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .exerciseMinutes: "figure.run"
        case .activeEnergy: "flame.fill"
        case .sleepHours: "bed.double.fill"
        case .sleepScore: "moon.stars.fill"
        }
    }

    /// Steps, minutes and calories add up across people and days; sleep doesn't.
    var isAdditive: Bool {
        switch self {
        case .steps, .exerciseMinutes, .activeEnergy: true
        case .sleepHours, .sleepScore: false
        }
    }

    var defaultTarget: Double {
        switch self {
        case .steps: 10_000
        case .exerciseMinutes: 30
        case .activeEnergy: 500
        case .sleepHours: 8
        case .sleepScore: 80
        }
    }

    /// A family's weekly target: the daily one for each of `people`, for seven days.
    func defaultWeeklyTarget(people: Int) -> Double {
        defaultTarget * 7 * Double(max(people, 1))
    }

    var targetStep: Double {
        switch self {
        case .steps: 500
        case .exerciseMinutes: 5
        case .activeEnergy: 50
        case .sleepHours: 0.5
        case .sleepScore: 5
        }
    }

    var dailyRange: ClosedRange<Double> {
        switch self {
        case .steps: 1_000...40_000
        case .exerciseMinutes: 5...240
        case .activeEnergy: 100...2_000
        case .sleepHours: 5...10
        case .sleepScore: 50...100
        }
    }

    func value(in snapshot: HealthSnapshot) -> Double? {
        switch self {
        case .steps: snapshot.steps
        case .exerciseMinutes: snapshot.exerciseMinutes
        case .activeEnergy: snapshot.activeEnergy
        case .sleepHours: snapshot.sleepSeconds > 0 ? snapshot.sleepSeconds / 3_600 : nil
        case .sleepScore: snapshot.sleepScore.map(Double.init)
        }
    }

    /// "10,400 steps", "35 min", "520 kcal", "7.5 hr", "82".
    func format(_ value: Double) -> String {
        switch self {
        case .steps: "\(value.formatted(.number.precision(.fractionLength(0)))) steps"
        case .exerciseMinutes: "\(value.formatted(.number.precision(.fractionLength(0)))) min"
        case .activeEnergy: "\(value.formatted(.number.precision(.fractionLength(0)))) kcal"
        case .sleepHours: "\(value.formatted(.number.precision(.fractionLength(0...1)))) hr"
        case .sleepScore: value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// "10,000 steps a day", "a sleep score of 80", "300,000 steps together this week".
    func targetText(_ target: Double, kind: HealthGoal.Kind) -> String {
        switch kind {
        case .family:
            "\(format(target)) together this week"
        case .personal:
            self == .sleepScore ? "A sleep score of \(format(target))" : "\(format(target)) a day"
        }
    }
}

/// A target for one person each day, or for the whole family over a week.
struct HealthGoal: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        /// One person's daily goal. Private unless they share it.
        case personal
        /// Everyone's total over the week (Monday or Sunday on, as the calendar has it).
        case family
    }

    var id: UUID
    var metric: HealthMetric
    var target: Double
    var kind: Kind
    /// Who set it: whose goal it is, or who started the family challenge.
    var ownerEmail: String
    /// Whether a personal goal shows on the family dashboard. Family challenges always do.
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        metric: HealthMetric,
        target: Double,
        kind: Kind = .personal,
        ownerEmail: String,
        isShared: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.metric = metric
        self.target = target
        self.kind = kind
        self.ownerEmail = ownerEmail
        self.isShared = kind == .family || isShared
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Goes to the family: shared personal goals and every family challenge.
    var isVisibleToFamily: Bool { kind == .family || isShared }
}

struct HealthGoalStreak: Equatable {
    var current: Int
    var best: Int
}

enum HealthGoalMath {
    /// One person's value for the goal on `day` ("2026-10-27"), from their snapshots.
    static func value(of goal: HealthGoal, on day: String, snapshots: [HealthSnapshot]) -> Double? {
        let owner = FamilyAlert.normalized(goal.ownerEmail)
        return snapshots
            .first { $0.dayID == day && $0.memberEmail == owner }
            .flatMap(goal.metric.value(in:))
    }

    /// Days in a row the goal was met, ending today if it's met already, else yesterday,
    /// so an unfinished today doesn't break the streak.
    static func streak(of goal: HealthGoal, snapshots: [HealthSnapshot], now: Date = Date(), calendar: Calendar = .current) -> HealthGoalStreak {
        let owner = FamilyAlert.normalized(goal.ownerEmail)
        var met: [String: Bool] = [:]
        for snapshot in snapshots where snapshot.memberEmail == owner {
            met[snapshot.dayID] = (goal.metric.value(in: snapshot) ?? 0) >= goal.target
        }
        let today = calendar.startOfDay(for: now)
        guard let earliest = met.keys.min().flatMap({ HabitMath.date(fromKey: $0, calendar: calendar) }) else {
            return HealthGoalStreak(current: 0, best: 0)
        }

        var run = 0
        var best = 0
        var day = max(earliest, calendar.date(byAdding: .day, value: -400, to: today) ?? earliest)
        while day <= today {
            if met[HabitMath.dayKey(for: day, calendar: calendar)] == true {
                run += 1
                best = max(best, run)
            } else if day < today {
                run = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return HealthGoalStreak(current: run, best: best)
    }

    /// The calendar week holding `now`, Monday or Sunday first as the calendar has it.
    static func week(containing now: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
    }

    /// "2026-W44", for remembering a week's challenge was announced.
    static func weekKey(for now: Date, calendar: Calendar = .current) -> String {
        let start = week(containing: now, calendar: calendar).start
        return "week-" + HabitMath.dayKey(for: start, calendar: calendar)
    }

    /// Each person's total this week for a family challenge, by email, and the sum.
    static func weekTotals(of goal: HealthGoal, snapshots: [HealthSnapshot], now: Date = Date(), calendar: Calendar = .current) -> (total: Double, byMember: [String: Double]) {
        let week = week(containing: now, calendar: calendar)
        var byMember: [String: Double] = [:]
        for snapshot in snapshots where snapshot.date >= week.start && snapshot.date < week.end {
            byMember[snapshot.memberEmail, default: 0] += goal.metric.value(in: snapshot) ?? 0
        }
        return (byMember.values.reduce(0, +), byMember)
    }
}

// MARK: Tips

struct HealthTip: Identifiable, Equatable {
    enum Topic: String {
        case sleep, movement, food, water, mind, family

        var systemImage: String {
            switch self {
            case .sleep: "moon.zzz.fill"
            case .movement: "figure.walk"
            case .food: "carrot.fill"
            case .water: "drop.fill"
            case .mind: "brain.head.profile"
            case .family: "figure.2.and.child.holdinghands"
            }
        }
    }

    var id: String { title }
    var topic: Topic
    var title: String
    var body: String
}

/// Everyday wellness tips, one a day. General habits, not medical advice: keep new ones
/// short, practical and widely agreed on.
enum HealthTips {
    static let all: [HealthTip] = [
        HealthTip(topic: .sleep, title: "Try 3-2-1 tonight", body: "No food 3 hours before bed, no drinks 2 hours before, and no screens in the last hour."),
        HealthTip(topic: .movement, title: "Walk after meals", body: "A 10-minute walk after eating helps keep blood sugar steadier than sitting down."),
        HealthTip(topic: .water, title: "Start with water", body: "Have a glass of water when you wake up. You've gone all night without a drink."),
        HealthTip(topic: .sleep, title: "Same time, every day", body: "Waking at the same time on weekends too keeps your body clock steady, and Mondays feel easier."),
        HealthTip(topic: .food, title: "Half a plate of vegetables", body: "Fill half your plate with vegetables or salad, a quarter with protein and a quarter with grains."),
        HealthTip(topic: .mind, title: "Breathe slowly", body: "Breathing out for longer than you breathe in, for a minute, helps you calm down when stressed."),
        HealthTip(topic: .movement, title: "Stand up every hour", body: "Long stretches of sitting add up. Stand, stretch or walk for a couple of minutes each hour."),
        HealthTip(topic: .family, title: "Walk together", body: "An evening walk as a family adds steps for everyone and time to talk without screens."),
        HealthTip(topic: .sleep, title: "Morning light", body: "Ten minutes of daylight soon after waking helps you feel alert in the day and sleepy at night."),
        HealthTip(topic: .food, title: "Eat slowly", body: "It takes about 20 minutes to feel full. Putting the spoon down between bites helps you notice."),
        HealthTip(topic: .water, title: "Check the color", body: "Pale yellow means you're drinking enough. Darker means have a glass of water."),
        HealthTip(topic: .movement, title: "Take the stairs", body: "Stairs instead of the lift are a quick, free way to raise your heart rate."),
        HealthTip(topic: .mind, title: "Name three good things", body: "Before bed, think of three things that went well today. It's a small habit that lifts mood."),
        HealthTip(topic: .sleep, title: "Caffeine has a long tail", body: "Half the caffeine from an afternoon coffee is still in you at bedtime. Try none after 2 PM."),
        HealthTip(topic: .food, title: "Protein at breakfast", body: "Eggs, curd, paneer, dal or sprouts in the morning keep you fuller until lunch."),
        HealthTip(topic: .family, title: "Phones off at dinner", body: "Eating together without screens helps everyone eat more slowly and actually talk."),
        HealthTip(topic: .movement, title: "Strength counts too", body: "Two days a week of muscle work, like squats, push-ups or carrying shopping, keeps you strong."),
        HealthTip(topic: .sleep, title: "Cool, dark and quiet", body: "A slightly cool, dark bedroom helps you fall asleep and stay asleep."),
        HealthTip(topic: .water, title: "Keep a bottle nearby", body: "You drink more when water is within reach. Keep a bottle on your desk."),
        HealthTip(topic: .mind, title: "Step outside", body: "A few minutes outdoors, even on a busy day, helps reset your focus."),
        HealthTip(topic: .food, title: "Fruit over juice", body: "Whole fruit has the fiber that juice leaves behind, so it fills you up and is easier on blood sugar."),
        HealthTip(topic: .movement, title: "Stretch before bed", body: "Five minutes of gentle stretching loosens up after a day of sitting and helps you wind down."),
        HealthTip(topic: .family, title: "Cheer someone on", body: "Saw someone in the family hit a goal? A quick cheer keeps everyone going."),
        HealthTip(topic: .sleep, title: "Get up if you can't sleep", body: "Awake for more than 20 minutes? Get up, do something calm in dim light, and go back when sleepy."),
        HealthTip(topic: .food, title: "Go easy on salt", body: "Taste before you add salt, and go easy on pickles, papad and packaged snacks."),
        HealthTip(topic: .mind, title: "One thing at a time", body: "Switching between tasks is tiring. Try finishing one thing before starting the next."),
        HealthTip(topic: .movement, title: "Every step counts", body: "You don't need 10,000 steps to benefit. Adding a couple of thousand to your usual day helps."),
        HealthTip(topic: .water, title: "Drink before you're thirsty", body: "On hot days or after exercise, drink regularly rather than waiting to feel thirsty."),
    ]

    /// The same tip all day, a different one each day.
    static func tip(for date: Date, calendar: Calendar = .current) -> HealthTip {
        let day = Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate / 86_400)
        return all[((day % all.count) + all.count) % all.count]
    }
}

// MARK: Wind-down

/// The 3-2-1 routine before bed: no food 3 hours before, no drinks 2 hours before, and no
/// screens in the last hour.
enum WindDownStep: String, CaseIterable, Identifiable {
    case food
    case drinks
    case screens

    var id: String { rawValue }

    var hoursBefore: Int {
        switch self {
        case .food: 3
        case .drinks: 2
        case .screens: 1
        }
    }

    var title: String {
        switch self {
        case .food: "Last meal"
        case .drinks: "Last drinks"
        case .screens: "Screens off"
        }
    }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .drinks: "cup.and.saucer.fill"
        case .screens: "iphone.slash"
        }
    }

    var settingsKey: String { "health.windDown.\(rawValue)" }

    var notificationTitle: String {
        switch self {
        case .food: "3 hours to bed: kitchen's closed"
        case .drinks: "2 hours to bed: last drinks"
        case .screens: "1 hour to bed: screens off"
        }
    }

    func notificationBody(bedtime: String) -> String {
        switch self {
        case .food: "Bedtime is \(bedtime). Finishing eating now means you're not digesting while you sleep."
        case .drinks: "Bedtime is \(bedtime). Stopping drinks now means fewer trips to the bathroom at night."
        case .screens: "Bedtime is \(bedtime). Put the phone away, dim the lights and pick up a book."
        }
    }

    /// The hour and minute of this step for a bedtime, wrapping past midnight.
    func time(bedtimeHour: Int, bedtimeMinute: Int) -> (hour: Int, minute: Int) {
        let minutes = ((bedtimeHour - hoursBefore) * 60 + bedtimeMinute + 24 * 60) % (24 * 60)
        return (minutes / 60, minutes % 60)
    }
}

enum WindDownSettings {
    static let enabledKey = "health.windDown.enabled"
    static let bedtimeHourKey = "health.bedtimeHour"
    static let bedtimeMinuteKey = "health.bedtimeMinute"
    static let dailyTipKey = "health.dailyTip"
    static let dailyTipHourKey = "health.dailyTipHour"
    static let dailyTipMinuteKey = "health.dailyTipMinute"
    static let defaultBedtimeHour = 22
    static let defaultBedtimeMinute = 30
    static let defaultTipHour = 9

    /// "10:30 PM" for an hour and minute.
    static func timeText(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: Data from Health

/// Each kind of data Health can send, for showing which ones are arriving. iOS never tells
/// an app what it may read, so arriving data is the only sign access was allowed.
enum HealthDataKind: String, CaseIterable, Identifiable {
    case steps, exercise, activeEnergy, sleep, sleepStages, restingHeartRate, hrv, vo2Max, weight, height

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .exercise: "Exercise Minutes"
        case .activeEnergy: "Active Energy"
        case .sleep: "Sleep"
        case .sleepStages: "Sleep Stages"
        case .restingHeartRate: "Resting Heart Rate"
        case .hrv: "Heart Rate Variability"
        case .vo2Max: "Cardio Fitness (VO₂ Max)"
        case .weight: "Weight"
        case .height: "Height"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .exercise: "figure.run"
        case .activeEnergy: "flame.fill"
        case .sleep: "bed.double.fill"
        case .sleepStages: "moon.stars.fill"
        case .restingHeartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .vo2Max: "lungs.fill"
        case .weight: "scalemass.fill"
        case .height: "ruler"
        }
    }

    /// What usually records it, when that's not the iPhone itself.
    var source: String? {
        switch self {
        case .exercise, .sleepStages, .restingHeartRate, .hrv, .vo2Max: "Needs Apple Watch"
        case .sleep: "Apple Watch or Sleep in the Health app"
        case .weight, .height: "A scale, or enter it in Health"
        case .steps, .activeEnergy: nil
        }
    }

    /// Whether any of this kind arrived in `days`, or as the latest weight and height.
    func isArriving(in days: [HealthSnapshot], sleepStages: Bool, weight: HealthReading?, height: HealthReading?) -> Bool {
        switch self {
        case .steps: days.contains { $0.steps > 0 }
        case .exercise: days.contains { $0.exerciseMinutes != nil }
        case .activeEnergy: days.contains { $0.activeEnergy != nil }
        case .sleep: days.contains { $0.sleepSeconds > 0 }
        case .sleepStages: sleepStages
        case .restingHeartRate: days.contains { $0.restingHeartRate != nil }
        case .hrv: days.contains { $0.hrv != nil }
        case .vo2Max: days.contains { $0.vo2Max != nil }
        case .weight: weight != nil
        case .height: height != nil
        }
    }
}
