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

    // MARK: Done by

    private func doneTask(_ title: String, by email: String, at date: Date = Date(), assignedTo: [String] = []) -> FamilyTask {
        FamilyTask(title: title, isDone: true, assignedTo: assignedTo.first ?? Assignee.everyone, assignedToEmails: assignedTo, createdBy: "parent@example.com", completedBy: email, completedAt: date)
    }

    func testCompletionFieldsSurviveEncodingAndAreOptionalWhenDecoding() throws {
        let task = doneTask("Bins", by: "sam@example.com")
        let decoded = try JSONDecoder().decode(FamilyTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded.completedBy, "sam@example.com")
        XCTAssertEqual(decoded.completedAt, task.completedAt)

        let old = try JSONDecoder().decode(FamilyTask.self, from: Data(#"{"title":"Old","isDone":true}"#.utf8))
        XCTAssertNil(old.completedBy)
        XCTAssertNil(old.completedAt)
    }

    func testCompletionSummaryNamesWhoFinishedIt() {
        let now = Date()
        let calendar = Calendar.current
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: now)!

        XCTAssertEqual(
            doneTask("Bins", by: "sam.smith@example.com", at: now).completionSummary(viewerEmail: "mum@example.com", now: now),
            "Done by Sam Smith · \(now.formatted(date: .omitted, time: .shortened))"
        )
        XCTAssertEqual(
            doneTask("Bins", by: "mum@example.com", at: lastWeek).completionSummary(viewerEmail: "Mum@example.com", now: now),
            "Done by you · \(lastWeek.formatted(.dateTime.month(.abbreviated).day()))"
        )
        XCTAssertNil(FamilyTask(title: "Open").completionSummary(viewerEmail: "mum@example.com"))
        XCTAssertNil(FamilyTask(title: "Done long ago", isDone: true).completionSummary(viewerEmail: "mum@example.com"))
    }

    func testOnlyTasksSomeoneElseJustFinishedAreNews() {
        let viewer = "mum@example.com"
        let open = [
            FamilyTask(title: "By Sam"),
            FamilyTask(title: "By me"),
            FamilyTask(title: "Finished yesterday morning"),
            FamilyTask(title: "Private to Sam", assignedTo: "sam@example.com", assignedToEmails: ["sam@example.com"], createdBy: "sam@example.com")
        ]
        var after = open
        for index in after.indices {
            after[index].isDone = true
            after[index].completedBy = index == 1 ? viewer : "sam@example.com"
            after[index].completedAt = index == 2 ? Date().addingTimeInterval(-2 * 86_400) : Date()
        }
        let alreadyDone = doneTask("Never seen open", by: "sam@example.com")

        let news = TaskCompletion.newlyCompleted(before: open, after: after + [alreadyDone], viewerEmail: viewer)

        XCTAssertEqual(news, [TaskCompletion(who: "Sam", title: "By Sam")])
    }

    func testCompletionNotificationText() {
        let sam = { TaskCompletion(who: "Sam", title: $0) }
        XCTAssertEqual(TaskCompletion.notificationBody(for: [sam("Take out bins")]), "Sam finished Take out bins.")
        XCTAssertEqual(TaskCompletion.notificationBody(for: [sam("Bins"), sam("Dishes")]), "Sam finished Bins and Dishes.")
        XCTAssertEqual(TaskCompletion.notificationBody(for: [sam("Bins"), sam("Dishes"), sam("Laundry"), sam("Mow")]), "Sam finished Bins, Dishes and 2 more.")
        XCTAssertEqual(
            TaskCompletion.notificationBody(for: [sam("Bins"), TaskCompletion(who: "Mum", title: "Groceries")]),
            "Sam and Mum finished Bins and Groceries."
        )
    }
}
