import XCTest
@testable import FamilyTasks

/// Repeatable "random" numbers so generated plans can be checked.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class MealPlanGeneratorTests: XCTestCase {
    private let calendar = Calendar.current
    private var week: [Date] {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func meals(_ count: Int, _ category: MealCategory, timesPerWeek: Int = 1, prefix: String) -> [MealIdea] {
        (1...count).map { MealIdea(name: "\(prefix) \($0)", category: category, timesPerWeek: timesPerWeek) }
    }

    func testFillsEveryEmptySlotWithTheRightTypeOfMeal() {
        let library = meals(7, .breakfast, prefix: "Breakfast") + meals(7, .mainCourse, prefix: "Dinner")
        var random = SeededGenerator(state: 1)

        let plan = MealPlanGenerator.generate(days: week, slots: [.breakfast, .dinner], meals: library, planned: [], using: &random)

        XCTAssertEqual(plan.count, 14)
        XCTAssertTrue(plan.allSatisfy { $0.mealID != nil })
        for proposal in plan {
            let meal = library.first { $0.id == proposal.mealID }!
            XCTAssertEqual(meal.category, proposal.slot == .breakfast ? .breakfast : .mainCourse)
        }
        // Seven meals, once a week each: every one used exactly once per slot type.
        XCTAssertEqual(Set(plan.filter { $0.slot == .dinner }.compactMap(\.mealID)).count, 7)
    }

    func testRepeatableMealsLetAFewMealsFillTheWeek() {
        let library = meals(3, .breakfast, timesPerWeek: 3, prefix: "Breakfast")
        var random = SeededGenerator(state: 7)

        let plan = MealPlanGenerator.generate(days: week, slots: [.breakfast], meals: library, planned: [], using: &random)

        XCTAssertTrue(plan.allSatisfy { $0.mealID != nil })
        let counts = Dictionary(grouping: plan.compactMap(\.mealID), by: { $0 }).mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 <= 3 })
        // Back-to-back repeats are avoided when there's a choice.
        let ordered = plan.sorted { $0.day < $1.day }.compactMap(\.mealID)
        XCTAssertFalse(zip(ordered, ordered.dropFirst()).contains { $0 == $1 })
    }

    func testLunchAndDinnerOnTheSameDayDiffer() {
        let library = meals(7, .mainCourse, timesPerWeek: 2, prefix: "Main")
        var random = SeededGenerator(state: 3)

        let plan = MealPlanGenerator.generate(days: week, slots: [.lunch, .dinner], meals: library, planned: [], using: &random)

        for day in week {
            let thatDay = plan.filter { calendar.isDate($0.day, inSameDayAs: day) }.compactMap(\.mealID)
            XCTAssertEqual(Set(thatDay).count, thatDay.count)
        }
    }

    func testShortfallSaysHowManyMoreAreNeeded() {
        let library = meals(3, .breakfast, prefix: "Breakfast") + meals(7, .mainCourse, prefix: "Dinner")

        let shortfalls = MealPlanGenerator.shortfalls(days: week, slots: [.breakfast, .dinner], meals: library, planned: [])

        XCTAssertEqual(shortfalls, [MealPlanGenerator.Shortfall(category: .breakfast, canFill: 3, needed: 7)])
    }

    func testSkippedMealsAreNotSuggested() {
        var library = meals(8, .breakfast, prefix: "Breakfast")
        library[0].skipInGeneratedPlans = true
        var random = SeededGenerator(state: 11)

        let plan = MealPlanGenerator.generate(days: week, slots: [.breakfast], meals: library, planned: [], using: &random)

        XCTAssertFalse(plan.contains { $0.mealID == library[0].id })
        XCTAssertEqual(MealPlanGenerator.shortfalls(days: week, slots: [.breakfast], meals: Array(library.prefix(7)), planned: []).first?.canFill, 6)
    }

    func testMealsAlreadyPlannedAreKeptAndCountTowardTheWeek() {
        let library = meals(7, .mainCourse, prefix: "Dinner")
        let planned = [PlannedMeal(mealID: library[0].id, date: week[2], slot: .dinner)]
        var random = SeededGenerator(state: 5)

        let plan = MealPlanGenerator.generate(days: week, slots: [.dinner], meals: library, planned: planned, using: &random)

        XCTAssertEqual(plan.count, 6)
        XCTAssertFalse(plan.contains { calendar.isDate($0.day, inSameDayAs: week[2]) })
        XCTAssertFalse(plan.contains { $0.mealID == library[0].id }, "Its one use this week is taken")
    }

    func testSwappingSuggestsADifferentMeal() {
        let library = meals(7, .mainCourse, timesPerWeek: 2, prefix: "Dinner")
        var random = SeededGenerator(state: 9)
        let plan = MealPlanGenerator.generate(days: week, slots: [.dinner], meals: library, planned: [], using: &random)
        let first = plan[0]

        let replacement = MealPlanGenerator.alternative(for: first, in: plan, meals: library, planned: [], days: week, using: &random)

        XCTAssertNotNil(replacement)
        XCTAssertNotEqual(replacement, first.mealID)
    }

    func testMealsSavedBeforeTheseOptionsDefaultToOnceAWeek() throws {
        let meal = try JSONDecoder().decode(MealIdea.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Dosa"}"#.utf8))
        XCTAssertEqual(meal.timesPerWeek, 1)
        XCTAssertFalse(meal.skipInGeneratedPlans)

        let roundTripped = try JSONDecoder().decode(MealIdea.self, from: JSONEncoder().encode(MealIdea(name: "Idly", timesPerWeek: 3, skipInGeneratedPlans: true)))
        XCTAssertEqual(roundTripped.timesPerWeek, 3)
        XCTAssertTrue(roundTripped.skipInGeneratedPlans)
    }

    // MARK: Shopping done

    func testFinishedShoppingIsNewsForTheRestOfTheFamily() {
        let costco = Shop(name: "Costco")
        var done = costco
        done.lastTripDoneAt = Date()
        done.lastTripDoneBy = "sam@example.com"
        done.lastTripItemCount = 5

        let news = ShoppingTripNews.newlyDone(before: [costco], after: [done], viewerEmail: "mum@example.com")

        XCTAssertEqual(news, [ShoppingTripNews(who: "Sam", shopName: "Costco", itemCount: 5)])
        XCTAssertEqual(news.first?.notificationBody, "Sam finished shopping at Costco (5 items).")
        XCTAssertTrue(ShoppingTripNews.newlyDone(before: [costco], after: [done], viewerEmail: "sam@example.com").isEmpty, "Not news to the shopper")
        XCTAssertTrue(ShoppingTripNews.newlyDone(before: [done], after: [done], viewerEmail: "mum@example.com").isEmpty, "Already seen")
    }
}
