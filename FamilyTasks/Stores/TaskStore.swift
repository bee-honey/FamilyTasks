import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = [] {
        didSet { save() }
    }
    @Published private(set) var familyMembers: [String] = [] {
        didSet { saveFamilyMembers() }
    }

    private let storageURL: URL
    private let familyMembersURL: URL
    private var isApplyingSharedData = false

    init(storageURL: URL? = nil) {
        let documents = URL.documentsDirectory
        self.storageURL = storageURL ?? documents.appendingPathComponent("family-tasks.json")
        self.familyMembersURL = documents.appendingPathComponent("family-members.json")
        load()
        loadFamilyMembers()
        removeLegacyAssigneeNames()

        if tasks.isEmpty {
            tasks = [
                FamilyTask(title: "Book pediatrician appointment", notes: "Add to shared calendar once a time is picked.", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), isUrgent: true, isImportant: true),
                FamilyTask(title: "Plan school lunch rotation", dueDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()), isUrgent: false, isImportant: true),
                FamilyTask(title: "Reply to neighborhood RSVP", isUrgent: true, isImportant: false)
            ]
        }

        if familyMembers.isEmpty {
            let taskAssignees = tasks
                .map(\.assignedTo)
                .filter { Self.isValidEmail($0) }
            familyMembers = Array(Set(taskAssignees)).sorted()
        }
    }

    func tasks(in bucket: TaskBucket) -> [FamilyTask] {
        tasks
            .filter { $0.bucket == bucket }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.updatedAt > rhs.updatedAt
                }
            }
    }

    func tasksScheduledToday(calendar: Calendar = .current) -> [FamilyTask] {
        tasksScheduled(on: Date(), calendar: calendar)
    }

    func tasksScheduled(on date: Date, calendar: Calendar = .current) -> [FamilyTask] {
        tasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
            .sorted(by: taskScheduleSort)
    }

    func pendingTasks(before date: Date, calendar: Calendar = .current) -> [FamilyTask] {
        let startOfDay = calendar.startOfDay(for: date)
        return tasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate < startOfDay && !task.isDone
            }
            .sorted(by: taskScheduleSort)
    }

    func add(_ draft: TaskDraft) {
        tasks.append(
            FamilyTask(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: draft.includeDueDate ? draft.dueDate : nil,
                isUrgent: draft.isUrgent,
                isImportant: draft.isImportant,
                assignedTo: draft.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func update(_ task: FamilyTask, with draft: TaskDraft) {
        var changed = task
        changed.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.dueDate = draft.includeDueDate ? draft.dueDate : nil
        changed.isUrgent = draft.isUrgent
        changed.isImportant = draft.isImportant
        changed.assignedTo = draft.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        update(changed)
    }

    func update(_ task: FamilyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var changed = task
        changed.updatedAt = Date()
        tasks[index] = changed
    }

    func move(_ task: FamilyTask, to bucket: TaskBucket) {
        var changed = task
        let flags = bucket.flags
        changed.isUrgent = flags.urgent
        changed.isImportant = flags.important
        update(changed)
    }

    func markDone(_ task: FamilyTask) {
        var changed = task
        changed.isDone.toggle()
        update(changed)
    }

    func delete(_ task: FamilyTask) {
        tasks.removeAll { $0.id == task.id }
    }

    func setCalendarEventIdentifier(_ identifier: String?, for task: FamilyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].calendarEventIdentifier = identifier
        tasks[index].updatedAt = Date()
    }

    func addFamilyMember(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(trimmed) else { return }
        guard !familyMembers.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        familyMembers.append(trimmed)
        familyMembers.sort()
    }

    func assignUnassignedTasks(to assignee: String) {
        let trimmed = assignee.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(trimmed) else { return }

        var changed = false
        tasks = tasks.map { task in
            guard task.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return task
            }

            var assigned = task
            assigned.assignedTo = trimmed
            assigned.updatedAt = Date()
            changed = true
            return assigned
        }

        if changed {
            save()
        }
    }

    func deleteFamilyMember(at offsets: IndexSet) {
        familyMembers.remove(atOffsets: offsets)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        tasks = (try? JSONDecoder().decode([FamilyTask].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: storageURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadFamilyMembers() {
        guard let data = try? Data(contentsOf: familyMembersURL) else { return }
        familyMembers = (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func saveFamilyMembers() {
        guard let data = try? JSONEncoder().encode(familyMembers) else { return }
        try? data.write(to: familyMembersURL, options: [.atomic])
        notifySharedDataChanged()
    }

    func exportTasks() -> [FamilyTask] {
        tasks
    }

    func exportFamilyMembers() -> [String] {
        familyMembers
    }

    func applySharedData(tasks: [FamilyTask], familyMembers: [String]) {
        isApplyingSharedData = true
        self.tasks = tasks
        self.familyMembers = familyMembers
        save()
        saveFamilyMembers()
        isApplyingSharedData = false
    }

    private func notifySharedDataChanged() {
        guard !isApplyingSharedData else { return }
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    private func removeLegacyAssigneeNames() {
        let validMembers = familyMembers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(Self.isValidEmail)

        if validMembers != familyMembers {
            familyMembers = Array(Set(validMembers)).sorted()
        }

        var changedTasks = false
        tasks = tasks.map { task in
            guard !task.assignedTo.isEmpty, !Self.isValidEmail(task.assignedTo) else {
                return task
            }

            var cleaned = task
            cleaned.assignedTo = ""
            cleaned.updatedAt = Date()
            changedTasks = true
            return cleaned
        }

        if changedTasks {
            save()
        }
    }

    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func taskScheduleSort(_ lhs: FamilyTask, _ rhs: FamilyTask) -> Bool {
        if lhs.isDone != rhs.isDone {
            return !lhs.isDone
        }

        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

struct TaskDraft {
    var title = ""
    var notes = ""
    var assignedTo = ""
    var includeDueDate = true
    var dueDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    var isUrgent = true
    var isImportant = true

    init() {}

    init(task: FamilyTask) {
        title = task.title
        notes = task.notes
        assignedTo = task.assignedTo
        includeDueDate = task.dueDate != nil
        dueDate = task.dueDate ?? Date()
        isUrgent = task.isUrgent
        isImportant = task.isImportant
    }
}
