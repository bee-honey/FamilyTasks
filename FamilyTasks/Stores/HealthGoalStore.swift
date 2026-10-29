import Foundation

/// Health goals: each person's daily ones, private or shared, and family challenges,
/// which everyone works toward together over a week.
@MainActor
final class HealthGoalStore: ObservableObject {
    static let shared = HealthGoalStore()

    @Published private(set) var goals: [HealthGoal] = []

    private let storageURL: URL
    private let ownerEmail: () -> String
    private let defaults: UserDefaults
    /// Goals already announced, by goal ID: the day (personal) or week (family) they were met.
    private static let announcedKey = "health.goalsAnnounced"

    init(
        directory: URL? = nil,
        defaults: UserDefaults = .standard,
        ownerEmail: @escaping () -> String = HabitStore.currentProfileEmail
    ) {
        storageURL = (directory ?? URL.documentsDirectory).appendingPathComponent("family-health-goals.json")
        self.defaults = defaults
        self.ownerEmail = ownerEmail
        load()
    }

    // MARK: Reading

    var myGoals: [HealthGoal] {
        let me = ownerEmail()
        return goals.filter { $0.kind == .personal && $0.ownerEmail == me }
    }

    /// Other people's shared goals.
    var familyGoals: [HealthGoal] {
        let me = ownerEmail()
        return goals.filter { $0.kind == .personal && $0.ownerEmail != me && $0.isShared }
    }

    var challenges: [HealthGoal] {
        goals.filter { $0.kind == .family }
    }

    func isMine(_ goal: HealthGoal) -> Bool {
        goal.ownerEmail == ownerEmail()
    }

    // MARK: Changing

    func add(metric: HealthMetric, target: Double, kind: HealthGoal.Kind, isShared: Bool) {
        guard target > 0, kind == .personal || metric.isAdditive else { return }
        change {
            goals.append(HealthGoal(metric: metric, target: target, kind: kind, ownerEmail: ownerEmail(), isShared: isShared))
        }
    }

    func update(_ goal: HealthGoal, target: Double, isShared: Bool) {
        guard target > 0, isMine(goal), let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        change {
            goals[index].target = target
            goals[index].isShared = goal.kind == .family || isShared
            goals[index].updatedAt = Date()
        }
    }

    func delete(_ goal: HealthGoal) {
        guard isMine(goal) else { return }
        change {
            goals.removeAll { $0.id == goal.id }
        }
    }

    private func change(_ body: () -> Void) {
        let before = exportPayload()
        body()
        SyncLedger.shared.recordRemovals(from: before, to: exportPayload())
        save()
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    // MARK: Announcing

    /// Tells the family about shared goals this person met today and challenges they
    /// started that the family finished this week, once each.
    ///
    /// `mine` is this person's own days, straight from Health; `family` is everyone's
    /// shared days.
    func announceAchievements(mine: [HealthSnapshot], family: [HealthSnapshot], now: Date = Date(), calendar: Calendar = .current) {
        let me = ownerEmail()
        guard !me.isEmpty else { return }
        let today = HabitMath.dayKey(for: now, calendar: calendar)
        let week = HealthGoalMath.weekKey(for: now, calendar: calendar)
        var announced = defaults.dictionary(forKey: Self.announcedKey) as? [String: String] ?? [:]
        let before = announced

        for goal in myGoals where goal.isShared && announced[goal.id.uuidString] != today {
            guard let value = HealthGoalMath.value(of: goal, on: today, snapshots: mine), value >= goal.target else { continue }
            announced[goal.id.uuidString] = today
            let streak = HealthGoalMath.streak(of: goal, snapshots: mine, now: now, calendar: calendar).current
            LocalItemChange.healthGoal(goal: goal, value: value, streak: streak).post()
        }

        // Only whoever started a challenge announces it, so the family hears once.
        let everyone = Self.replacingOwn(family, with: mine, owner: me)
        for goal in challenges where goal.ownerEmail == me && announced[goal.id.uuidString] != week {
            let total = HealthGoalMath.weekTotals(of: goal, snapshots: everyone, now: now, calendar: calendar).total
            guard total >= goal.target else { continue }
            announced[goal.id.uuidString] = week
            LocalItemChange.healthGoal(goal: goal, value: total, streak: 0).post()
        }

        if announced != before {
            // Only today's and this week's entries are ever checked.
            defaults.set(announced.filter { $0.value == today || $0.value == week }, forKey: Self.announcedKey)
        }
    }

    /// The family's days with this person's own replaced by the fresher ones from Health.
    static func replacingOwn(_ family: [HealthSnapshot], with mine: [HealthSnapshot], owner: String) -> [HealthSnapshot] {
        let myDays = Set(mine.map(\.dayID))
        return family.filter { $0.memberEmail != owner || !myDays.contains($0.dayID) } + mine
    }

    // MARK: Family sharing

    /// Shared goals and challenges; private goals never leave the phone.
    func exportPayload() -> [HealthGoal] {
        goals.filter(\.isVisibleToFamily)
    }

    /// Takes the family's goals from `goals` and keeps this phone's private ones.
    func applySharedData(_ shared: [HealthGoal]) {
        let incomingIDs = Set(shared.map(\.id))
        let privateGoals = goals.filter { !$0.isVisibleToFamily && !incomingIDs.contains($0.id) }
        let merged = shared + privateGoals
        guard merged != goals else { return }
        goals = merged
        save()
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let saved = try? JSONDecoder().decode([HealthGoal].self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: storageURL)
            return
        }
        goals = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
