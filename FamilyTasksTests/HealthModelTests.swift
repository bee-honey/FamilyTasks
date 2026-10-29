import XCTest
@testable import FamilyTasks

@MainActor
final class HealthModelTests: XCTestCase {
    private let calendar = Calendar.current
    private let me = "me@example.com"
    private let sam = "sam@example.com"

    private func hours(_ value: Double) -> TimeInterval { value * 3_600 }

    private func snapshot(_ email: String, daysAgo: Int, steps: Double = 0, sleepScore: Int? = nil, now: Date = Date()) -> HealthSnapshot {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return HealthSnapshot(
            memberEmail: email,
            memberInitials: "",
            date: day,
            dayID: HabitMath.dayKey(for: day, calendar: calendar),
            steps: steps,
            sleepSeconds: 0,
            sleepScore: sleepScore
        )
    }

    // MARK: Sleep score

    func testSleepScoreFromDurationAlone() {
        XCTAssertEqual(SleepScore.score(for: SleepNight(asleep: hours(8))), 100)
        XCTAssertEqual(SleepScore.score(for: SleepNight(asleep: hours(6))), 75)
        XCTAssertEqual(SleepScore.score(for: SleepNight(asleep: hours(10))), 90)
        XCTAssertNil(SleepScore.score(for: SleepNight(asleep: 20 * 60)), "A short nap isn't a night")
    }

    func testSleepScoreWithStages() {
        let restful = SleepNight(asleep: hours(8), deepAndREM: hours(8) * 0.35, awake: 0)
        XCTAssertEqual(SleepScore.score(for: restful), 100)

        // Half an hour awake costs half the continuity part (12.5 points).
        let restless = SleepNight(asleep: hours(8), deepAndREM: hours(8) * 0.35, awake: 30 * 60)
        XCTAssertEqual(SleepScore.score(for: restless), 88)

        // Short and light: duration 0.75, restorative 0.5, continuity 0.
        let poor = SleepNight(asleep: hours(6), deepAndREM: hours(6) * 0.175, awake: hours(1))
        XCTAssertEqual(SleepScore.score(for: poor), 50)
    }

    func testSleepScoreLabels() {
        XCTAssertEqual(SleepScore.label(for: 92), "Excellent")
        XCTAssertEqual(SleepScore.label(for: 70), "Good")
        XCTAssertEqual(SleepScore.label(for: 55), "Fair")
        XCTAssertEqual(SleepScore.label(for: 30), "Poor")
    }

    func testANightWithStagesCountsTimeAwakeInBetween() {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        let data = HealthMetricsService.HealthRangeData(
            stepsByDay: [:],
            asleep: [DateInterval(start: at(-1), end: at(3)), DateInterval(start: at(3.5), end: at(7))],
            restorative: [DateInterval(start: at(0), end: at(2))],
            awake: [DateInterval(start: at(3), end: at(3.5))]
        )

        let night = data.night(in: DateInterval(start: at(0), end: at(24)), now: .distantFuture)

        XCTAssertEqual(night.asleep, hours(7.5), accuracy: 1)
        XCTAssertEqual(night.deepAndREM ?? 0, hours(2), accuracy: 1)
        XCTAssertEqual(night.awake ?? 0, hours(0.5), accuracy: 1)
    }

    func testANightWithoutStagesHasNone() {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let data = HealthMetricsService.HealthRangeData(
            stepsByDay: [:],
            asleep: [DateInterval(start: day.addingTimeInterval(-hours(1)), end: day.addingTimeInterval(hours(6)))]
        )

        let night = data.night(in: DateInterval(start: day, end: day.addingTimeInterval(hours(24))), now: .distantFuture)

        XCTAssertFalse(night.hasStages)
        XCTAssertEqual(night.asleep, hours(7), accuracy: 1)
    }

    // MARK: Body

    func testBMI() throws {
        let bmi = try XCTUnwrap(BodyMath.bmi(weightKg: 70, heightMeters: 1.75))
        XCTAssertEqual(bmi, 22.86, accuracy: 0.01)
        XCTAssertEqual(BodyMath.BMICategory(bmi: bmi), .healthy)
        XCTAssertEqual(BodyMath.BMICategory(bmi: 18.4), .underweight)
        XCTAssertEqual(BodyMath.BMICategory(bmi: 25), .overweight)
        XCTAssertEqual(BodyMath.BMICategory(bmi: 30), .obese)
        XCTAssertNil(BodyMath.bmi(weightKg: 70, heightMeters: 175), "Centimeters by mistake")
    }

    // MARK: Wind-down and tips

