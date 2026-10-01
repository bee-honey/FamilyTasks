import XCTest
@testable import FamilyTasks

final class TaskIntentsTests: XCTestCase {
    func testFamilyMembersAreSpokenByTheirEmailName() {
        XCTAssertEqual(FamilyMemberEntity.spokenName(for: "sam.smith@example.com"), "Sam Smith")
        XCTAssertEqual(FamilyMemberEntity.spokenName(for: "mum_2024@example.com"), "Mum")
        XCTAssertEqual(FamilyMemberEntity.spokenName(for: "alex@example.com"), "Alex")
    }

    func testFamilyMembersMatchByNameOrEmail() {
        XCTAssertTrue(FamilyMemberEntity.matches("sam.smith@example.com", query: "Sam"))
        XCTAssertTrue(FamilyMemberEntity.matches("sam.smith@example.com", query: "sam smith"))
        XCTAssertTrue(FamilyMemberEntity.matches("sam.smith@example.com", query: "sam.smith@"))
        XCTAssertFalse(FamilyMemberEntity.matches("sam.smith@example.com", query: "Alex"))
        XCTAssertFalse(FamilyMemberEntity.matches("sam.smith@example.com", query: " "))
    }

    func testSuggestedTasksAreOpenAndSoonestFirst() {
        let now = Date()
        let tasks = [
            FamilyTask(title: "Later", dueDate: now.addingTimeInterval(86_400)),
            FamilyTask(title: "No date"),
            FamilyTask(title: "Done", dueDate: now, isDone: true),
            FamilyTask(title: "Overdue", dueDate: now.addingTimeInterval(-86_400))
        ]

        XCTAssertEqual(TaskQuery.openTasks(tasks).map(\.title), ["Overdue", "Later", "No date"])
    }

    func testTodaySummaryReadsNaturally() {
        XCTAssertEqual(TodayTasksIntent.summary(due: [], overdue: []), "Nothing is due today.")
        XCTAssertEqual(TodayTasksIntent.summary(due: ["Bins"], overdue: []), "You have one task today: Bins.")
        XCTAssertEqual(
            TodayTasksIntent.summary(due: ["Bins", "Dentist"], overdue: ["Taxes"]),
            "You have 2 tasks today: Bins and Dentist. Also overdue: Taxes."
        )
        XCTAssertEqual(
            TodayTasksIntent.summary(due: [], overdue: ["Taxes", "Car"]),
            "Nothing is due today, but 2 tasks are overdue: Taxes and Car."
        )
    }
}
