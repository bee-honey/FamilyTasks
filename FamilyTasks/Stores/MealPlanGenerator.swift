import Foundation

/// Fills a week's empty meal slots from the saved meals: breakfasts for breakfast, main
/// courses for lunch and dinner, each meal at most `timesPerWeek` times, never twice in
/// a day, and not on back-to-back days when there's another choice.
enum MealPlanGenerator {
    struct Proposal: Identifiable, Equatable {
        let id: UUID
        let day: Date
        let slot: MealSlot
        var mealID: UUID?

        init(id: UUID = UUID(), day: Date, slot: MealSlot, mealID: UUID?) {
            self.id = id
            self.day = day
            self.slot = slot
            self.mealID = mealID
        }
    }

    /// Not enough meals of one type to fill the slots that need it.
    struct Shortfall: Equatable {
        let category: MealCategory
        /// How many slots the eligible meals can fill (counting repeats).
        let canFill: Int
        let needed: Int
    }

    static func category(for slot: MealSlot) -> MealCategory {
        slot == .breakfast ? .breakfast : .mainCourse
    }

    /// Meals a generated plan may use for a type.
    static func eligibleMeals(_ meals: [MealIdea], for category: MealCategory) -> [MealIdea] {
        meals.filter { $0.category == category && !$0.skipInGeneratedPlans }
    }

    /// The days' slots that are still empty.
    static func emptySlots(days: [Date], slots: [MealSlot], planned: [PlannedMeal], calendar: Calendar = .current) -> [(day: Date, slot: MealSlot)] {
        days.flatMap { day in
            slots.compactMap { slot in
                let taken = planned.contains { calendar.isDate($0.date, inSameDayAs: day) && $0.slot == slot }
                return taken ? nil : (calendar.startOfDay(for: day), slot)
            }
        }
    }

    /// The types without enough meals for the empty slots; empty when the week can be filled.
    static func shortfalls(days: [Date], slots: [MealSlot], meals: [MealIdea], planned: [PlannedMeal], calendar: Calendar = .current) -> [Shortfall] {
        let empty = emptySlots(days: days, slots: slots, planned: planned, calendar: calendar)
        let usage = weeklyUsage(planned: planned, days: days, calendar: calendar)
        return MealCategory.allCases.compactMap { category in
            let needed = empty.filter { Self.category(for: $0.slot) == category }.count
            guard needed > 0 else { return nil }
            let canFill = eligibleMeals(meals, for: category)
                .reduce(0) { $0 + max(min($1.timesPerWeek, 7) - (usage[$1.id] ?? 0), 0) }
            return canFill >= needed ? nil : Shortfall(category: category, canFill: canFill, needed: needed)
        }
    }

    /// A proposal for every empty slot; a slot stays nil only if nothing fits.
    static func generate<R: RandomNumberGenerator>(
        days: [Date],
        slots: [MealSlot],
        meals: [MealIdea],
        planned: [PlannedMeal],
        calendar: Calendar = .current,
        using random: inout R
    ) -> [Proposal] {
        var usage = weeklyUsage(planned: planned, days: days, calendar: calendar)
        var mealsByDay: [Date: Set<UUID>] = [:]
        for meal in planned {
            mealsByDay[calendar.startOfDay(for: meal.date), default: []].insert(meal.mealID)
        }

        var proposals: [Proposal] = []
        for (day, slot) in emptySlots(days: days, slots: slots, planned: planned, calendar: calendar) {
            let pick = choose(
                from: eligibleMeals(meals, for: category(for: slot)),
                day: day,
                usage: usage,
                mealsByDay: mealsByDay,
                calendar: calendar,
                using: &random
            )
            if let pick {
                usage[pick, default: 0] += 1
                mealsByDay[day, default: []].insert(pick)
            }
            proposals.append(Proposal(day: day, slot: slot, mealID: pick))
        }
        return proposals
    }

    static func generate(days: [Date], slots: [MealSlot], meals: [MealIdea], planned: [PlannedMeal]) -> [Proposal] {
        var random = SystemRandomNumberGenerator()
        return generate(days: days, slots: slots, meals: meals, planned: planned, using: &random)
    }

    /// Another meal for one proposal, respecting the limits given the rest of the plan.
    static func alternative<R: RandomNumberGenerator>(
        for proposal: Proposal,
        in proposals: [Proposal],
        meals: [MealIdea],
        planned: [PlannedMeal],
        days: [Date],
        calendar: Calendar = .current,
        using random: inout R
    ) -> UUID? {
        var usage = weeklyUsage(planned: planned, days: days, calendar: calendar)
        var mealsByDay: [Date: Set<UUID>] = [:]
        for meal in planned {
            mealsByDay[calendar.startOfDay(for: meal.date), default: []].insert(meal.mealID)
        }
        for other in proposals where other.id != proposal.id {
            guard let mealID = other.mealID else { continue }
            usage[mealID, default: 0] += 1
            mealsByDay[calendar.startOfDay(for: other.day), default: []].insert(mealID)
        }
        let candidates = eligibleMeals(meals, for: category(for: proposal.slot)).filter { $0.id != proposal.mealID }
        return choose(from: candidates, day: proposal.day, usage: usage, mealsByDay: mealsByDay, calendar: calendar, using: &random)
    }

    // MARK: Helpers

    private static func weeklyUsage(planned: [PlannedMeal], days: [Date], calendar: Calendar) -> [UUID: Int] {
        let dayStarts = Set(days.map { calendar.startOfDay(for: $0) })
        return planned
            .filter { dayStarts.contains(calendar.startOfDay(for: $0.date)) }
            .reduce(into: [:]) { $0[$1.mealID, default: 0] += 1 }
    }

    private static func choose<R: RandomNumberGenerator>(
        from meals: [MealIdea],
        day: Date,
        usage: [UUID: Int],
        mealsByDay: [Date: Set<UUID>],
        calendar: Calendar,
        using random: inout R
    ) -> UUID? {
        let today = mealsByDay[day] ?? []
        let neighbours = [-1, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            .reduce(into: Set<UUID>()) { $0.formUnion(mealsByDay[calendar.startOfDay(for: $1)] ?? []) }

        let available = meals.filter { (usage[$0.id] ?? 0) < min($0.timesPerWeek, 7) && !today.contains($0.id) }
        let spaced = available.filter { !neighbours.contains($0.id) }
        // Prefer meals used least so far, so the week has variety.
        let pool = spaced.isEmpty ? available : spaced
        guard let fewest = pool.map({ usage[$0.id] ?? 0 }).min() else { return nil }
        return pool.filter { (usage[$0.id] ?? 0) == fewest }.randomElement(using: &random)?.id
    }
}
