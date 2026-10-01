import AppIntents
import Foundation

/// A family member, for "Add a task for Sam" and the like. Members are stored by email,
/// so Siri knows them by the part before the @.
struct FamilyMemberEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Family Member"
    static let defaultQuery = FamilyMemberQuery()

    var id: String

    var name: String { Self.spokenName(for: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }

    /// "sam.smith@example.com" → "Sam Smith"
    static func spokenName(for email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        return localPart
            .split(whereSeparator: { ".-_+".contains($0) || $0.isNumber })
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func matches(_ email: String, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return false }
        return spokenName(for: email).lowercased().hasPrefix(query) || email.lowercased().hasPrefix(query)
    }
}

struct FamilyMemberQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FamilyMemberEntity] {
        members().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [FamilyMemberEntity] {
        members().filter { FamilyMemberEntity.matches($0.id, query: string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [FamilyMemberEntity] {
        members()
    }

    @MainActor
    private func members() -> [FamilyMemberEntity] {
        TaskStore.shared.exportFamilyMembers().map(FamilyMemberEntity.init(id:))
    }
}

/// An open task, so Siri can offer tasks to mark done by name.
struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    var id: UUID
    var title: String
    var dueDate: Date?

    init(_ task: FamilyTask) {
        id = task.id
        title = task.title
        dueDate = task.dueDate
    }

    var displayRepresentation: DisplayRepresentation {
        if let dueDate {
            DisplayRepresentation(title: "\(title)", subtitle: "Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        } else {
            DisplayRepresentation(title: "\(title)")
        }
    }
}

struct TaskQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        TaskStore.shared.visibleTasks.filter { identifiers.contains($0.id) }.map(TaskEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskEntity] {
        Self.openTasks(TaskStore.shared.visibleTasks)
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(TaskEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        Self.openTasks(TaskStore.shared.visibleTasks).prefix(20).map(TaskEntity.init)
    }

    /// Open tasks, soonest due first and undated ones last.
    static func openTasks(_ tasks: [FamilyTask]) -> [FamilyTask] {
        tasks
            .filter { !$0.isDone }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to Family Tasks, optionally for one family member and with a due date.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What's the task?")
    var taskTitle: String

    @Parameter(title: "For", description: "Leave empty to assign it to everyone.")
    var assignee: FamilyMemberEntity?

    @Parameter(title: "Due", kind: .dateTime)
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle)") {
            \.$assignee
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<TaskEntity> {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw $taskTitle.needsValueError("What's the task?")
        }

        var draft = TaskDraft()
        draft.title = title
        draft.includeDueDate = dueDate != nil
        draft.dueDate = dueDate ?? Date()
        if let assignee {
            draft.assignsToEveryone = false
            draft.assignedTo = assignee.id
            draft.assignedToEmails = [assignee.id]
        }

        let store = TaskStore.shared
        store.add(draft)
        await SharedHouseholdStore.shared.uploadNow(waitingAtMost: .seconds(8))

        let added = store.tasks.last { $0.title == title } ?? FamilyTask(title: title)
        let who = assignee.map { " for \($0.name)" } ?? ""
        return .result(value: TaskEntity(added), dialog: "Added \(title)\(who).")
    }
}

struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Tasks Due Today"
    static let description = IntentDescription("Lists your open tasks due today and any that are overdue.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[TaskEntity]> {
        let store = TaskStore.shared
        let due = store.tasksScheduledToday().filter { !$0.isDone }
        let overdue = store.pendingTasks(before: Date())
        return .result(
            value: (overdue + due).map(TaskEntity.init),
            dialog: "\(Self.summary(due: due.map(\.title), overdue: overdue.map(\.title)))"
        )
    }

    static func summary(due: [String], overdue: [String]) -> String {
        let list = { (titles: [String]) in ListFormatter.localizedString(byJoining: titles) }
        let overdueTasks = overdue.count == 1 ? "1 task is" : "\(overdue.count) tasks are"

        switch (due.count, overdue.isEmpty) {
        case (0, true):
            return "Nothing is due today."
        case (0, false):
            return "Nothing is due today, but \(overdueTasks) overdue: \(list(overdue))."
        default:
            let today = due.count == 1 ? "You have one task today: \(list(due))." : "You have \(due.count) tasks today: \(list(due))."
            return overdue.isEmpty ? today : "\(today) Also overdue: \(list(overdue))."
        }
    }
}

struct MarkTaskDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Task Done"
    static let description = IntentDescription("Marks one of your open tasks as done.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "Which task?")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$task) done")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TaskStore.shared
        guard let current = store.tasks.first(where: { $0.id == task.id }) else {
            return .result(dialog: "I couldn't find \(task.title). It may have been deleted.")
        }
        guard !current.isDone else {
            return .result(dialog: "\(current.title) is already done.")
        }

        store.markDone(taskID: current.id, at: Date())
        await SharedHouseholdStore.shared.uploadNow(waitingAtMost: .seconds(8))
        return .result(dialog: "Marked \(current.title) done.")
    }
}
