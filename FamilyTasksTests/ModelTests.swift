import XCTest
@testable import FamilyTasks

final class ModelTests: XCTestCase {
    func testTaskDecodesWithMissingFields() throws {
        let task = try JSONDecoder().decode(FamilyTask.self, from: Data(#"{"title":"Old task"}"#.utf8))

        XCTAssertEqual(task.title, "Old task")
        XCTAssertFalse(task.isUrgent)
        XCTAssertTrue(task.isImportant)
        XCTAssertFalse(task.isDone)
        XCTAssertEqual(task.updatedAt, task.createdAt)
    }

    func testTaskRoundTripsThroughJSON() throws {
        let task = FamilyTask(title: "Round trip", dueDate: Date(timeIntervalSince1970: 1_000), isUrgent: true, assignedToEmails: ["a@example.com"])

        let decoded = try JSONDecoder().decode(FamilyTask.self, from: JSONEncoder().encode(task))

        XCTAssertEqual(decoded, task)
    }

    func testAssigneeEmailsAreSplitNormalizedAndDeduplicated() {
        let emails = FamilyTask.normalizedAssigneeEmails(
            [" B@Example.com", "a@example.com, b@example.com", Assignee.everyone, ""],
            legacyAssignedTo: "C@example.com"
        )

        XCTAssertEqual(emails, ["a@example.com", "b@example.com", "c@example.com"])
    }

    func testTaskVisibility() {
        let me = "me@example.com"
        XCTAssertTrue(FamilyTask(title: "Everyone", assignedTo: Assignee.everyone, createdBy: "other@example.com").isVisible(to: me))
        XCTAssertTrue(FamilyTask(title: "Mine", createdBy: me).isVisible(to: me))
        XCTAssertTrue(FamilyTask(title: "Assigned to me", assignedToEmails: [me], createdBy: "other@example.com").isVisible(to: me))
        XCTAssertFalse(FamilyTask(title: "Someone else's", assignedToEmails: ["kid@example.com"], createdBy: "other@example.com").isVisible(to: me))
    }

    func testBucketsMatchUrgencyAndImportance() {
        for bucket in TaskBucket.allCases {
            let flags = bucket.flags
            XCTAssertEqual(TaskBucket(urgent: flags.urgent, important: flags.important), bucket)
        }
        XCTAssertEqual(TaskBucket(urgent: true, important: true), .doNow)
        XCTAssertEqual(TaskBucket(urgent: false, important: false), .delete)
    }

    func testNotificationPreferenceKeepsOnlySupportedLeadTimes() {
        XCTAssertEqual(TaskNotificationPreference(leadMinutesList: [7, 13]).selectedLeadMinutes, [60])
        XCTAssertEqual(TaskNotificationPreference(leadMinutesList: [1_440, 15, 15, 99]).selectedLeadMinutes, [15, 1_440])
    }

    func testRecurrenceFrequencyAdvancesByOnePeriod() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(RecurrenceFrequency.daily.nextDate(after: start, calendar: calendar), calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(RecurrenceFrequency.yearly.nextDate(after: start, calendar: calendar), calendar.date(byAdding: .year, value: 1, to: start))
    }
}
