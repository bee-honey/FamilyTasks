import XCTest
@testable import FamilyTasks

final class HealthAggregationTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    private let farFuture = Date.distantFuture

    private func at(_ hours: Double) -> Date {
        day.addingTimeInterval(hours * 3_600)
    }

    func testOverlappingSleepFromDifferentSourcesIsCountedOnce() {
        // Watch: 23:00-07:00, iPhone: 22:30-06:00, a nap later that day.
        let merged = HealthMetricsService.mergedIntervals([
            DateInterval(start: at(-1), end: at(7)),
            DateInterval(start: at(-1.5), end: at(6)),
            DateInterval(start: at(14), end: at(15))
        ])

        XCTAssertEqual(merged, [DateInterval(start: at(-1.5), end: at(7)), DateInterval(start: at(14), end: at(15))])
    }

    func testTouchingIntervalsAreJoined() {
        let merged = HealthMetricsService.mergedIntervals([
            DateInterval(start: at(2), end: at(3)),
            DateInterval(start: at(1), end: at(2))
        ])

        XCTAssertEqual(merged, [DateInterval(start: at(1), end: at(3))])
    }

    func testDurationIsClippedToTheWindow() {
        let total = HealthMetricsService.totalDuration(
            of: [DateInterval(start: at(-2), end: at(2)), DateInterval(start: at(5), end: at(6))],
            in: DateInterval(start: at(0), end: at(5.5))
        )

        XCTAssertEqual(total, 2.5 * 3_600, accuracy: 0.001)
    }

    func testSleepWindowRunsFromSixPMTheEveningBefore() {
        let window = HealthMetricsService.sleepWindow(start: at(0), end: at(24), now: farFuture)

        XCTAssertEqual(window, DateInterval(start: at(-6), end: at(18)))
    }

    func testSleepWindowForTodayRunsUntilNow() {
        let now = at(9)

        let window = HealthMetricsService.sleepWindow(start: at(0), end: now, now: now)

        XCTAssertEqual(window, DateInterval(start: at(-6), end: now))
    }

    func testANightCountsTowardTheDayYouWakeUp() {
        let data = HealthMetricsService.HealthRangeData(
            stepsByDay: [:],
            asleep: [DateInterval(start: at(-1), end: at(7))]
        )

        let wakeDay = data.sleep(in: DateInterval(start: at(0), end: at(24)), now: farFuture)
        let dayBefore = data.sleep(in: DateInterval(start: at(-24), end: at(0)), now: farFuture)

        XCTAssertEqual(wakeDay, 8 * 3_600, accuracy: 0.001)
        XCTAssertEqual(dayBefore, 0, accuracy: 0.001)
    }

    func testStepsAreSummedForDaysInsideTheInterval() {
        let data = HealthMetricsService.HealthRangeData(
            stepsByDay: [at(-24): 1_000, at(0): 2_000, at(24): 4_000],
            asleep: []
        )

        XCTAssertEqual(data.steps(in: DateInterval(start: at(0), end: at(48)), calendar: calendar), 6_000)
        XCTAssertEqual(data.steps(in: DateInterval(start: at(0), end: at(24)), calendar: calendar), 2_000)
    }
}
