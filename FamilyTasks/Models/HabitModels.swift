import SwiftUI

/// Something one person does on certain days, once or several times a day, such as
/// "Drink water, 8 times a day". Only its owner logs it; shared ones sync so the family
/// can see how it's going, private ones never leave the phone.
struct Habit: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var color: HabitColor
    var timesPerDay: Int
    /// Calendar weekdays it's on, 1 (Sunday) to 7 (Saturday). Empty means every day.
    var weekdays: [Int]
    var ownerEmail: String
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = HabitSymbols.all[0],
        color: HabitColor = .teal,
        timesPerDay: Int = 1,
        weekdays: [Int] = [],
        ownerEmail: String,
        isShared: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.timesPerDay = timesPerDay
        self.weekdays = weekdays
        self.ownerEmail = ownerEmail
        self.isShared = isShared
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, timesPerDay, weekdays, ownerEmail, isShared, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = (try? container.decode(String.self, forKey: .symbol)) ?? HabitSymbols.all[0]
        color = (try? container.decode(HabitColor.self, forKey: .color)) ?? .teal
        timesPerDay = max((try? container.decode(Int.self, forKey: .timesPerDay)) ?? 1, 1)
        weekdays = (try? container.decode([Int].self, forKey: .weekdays)) ?? []
        ownerEmail = (try? container.decode(String.self, forKey: .ownerEmail)) ?? ""
        isShared = (try? container.decode(Bool.self, forKey: .isShared)) ?? false
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: date))
    }

    /// "Every day", "Weekdays", "Mon, Wed, Fri", with "· 8 times" when it's more than once
    /// (left off where the count is already shown, as "5 of 8").
    func scheduleText(calendar: Calendar = .current, includesTimes: Bool = true) -> String {
        let days: String
        switch Set(weekdays) {
        case [], Set(1...7): days = "Every day"
        case Set(2...6): days = "Weekdays"
        case [1, 7]: days = "Weekends"
        default:
            let symbols = calendar.shortWeekdaySymbols
            // In the calendar's own week order, so Monday-first places read Mon … Sun.
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            days = order.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return includesTimes && timesPerDay > 1 ? "\(days) · \(timesPerDay) times" : days
    }
}

/// How many times a habit was done on one day. One record per habit per day keeps a
/// habit done eight times a day from making eight records.
struct HabitDay: Identifiable, Codable, Equatable {
    var habitID: UUID
    /// The day in the owner's calendar, "2026-10-27".
    var day: String
    var count: Int
    var updatedAt: Date

    var id: String { Self.id(habitID: habitID, day: day) }

    static func id(habitID: UUID, day: String) -> String {
        "habitday:\(habitID.uuidString):\(day)"
    }
}

enum HabitColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}

/// Symbols to choose from, the everyday ones from HabitHive.
enum HabitSymbols {
    static let all = [
        "drop", "figure.walk", "figure.run", "figure.yoga", "figure.mind.and.body", "dumbbell",
        "bicycle", "figure.pool.swim", "bed.double.fill", "book", "pencil.and.outline", "graduationcap",
        "music.note", "paintbrush", "leaf", "pills", "fork.knife", "carrot",
        "cup.and.saucer", "heart", "sun.max", "moon.stars", "sparkles", "pawprint",
        "brain.head.profile", "hand.raised", "dollarsign.circle", "iphone.slash", "tray.full", "checkmark.circle",
    ]
}

/// Everything about habits that's shared with the family.
struct HabitsPayload: Codable, Equatable {
    var habits: [Habit] = []
    var days: [HabitDay] = []

    init(habits: [Habit] = [], days: [HabitDay] = []) {
        self.habits = habits
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case habits, days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        habits = (try? container.decode([Habit].self, forKey: .habits)) ?? []
        days = (try? container.decode([HabitDay].self, forKey: .days)) ?? []
    }
}

struct HabitStreak: Equatable {
    var current: Int
    var best: Int
}

enum HabitMath {
    /// "2026-10-27" for `date` in `calendar`, which stays the same day whatever the time zone it's read in.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func count(of habit: Habit, on date: Date, days: [HabitDay], calendar: Calendar = .current) -> Int {
        let id = HabitDay.id(habitID: habit.id, day: dayKey(for: date, calendar: calendar))
        return days.first { $0.id == id }?.count ?? 0
    }

    /// Days in a row the habit was fully done, skipping days it isn't on. Today only
    /// counts once it's done, so an unfinished today doesn't break the streak.
    static func streak(for habit: Habit, days: [HabitDay], now: Date = Date(), calendar: Calendar = .current) -> HabitStreak {
        let counts = Dictionary(
            days.filter { $0.habitID == habit.id }.map { ($0.day, $0.count) },
            uniquingKeysWith: max
        )
        let today = calendar.startOfDay(for: now)
        let earliestLog = counts.keys.min().flatMap { date(fromKey: $0, calendar: calendar) }
        var day = calendar.startOfDay(for: min(habit.createdAt, earliestLog ?? habit.createdAt))
        // Bounded so a wrong clock can't make this run for ages.
        if let limit = calendar.date(byAdding: .year, value: -5, to: today), day < limit { day = limit }

        var run = 0
        var best = 0
        while day <= today {
            if habit.isScheduled(on: day, calendar: calendar) {
                let done = (counts[dayKey(for: day, calendar: calendar)] ?? 0) >= habit.timesPerDay
                if done {
                    run += 1
                    best = max(best, run)
                } else if day < today {
                    run = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return HabitStreak(current: run, best: best)
    }

    /// Share of the days it was on in `interval`, up to today, that it was fully done.
    static func completionRate(for habit: Habit, days: [HabitDay], in interval: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> Double? {
        let counts = Dictionary(
            days.filter { $0.habitID == habit.id }.map { ($0.day, $0.count) },
            uniquingKeysWith: max
        )
        let start = max(calendar.startOfDay(for: interval.start), calendar.startOfDay(for: habit.createdAt))
        let end = min(interval.end, now)
        var day = start
        var scheduled = 0
        var done = 0
        while day < end {
            if habit.isScheduled(on: day, calendar: calendar) {
                scheduled += 1
                if (counts[dayKey(for: day, calendar: calendar)] ?? 0) >= habit.timesPerDay { done += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return scheduled == 0 ? nil : Double(done) / Double(scheduled)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
