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

    func testAvatarShowsWhoElseTheTaskIsFor() {
        let task = FamilyTask(title: "Pick up Maya", assignedToEmails: ["naveen@example.com", "priya@example.com"])
        XCTAssertEqual(task.avatarAssignee(viewerEmail: "naveen@example.com"), "priya@example.com")
        XCTAssertEqual(task.avatarAssignee(viewerEmail: "priya@example.com"), "naveen@example.com")
        XCTAssertEqual(FamilyTask(title: "Mine", assignedToEmails: ["naveen@example.com"]).avatarAssignee(viewerEmail: "naveen@example.com"), "naveen@example.com")
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

    // MARK: Quick due dates

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    func testQuickDueDatesPickSensibleTimes() {
        let thursdayAfternoon = date("2026-10-01 14:20")
        XCTAssertEqual(TaskDueChoice.today.dueDate(now: thursdayAfternoon), date("2026-10-01 18:00"))
        XCTAssertEqual(TaskDueChoice.tonight.dueDate(now: thursdayAfternoon), date("2026-10-01 19:00"))
        XCTAssertEqual(TaskDueChoice.tomorrow.dueDate(now: thursdayAfternoon), date("2026-10-02 09:00"))
        XCTAssertEqual(TaskDueChoice.weekend.dueDate(now: thursdayAfternoon), date("2026-10-03 10:00"))
        XCTAssertNil(TaskDueChoice.noDate.dueDate(now: thursdayAfternoon))
        XCTAssertNil(TaskDueChoice.pickDate.dueDate(now: thursdayAfternoon))
    }

    func testLateInTheDayTodayAndTonightMeanTheNextHour() {
        let lateEvening = date("2026-10-01 18:40")
        XCTAssertEqual(TaskDueChoice.today.dueDate(now: lateEvening), date("2026-10-01 20:00"))
        XCTAssertEqual(TaskDueChoice.tonight.dueDate(now: lateEvening), date("2026-10-01 20:00"))
    }

    func testThisWeekendOnSaturdayAfternoonMeansSundayMorning() {
        XCTAssertEqual(TaskDueChoice.weekend.dueDate(now: date("2026-10-03 15:00")), date("2026-10-04 10:00"))
        XCTAssertEqual(TaskDueChoice.weekend.dueDate(now: date("2026-10-03 08:00")), date("2026-10-03 10:00"))
    }

    func testExistingDueDatesHighlightTheMatchingChoice() {
        let now = date("2026-10-01 14:20")
        XCTAssertEqual(TaskDueChoice.matching(date("2026-10-02 09:00"), now: now), .tomorrow)
        XCTAssertEqual(TaskDueChoice.matching(date("2026-10-05 13:15"), now: now), .pickDate)
        XCTAssertEqual(TaskDueChoice.matching(nil, now: now), .noDate)
    }

    func testTaskTagTitles() {
        XCTAssertEqual(TaskBucket.allCases.map(\.tagTitle), ["Do now", "Schedule", "Delegate", "Someday"])
    }

    // MARK: Themes

    /// WCAG contrast ratio between two sRGB hex colors.
    private func contrast(_ a: UInt, _ b: UInt) -> Double {
        func luminance(_ hex: UInt) -> Double {
            func channel(_ value: UInt) -> Double {
                let c = Double(value) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testSundayMorningIsTheDefaultAndThemeIDsAreUnique() {
        XCTAssertEqual(ThemePalette.all.first?.id, ThemePalette.sundayMorning.id)
        XCTAssertEqual(ThemePalette.named(nil).id, ThemePalette.sundayMorning.id)
        XCTAssertEqual(ThemePalette.named("no-such-theme").id, ThemePalette.sundayMorning.id)
        XCTAssertEqual(Set(ThemePalette.all.map(\.id)).count, ThemePalette.all.count)
    }

    func testEveryThemeIsReadableInLightAndDarkMode() {
        for theme in ThemePalette.all {
            for mode in ["light", "dark"] {
                func value(_ swatch: Swatch) -> UInt { mode == "light" ? swatch.light : swatch.dark }
                func check(_ foreground: Swatch, on background: Swatch, _ what: String, minimum: Double = 4.5) {
                    let ratio = contrast(value(foreground), value(background))
                    XCTAssertGreaterThanOrEqual(ratio, minimum, "\(theme.name) \(mode): \(what) is \(String(format: "%.2f", ratio)):1")
                }

                check(theme.ink, on: theme.background, "text on background")
                check(theme.ink, on: theme.surface, "text on cards")
                check(theme.onPrimary, on: theme.primary, "icons on the main color")
                for (name, accent) in [("warm", theme.warmAccent), ("cool", theme.coolAccent), ("gold", theme.goldAccent),
                                       ("soft", theme.softAccent), ("bright", theme.brightAccent), ("done", theme.success),
                                       ("error", theme.destructive), ("main", theme.primary)] {
                    check(accent, on: theme.surface, "\(name) text on cards")
                }
                for (name, avatar) in [("main", theme.primary), ("soft", theme.softAccent), ("bright", theme.brightAccent),
                                       ("cool", theme.coolAccent), ("gold", theme.goldAccent), ("warm", theme.warmAccent)] {
                    check(theme.onAvatar, on: avatar, "initials on the \(name) avatar")
                }
            }
        }
    }

    // MARK: Tab bar

    func testTabBarDefaultsToMealPlanAndShopping() {
        XCTAssertEqual(TabSection.slots(from: ""), [.mealPlan, .shopping])
        XCTAssertEqual(TabSection.slots(from: "garbage"), [.mealPlan, .shopping])
    }

    func testSavedTabsAreKeptUniqueAndFilledToTwo() {
        XCTAssertEqual(TabSection.slots(from: "tasks,ideas"), [.tasks, .ideas])
        XCTAssertEqual(TabSection.slots(from: "tasks,tasks"), [.tasks, .mealPlan])
        XCTAssertEqual(TabSection.slots(from: TabSection.encode([.chores, .ideas])), [.chores, .ideas])
    }

    func testTheOldThreeTabSettingGivesTheNewDefault() {
        // The old setting always included Family; Meal Plan and Shopping replace it.
        XCTAssertEqual(TabSection.slots(from: "tasks,shopping,family"), [.mealPlan, .shopping])
        XCTAssertEqual(TabSection.slots(from: "family,tasks,chores"), [.mealPlan, .shopping])
    }

    func testPickingASectionAlreadyInTheOtherTabSwapsThem() {
        let slots: [TabSection] = [.mealPlan, .shopping]
        XCTAssertEqual(TabSection.replacing(slots, at: 0, with: .shopping), [.shopping, .mealPlan])
        XCTAssertEqual(TabSection.replacing(slots, at: 1, with: .tasks), [.mealPlan, .tasks])
    }

    // MARK: Locations

    func testTaskLocationIsSavedAndSynced() throws {
        let place = TaskLocation(name: "Costco", address: "1000 N Rengstorff Ave, Mountain View", latitude: 37.42, longitude: -122.09)
        let task = FamilyTask(title: "Pick up order", location: place)

        let decoded = try JSONDecoder().decode(FamilyTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded.location, place)

        let old = try JSONDecoder().decode(FamilyTask.self, from: Data(#"{"title":"No place"}"#.utf8))
        XCTAssertNil(old.location)
    }

    func testMapLinksUseCoordinatesWhenKnown() throws {
        let place = TaskLocation(name: "Costco", address: "1000 N Rengstorff Ave", latitude: 37.42, longitude: -122.09)

        let apple = try XCTUnwrap(MapApp.apple.url(for: place)).absoluteString
        XCTAssertTrue(apple.hasPrefix("https://maps.apple.com/"))
        XCTAssertTrue(apple.contains("ll=37.42,-122.09"))
        XCTAssertTrue(apple.contains("q=Costco"))

        let waze = try XCTUnwrap(MapApp.waze.url(for: place)).absoluteString
        XCTAssertEqual(waze, "https://waze.com/ul?ll=37.42,-122.09&navigate=yes")

        let google = try XCTUnwrap(MapApp.google.url(for: place)).absoluteString
        XCTAssertTrue(google.hasPrefix("https://www.google.com/maps/search/?api=1&query="))
        XCTAssertTrue(google.contains("Costco"))
    }

    func testTypedPlacesAreSearchedByName() throws {
        let place = TaskLocation(name: "Grandma's house")

        XCTAssertEqual(try XCTUnwrap(MapApp.apple.url(for: place)).absoluteString, "https://maps.apple.com/?q=Grandma's%20house")
        XCTAssertEqual(try XCTUnwrap(MapApp.waze.url(for: place)).absoluteString, "https://waze.com/ul?q=Grandma's%20house&navigate=yes")
        XCTAssertEqual(try XCTUnwrap(MapApp.google.url(for: place)).absoluteString, "https://www.google.com/maps/search/?api=1&query=Grandma's%20house")
    }
}
