import Foundation

@MainActor
final class HabitStore: ObservableObject {
    /// The app-wide store, shared with family sharing so there is only one copy in memory.
    static let shared = HabitStore()

    /// This person's habits, private and shared, and the family's shared ones.
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var days: [HabitDay] = []

    private let storageURL: URL
    private let ownerEmail: () -> String

    init(directory: URL? = nil, ownerEmail: @escaping () -> String = HabitStore.currentProfileEmail) {
        storageURL = (directory ?? URL.documentsDirectory).appendingPathComponent("family-habits.json")
        self.ownerEmail = ownerEmail
        load()
    }

    // MARK: Reading

    /// The habits this person logs, in the order they were added.
    var myHabits: [Habit] {
        let me = ownerEmail()
        return habits.filter { $0.ownerEmail == me }
    }

    /// Other family members' shared habits.
    var familyHabits: [Habit] {
        let me = ownerEmail()
        return habits.filter { $0.ownerEmail != me && $0.isShared }
    }

    func myHabits(on date: Date, calendar: Calendar = .current) -> [Habit] {
        myHabits.filter { $0.isScheduled(on: date, calendar: calendar) }
    }

    func count(of habit: Habit, on date: Date = Date()) -> Int {
        HabitMath.count(of: habit, on: date, days: days)
    }

    func isDone(_ habit: Habit, on date: Date = Date()) -> Bool {
        count(of: habit, on: date) >= habit.timesPerDay
    }

    func streak(for habit: Habit, now: Date = Date()) -> HabitStreak {
        HabitMath.streak(for: habit, days: days, now: now)
    }

    func isMine(_ habit: Habit) -> Bool {
        habit.ownerEmail == ownerEmail()
    }

    // MARK: Changing

    func add(name: String, symbol: String, color: HabitColor, timesPerDay: Int, weekdays: [Int], isShared: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        change {
            habits.append(Habit(
                name: trimmed,
                symbol: symbol,
                color: color,
                timesPerDay: max(timesPerDay, 1),
                weekdays: Self.cleaned(weekdays),
                ownerEmail: ownerEmail(),
                isShared: isShared
            ))
        }
    }

    func update(_ habit: Habit, name: String, symbol: String, color: HabitColor, timesPerDay: Int, weekdays: [Int], isShared: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isMine(habit), let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        change {
            var changed = habits[index]
            changed.name = trimmed
            changed.symbol = symbol
            changed.color = color
            changed.timesPerDay = max(timesPerDay, 1)
            changed.weekdays = Self.cleaned(weekdays)
            changed.isShared = isShared
            changed.updatedAt = Date()
            habits[index] = changed
            if isShared {
                // Its history goes up with it, so the family sees its streak.
                touchDays(of: habit.id)
            }
        }
    }

    func delete(_ habit: Habit) {
        guard isMine(habit) else { return }
        change {
            habits.removeAll { $0.id == habit.id }
            days.removeAll { $0.habitID == habit.id }
        }
    }

    /// One more time today (or on `date`), up to the day's target.
    func log(_ habit: Habit, on date: Date = Date()) {
        setCount(of: habit, on: date, to: min(count(of: habit, on: date) + 1, habit.timesPerDay))
    }

    func undo(_ habit: Habit, on date: Date = Date()) {
        setCount(of: habit, on: date, to: max(count(of: habit, on: date) - 1, 0))
    }

    /// For the history calendar: each tap adds one, and after the target it starts over.
    func cycle(_ habit: Habit, on date: Date) {
        let current = count(of: habit, on: date)
        setCount(of: habit, on: date, to: current >= habit.timesPerDay ? 0 : current + 1)
    }

    private func setCount(of habit: Habit, on date: Date, to newCount: Int) {
        guard isMine(habit) else { return }
        let key = HabitMath.dayKey(for: date)
        let id = HabitDay.id(habitID: habit.id, day: key)
        let existing = days.firstIndex { $0.id == id }
        let oldCount = existing.map { days[$0].count } ?? 0
        guard newCount != oldCount else { return }
        change {
            // A zero day is kept rather than removed, so an undo syncs like any other change.
            let day = HabitDay(habitID: habit.id, day: key, count: newCount, updatedAt: Date())
            if let existing {
                days[existing] = day
            } else {
                days.append(day)
            }
        }
        // Finishing a shared habit today is news for the family; fixing an old day isn't.
        if habit.isShared, oldCount < habit.timesPerDay, newCount >= habit.timesPerDay, Calendar.current.isDateInToday(date) {
            LocalItemChange.habitDone(habit: habit, day: key, streak: streak(for: habit).current).post()
        }
    }

    private func touchDays(of habitID: UUID) {
        let now = Date()
        for index in days.indices where days[index].habitID == habitID {
            days[index].updatedAt = now
        }
    }

    /// Makes a change, then marks shared items that went (deleted, or made private) as
    /// deleted for the family, and saves.
    private func change(_ body: () -> Void) {
        let before = exportPayload()
        body()
        let after = exportPayload()
        SyncLedger.shared.recordRemovals(from: before.habits, to: after.habits)
        SyncLedger.shared.recordRemovals(from: before.days, to: after.days)
        save()
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    private static func cleaned(_ weekdays: [Int]) -> [Int] {
        let days = Set(weekdays.filter { (1...7).contains($0) })
        return days.count == 7 ? [] : days.sorted()
    }

    // MARK: Family sharing

    /// Only shared habits and their days; private ones never leave the phone.
    func exportPayload() -> HabitsPayload {
        let shared = habits.filter(\.isShared)
        let sharedIDs = Set(shared.map(\.id))
        return HabitsPayload(habits: shared, days: days.filter { sharedIDs.contains($0.habitID) })
    }

    /// Takes the family's shared habits from `payload` and keeps this phone's private ones.
    /// Only assigns what changed, so a sync with nothing new doesn't rewrite files or redraw views.
    func applySharedData(_ payload: HabitsPayload) {
        let incomingIDs = Set(payload.habits.map(\.id))
        let privateHabits = habits.filter { !$0.isShared && !incomingIDs.contains($0.id) }
        let privateIDs = Set(privateHabits.map(\.id))
        let mergedHabits = payload.habits + privateHabits
        let mergedDays = payload.days.filter { !privateIDs.contains($0.habitID) } + days.filter { privateIDs.contains($0.habitID) }

        var changed = false
        if habits != mergedHabits { habits = mergedHabits; changed = true }
        if days != mergedDays { days = mergedDays; changed = true }
        if changed { save() }
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let payload = try? JSONDecoder().decode(HabitsPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: storageURL)
            return
        }
        habits = payload.habits
        days = payload.days
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(HabitsPayload(habits: habits, days: days)) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    nonisolated static func currentProfileEmail() -> String {
        (UserDefaults.standard.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
