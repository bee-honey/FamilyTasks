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

    // MARK: History

    private func entry(_ id: String, daysAgo: Double, title: String = "Title") -> NotificationHistory.Entry {
        NotificationHistory.Entry(id: id, title: title, body: "Body", date: now.addingTimeInterval(-daysAgo * 86_400), kind: .other)
    }

    func testHistoryKeepsAWeekNewestFirstAndEachNotificationOnce() {
        let existing = [entry("a", daysAgo: 1, title: "First seen"), entry("old", daysAgo: 8)]
        let new = [entry("a", daysAgo: 1, title: "Seen again"), entry("b", daysAgo: 0.5), entry("c", daysAgo: 6.9)]

        let merged = NotificationHistory.merged(existing, with: new, now: now)

        XCTAssertEqual(merged.map(\.id), ["b", "a", "c"])
        XCTAssertEqual(merged.first { $0.id == "a" }?.title, "First seen")
    }

    func testHistoryKindComesFromTheIdentifier() {
        XCTAssertEqual(NotificationHistory.kind(identifier: "familytasks.todayDigest.2026-10-16.morning", userInfo: [:]), .dailyList)
        XCTAssertEqual(NotificationHistory.kind(identifier: "familytasks.dueSoon.abc.60", userInfo: [:]), .dueSoon)
        XCTAssertEqual(NotificationHistory.kind(identifier: "familytasks.recurringDueSoon.abc.0", userInfo: [:]), .recurringDueSoon)
        XCTAssertEqual(NotificationHistory.kind(identifier: "familytasks.shoppingDone.x", userInfo: [:]), .shopping)
        XCTAssertEqual(NotificationHistory.kind(identifier: "something-else", userInfo: [:]), .other)
    }
}