    func testWindDownTimesCountBackFromBedtime() {
        XCTAssertTrue(WindDownStep.food.time(bedtimeHour: 22, bedtimeMinute: 30) == (19, 30))
        XCTAssertTrue(WindDownStep.drinks.time(bedtimeHour: 22, bedtimeMinute: 30) == (20, 30))
        XCTAssertTrue(WindDownStep.screens.time(bedtimeHour: 22, bedtimeMinute: 30) == (21, 30))
        XCTAssertTrue(WindDownStep.food.time(bedtimeHour: 1, bedtimeMinute: 0) == (22, 0), "Wraps past midnight")
    }

    func testTipStaysTheSameAllDayAndChangesTheNext() {
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning)!

        XCTAssertEqual(HealthTips.tip(for: morning), HealthTips.tip(for: evening))
        XCTAssertNotEqual(HealthTips.tip(for: morning), HealthTips.tip(for: tomorrow))
        XCTAssertEqual(Set(HealthTips.all.map(\.title)).count, HealthTips.all.count, "Tip titles are unique")
    }

    // MARK: Goals

    func testGoalStreakSkipsAnUnfinishedToday() {
        let goal = HealthGoal(metric: .steps, target: 10_000, ownerEmail: me)
        let snapshots = [
            snapshot(me, daysAgo: 4, steps: 12_000),
            snapshot(me, daysAgo: 3, steps: 3_000),
            snapshot(me, daysAgo: 2, steps: 10_500),
            snapshot(me, daysAgo: 1, steps: 11_000),
            snapshot(me, daysAgo: 0, steps: 2_000),
            snapshot(sam, daysAgo: 3, steps: 20_000),
        ]

        let streak = HealthGoalMath.streak(of: goal, snapshots: snapshots)

        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.best, 2)
    }

    func testSleepScoreGoalUsesTheScore() {
        let goal = HealthGoal(metric: .sleepScore, target: 80, ownerEmail: me)
        let today = HabitMath.dayKey(for: Date())

        XCTAssertEqual(HealthGoalMath.value(of: goal, on: today, snapshots: [snapshot(me, daysAgo: 0, sleepScore: 84)]), 84)
        XCTAssertNil(HealthGoalMath.value(of: goal, on: today, snapshots: [snapshot(me, daysAgo: 0)]))
    }

    func testFamilyChallengeAddsUpEveryoneThisWeekOnly() {
        let now = Date()
        let week = HealthGoalMath.week(containing: now)
        let lastWeek = calendar.date(byAdding: .day, value: -1, to: week.start)!
        let goal = HealthGoal(metric: .steps, target: 50_000, kind: .family, ownerEmail: me)
        var old = snapshot(sam, daysAgo: 0, steps: 99_000)
        old.date = lastWeek
        old.dayID = HabitMath.dayKey(for: lastWeek)

        let totals = HealthGoalMath.weekTotals(
            of: goal,
            snapshots: [snapshot(me, daysAgo: 0, steps: 8_000, now: now), snapshot(sam, daysAgo: 0, steps: 6_000, now: now), old],
            now: now
        )

        XCTAssertEqual(totals.total, 14_000)
        XCTAssertEqual(totals.byMember, [me: 8_000, sam: 6_000])
        XCTAssertTrue(goal.isShared, "Family challenges are always shared")
    }

    func testFamilyAlertsForGoals() {
        let shared = HealthGoal(metric: .steps, target: 10_000, ownerEmail: me, isShared: true)
        let alerts = FamilyAlert.healthGoalReached(shared, value: 12_345, streak: 4, sender: me, senderName: "Asha", familyMembers: [me, sam])

        XCTAssertEqual(alerts.map(\.recipient), [sam])
        XCTAssertEqual(alerts.first?.kind, .healthGoal)
        XCTAssertEqual(alerts.first?.body, "Asha reached their goal of 10,000 steps a day: 12,345 steps today · 🔥 4 days in a row")

        let privateGoal = HealthGoal(metric: .steps, target: 10_000, ownerEmail: me, isShared: false)
        XCTAssertTrue(FamilyAlert.healthGoalReached(privateGoal, value: 12_345, streak: 0, sender: me, senderName: "Asha", familyMembers: [me, sam]).isEmpty)

        let cheer = FamilyAlert.cheer(recipient: "Sam@Example.com ", senderName: "Asha", highlight: "12,400 steps today")
        XCTAssertEqual(cheer.recipient, sam)
        XCTAssertEqual(cheer.title, "Asha cheered you on 👏")
        XCTAssertEqual(cheer.body, "For your 12,400 steps today. Keep it up!")
    }

    // MARK: Store

    private func makeStore() throws -> (HealthGoalStore, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "HealthModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        return (HealthGoalStore(directory: directory, defaults: defaults, ownerEmail: { self.me }), directory, defaults)
    }

    func testPrivateGoalsStayOnThePhone() throws {
        let (store, directory, defaults) = try makeStore()
        store.add(metric: .steps, target: 10_000, kind: .personal, isShared: false)
        store.add(metric: .sleepHours, target: 8, kind: .personal, isShared: true)
        store.add(metric: .steps, target: 100_000, kind: .family, isShared: false)

        XCTAssertEqual(store.exportPayload().map(\.metric), [.sleepHours, .steps])

        let samsGoal = HealthGoal(metric: .exerciseMinutes, target: 30, ownerEmail: sam, isShared: true)
        store.applySharedData(store.exportPayload() + [samsGoal])
        XCTAssertEqual(store.goals.count, 4, "Applying the family's goals keeps the private one")
        XCTAssertEqual(store.familyGoals, [samsGoal])

        let reloaded = HealthGoalStore(directory: directory, defaults: defaults, ownerEmail: { self.me })
        XCTAssertEqual(reloaded.goals, store.goals)
    }

    func testFamilyChallengesOnlyForNumbersThatAddUp() throws {
        let (store, _, _) = try makeStore()
        store.add(metric: .sleepScore, target: 80, kind: .family, isShared: true)
        XCTAssertTrue(store.challenges.isEmpty)
    }

    func testReachingASharedGoalIsAnnouncedOncePerDay() throws {
        let (store, _, _) = try makeStore()
        store.add(metric: .steps, target: 10_000, kind: .personal, isShared: true)
        store.add(metric: .exerciseMinutes, target: 30, kind: .personal, isShared: false)
        var announced: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .familyItemChangedLocally, object: nil, queue: nil) { note in
            if case let .healthGoal(goal, _, _)? = note.userInfo?["change"] as? LocalItemChange {
                announced.append(goal.metric.rawValue)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        var today = snapshot(me, daysAgo: 0, steps: 4_000)
        today.exerciseMinutes = 45
        store.announceAchievements(mine: [today], family: [])
        XCTAssertEqual(announced, [], "Not there yet, and the private goal is never news")

        today.steps = 10_200
        store.announceAchievements(mine: [today], family: [])
        store.announceAchievements(mine: [today], family: [])
        XCTAssertEqual(announced, ["steps"])
    }

    // MARK: Data from Health

    func testArrivingDataIsWhatShowsAsReceiving() {
        var day = snapshot(me, daysAgo: 1, steps: 4_000)
        day.restingHeartRate = 60
        let days = [day, snapshot(me, daysAgo: 0)]
        let weight = HealthReading(value: 70, date: Date())

        let arriving = HealthDataKind.allCases.filter {
            $0.isArriving(in: days, sleepStages: false, weight: weight, height: nil)
        }

        XCTAssertEqual(arriving, [.steps, .restingHeartRate, .weight])
        XCTAssertTrue(HealthDataKind.sleepStages.isArriving(in: [], sleepStages: true, weight: nil, height: nil))
    }

    // MARK: Sharing

    func testOlderSummariesStillRead() throws {
        let json = #"{"id":"a@example.com|2026-10-01","memberEmail":"a@example.com","memberInitials":"A","date":0,"dayID":"2026-10-01","steps":1200,"sleepSeconds":3600,"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(HealthSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.steps, 1_200)
        XCTAssertNil(snapshot.sleepScore)
        XCTAssertNil(snapshot.weightKg)
    }

    func testHeartAndBodyAreOnlySharedWhenIncluded() {
        var day = snapshot(me, daysAgo: 0, steps: 5_000, sleepScore: 80)
        day.restingHeartRate = 58
        day.hrv = 45
        day.weightKg = 70
        day.bmi = 22.9

        let shared = day.sharing(heart: false, body: false)
        XCTAssertNil(shared.restingHeartRate)
        XCTAssertNil(shared.hrv)
        XCTAssertNil(shared.weightKg)
        XCTAssertNil(shared.bmi)
        XCTAssertEqual(shared.steps, 5_000)
        XCTAssertEqual(shared.sleepScore, 80)

        XCTAssertEqual(day.sharing(heart: true, body: true), day)
    }

    func testGoalsRoundTripThroughSyncRecords() {
        let goal = HealthGoal(metric: .steps, target: 70_000, kind: .family, ownerEmail: me)
        let records = HouseholdRecords.records(from: SharedHouseholdPayload(healthGoals: [goal]), updatedBy: me)

        XCTAssertEqual(records[goal.id.uuidString]?.kind, .healthGoal)
        XCTAssertEqual(HouseholdRecords.payload(from: Array(records.values)).healthGoals, [goal])
    }
}
