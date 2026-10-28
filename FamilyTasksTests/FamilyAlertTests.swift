import XCTest
@testable import FamilyTasks

final class FamilyAlertTests: XCTestCase {
    private let mum = "mum@example.com"
    private let sam = "sam@example.com"
    private let kid = "kid@example.com"
    private var family: [String] { [mum, sam, kid] }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Tuesday 13 Oct 2026, 10:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 10))!
    }

    private func task(_ title: String, for people: [String], by creator: String? = nil, due: Date? = nil) -> FamilyTask {
        FamilyTask(
            title: title,
            dueDate: due,
            assignedTo: people.first ?? "",
            assignedToEmails: people,
            createdBy: creator ?? mum
        )
    }

    private func taskAlerts(before: FamilyTask?, after: FamilyTask, sender: String? = nil) -> [FamilyAlert] {
        FamilyAlert.taskAlerts(
            before: before,
            after: after,
            sender: sender ?? mum,
            senderName: Assignee.memberName(for: sender ?? mum),
            familyMembers: family,
            now: now,
            calendar: calendar
        )
    }

    // MARK: Nudges

    func testNudgeGoesToEveryoneElseOnTheTask() {
        let bins = task("Take out bins", for: [mum, kid])

        let alerts = FamilyAlert.nudges(for: bins, dueDate: nil, sender: mum, senderName: "Mum", familyMembers: family, now: now, calendar: calendar)

        XCTAssertEqual(alerts.map(\.recipient), [kid])
        XCTAssertEqual(alerts.first?.kind, .nudge)
        XCTAssertEqual(alerts.first?.title, "Mum nudged you")
        XCTAssertEqual(alerts.first?.body, "Please do Take out bins.")
    }

    func testNudgeForEveryoneGoesToTheWholeFamilyButTheSender() {
        var dishes = task("Dishes", for: [])
        dishes.assignedTo = Assignee.everyone

        let recipients = FamilyAlert.nudgeRecipients(for: dishes, sender: "Mum@Example.com ", familyMembers: family)

        XCTAssertEqual(recipients, [kid, sam])
    }

    func testNobodyToNudgeOnYourOwnTask() {
        XCTAssertTrue(FamilyAlert.nudgeRecipients(for: task("Mine", for: [mum]), sender: mum, familyMembers: family).isEmpty)
    }

    func testNudgeMentionsWhenItsDue() {
        let overdue = calendar.date(byAdding: .day, value: -2, to: now)!
        let alerts = FamilyAlert.nudges(for: task("Homework", for: [kid]), dueDate: overdue, sender: mum, senderName: "Mum", familyMembers: family, now: now, calendar: calendar)

        XCTAssertTrue(alerts[0].body.hasPrefix("Please do Homework (overdue since"), alerts[0].body)
    }

    // MARK: Task changes

    func testNewTaskTellsItsPeopleButNotTheSender() {
        let alerts = taskAlerts(before: nil, after: task("Homework", for: [mum, kid]))

        XCTAssertEqual(alerts.map(\.recipient), [kid])
        XCTAssertEqual(alerts.map(\.kind), [.assigned])
        XCTAssertEqual(alerts.first?.title, "New task from Mum")
    }

    func testFinishingTellsItsPeopleAndWhoAddedIt() {
        let before = task("Homework", for: [kid, sam], by: mum)
        var after = before
        after.isDone = true

        let alerts = taskAlerts(before: before, after: after, sender: kid)

        XCTAssertEqual(alerts.map(\.recipient), [mum, sam])
        XCTAssertEqual(Set(alerts.map(\.kind)), [.completed])
        XCTAssertEqual(alerts.first?.body, "Kid finished Homework.")
    }

    func testEditsTellKeptAddedAndRemovedPeopleDifferently() {
        let before = task("Homework", for: [mum, kid])
        var after = task("Maths homework", for: [mum, sam])
        after.id = before.id

        let alerts = taskAlerts(before: before, after: after)

        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts.first { $0.recipient == sam }?.kind, .assigned)
        XCTAssertEqual(alerts.first { $0.recipient == kid }?.body, "Mum took you off Maths homework.")
    }

    func testChangedFieldsAreNamed() {
        let before = task("Homework", for: [mum, kid])
        var after = before
        after.title = "Maths homework"
        after.notes = "Page 12"

        let alerts = taskAlerts(before: before, after: after)

        XCTAssertEqual(alerts.map(\.kind), [.updated])
        XCTAssertEqual(alerts.first?.body, "Mum changed the title and notes of Maths homework.")
    }

    func testDeviceOnlyChangesSendNothing() {
        let before = task("Homework", for: [mum, kid])
        var after = before
        after.calendarEventIdentifier = "event"
        after.notificationPreference = TaskNotificationPreference(usesDefaultSettings: false)
        after.updatedAt = now

        XCTAssertTrue(taskAlerts(before: before, after: after).isEmpty)
    }

    func testReopeningIsAnUpdate() {
        var before = task("Homework", for: [mum, kid])
        before.isDone = true
        var after = before
        after.isDone = false

        XCTAssertEqual(taskAlerts(before: before, after: after).map(\.title), ["Task reopened"])
    }

    // MARK: Recurring tasks

    func testDoingARecurringTaskTellsTheOthers() {
        let rent = RecurringTask(title: "Pay rent", nextDueDate: now, assignedTo: Assignee.everyone, createdBy: mum)
        var after = rent
        after.nextDueDate = calendar.date(byAdding: .month, value: 1, to: now)!

        let alerts = FamilyAlert.recurringAlerts(
            before: rent, after: after, completedOccurrence: true,
            sender: sam, senderName: "Sam", familyMembers: family, now: now, calendar: calendar
        )

        XCTAssertEqual(alerts.map(\.recipient), [kid, mum])
        XCTAssertTrue(alerts.allSatisfy { $0.kind == .completed })
        XCTAssertTrue(alerts[0].body.hasPrefix("Sam did Pay rent. Next one is"), alerts[0].body)
    }

    func testPausingARecurringTaskSendsNothing() {
        let rent = RecurringTask(title: "Pay rent", nextDueDate: now, assignedTo: Assignee.everyone, createdBy: mum)
        var paused = rent
        paused.isActive = false

        XCTAssertTrue(FamilyAlert.recurringAlerts(
            before: rent, after: paused, completedOccurrence: false,
            sender: mum, senderName: "Mum", familyMembers: family, now: now, calendar: calendar
        ).isEmpty)
    }

    // MARK: Habits

    func testFinishingASharedHabitTellsEveryoneElse() {
        let water = Habit(name: "Drink water", timesPerDay: 8, ownerEmail: sam, isShared: true)

        let alerts = FamilyAlert.habitDone(water, streak: 12, sender: sam, senderName: "Sam", familyMembers: family)

        XCTAssertEqual(alerts.map(\.recipient), [kid, mum])
        XCTAssertTrue(alerts.allSatisfy { $0.kind == .habit })
        XCTAssertEqual(alerts[0].body, "Sam did Drink water today (8 of 8) · 🔥 12 days in a row")
    }

    func testAFirstDayOnceADayHabitReadsSimply() {
        let read = Habit(name: "Read", ownerEmail: sam, isShared: true)
        let alerts = FamilyAlert.habitDone(read, streak: 1, sender: sam, senderName: "Sam", familyMembers: family)
        XCTAssertEqual(alerts.first?.body, "Sam did Read today")
    }

    func testPrivateHabitsSendNothing() {
        let diary = Habit(name: "Diary", ownerEmail: sam, isShared: false)
        XCTAssertTrue(FamilyAlert.habitDone(diary, streak: 3, sender: sam, senderName: "Sam", familyMembers: family).isEmpty)
    }

    // MARK: Delivery

    func testRecipientKeyHidesTheEmailButMatchesAnySpelling() {
        let key = FamilyAlertService.recipientKey(for: kid)

        XCTAssertEqual(key, FamilyAlertService.recipientKey(for: " Kid@Example.com"))
        XCTAssertNotEqual(key, FamilyAlertService.recipientKey(for: sam))
        XCTAssertFalse(key.contains("kid"))
        XCTAssertEqual(key.count, 64)
    }

    func testWantedKindsFollowSettings() {
        let defaults = UserDefaults(suiteName: "FamilyAlertTests")!
        defaults.removePersistentDomain(forName: "FamilyAlertTests")

        XCTAssertEqual(FamilyAlertService.wantedKinds(defaults: defaults), [])

        defaults.set(true, forKey: "notifications.enabled")
        XCTAssertEqual(FamilyAlertService.wantedKinds(defaults: defaults), [.nudge, .assigned, .updated, .completed, .shopping, .habit])

        defaults.set(false, forKey: "notifications.taskChanges")
        defaults.set(false, forKey: "notifications.familyCompletions")
        defaults.set(false, forKey: "notifications.familyShopping")
        defaults.set(false, forKey: "notifications.familyHabits")
        XCTAssertEqual(FamilyAlertService.wantedKinds(defaults: defaults), [.nudge])
    }

    // MARK: Daily lists

    func testDailyListHasOnlyMyOpenTasksDueByTonight() {
        let earlier = calendar.date(byAdding: .day, value: -1, to: now)!
        let tonight = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        var done = task("Done already", for: [kid], due: tonight)
        done.isDone = true
        let tasks = [
            task("Tonight", for: [kid], due: tonight),
            task("Yesterday's", for: [kid], due: earlier),
            task("Tomorrow's", for: [kid], due: tomorrow),
            task("Sam's", for: [sam], due: tonight),
            task("Whenever", for: [kid]),
            done
        ]
        let recurring = [
            RecurringTask(title: "Feed the cat", nextDueDate: now, assignedTo: kid, assignedToEmails: [kid]),
            RecurringTask(title: "Mow", nextDueDate: tomorrow, assignedTo: kid, assignedToEmails: [kid])
        ]

        let list = DailyTaskList.make(on: now, tasks: tasks, recurringTasks: recurring, viewer: kid, calendar: calendar)

        XCTAssertEqual(list.entries.map(\.title), ["Yesterday's", "Feed the cat", "Tonight", "Whenever"])
        XCTAssertEqual(list.entries.map(\.detail), ["overdue", "repeats", tonight.formatted(date: .omitted, time: .shortened), nil])
    }

    func testDailyListBodyShowsSixThenACount() {
        let list = DailyTaskList(entries: (1...8).map { DailyTaskList.Entry(title: "Task \($0)", detail: $0 == 1 ? "overdue" : nil) })
        let lines = list.body.split(separator: "\n")

        XCTAssertEqual(lines.count, 7)
        XCTAssertEqual(lines.first, "• Task 1 — overdue")
        XCTAssertEqual(lines.last, "+2 more")
    }
}
