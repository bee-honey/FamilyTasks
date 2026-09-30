import XCTest
@testable import FamilyTasks

final class NotificationTimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testUpcomingLeadTimesAreScheduledAtTheirTime() {
        let due = now.addingTimeInterval(3 * 3_600)

        let alerts = NotificationScheduler.leadTimeFireDates(dueDate: due, leadMinuteValues: [15, 60], now: now)

        XCTAssertEqual(alerts.map(\.leadMinutes), [15, 60])
        XCTAssertEqual(alerts.map(\.fireDate), [due.addingTimeInterval(-15 * 60), due.addingTimeInterval(-3_600)])
    }

    func testLeadTimesThatAlreadyPassedAreSkipped() {
        // Due in 3 days with a 1-week and a 1-day reminder: only the 1-day one is still ahead.
        let due = now.addingTimeInterval(3 * 86_400)

        let alerts = NotificationScheduler.leadTimeFireDates(dueDate: due, leadMinuteValues: [10_080, 1_440], now: now)

        XCTAssertEqual(alerts.map(\.leadMinutes), [1_440])
    }

    func testWhenEveryLeadTimeHasPassedOneAlertFiresAtTheDueTime() {
        let due = now.addingTimeInterval(10 * 60)

        let alerts = NotificationScheduler.leadTimeFireDates(dueDate: due, leadMinuteValues: [60, 1_440], now: now)

        XCTAssertEqual(alerts.map(\.leadMinutes), [0])
        XCTAssertEqual(alerts.map(\.fireDate), [due])
    }

    func testNothingIsScheduledForPastTasksOrWhenRemindersAreOff() {
        XCTAssertTrue(NotificationScheduler.leadTimeFireDates(dueDate: now.addingTimeInterval(-60), leadMinuteValues: [15], now: now).isEmpty)
        XCTAssertTrue(NotificationScheduler.leadTimeFireDates(dueDate: now.addingTimeInterval(3_600), leadMinuteValues: [], now: now).isEmpty)
    }
}
