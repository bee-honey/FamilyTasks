import Foundation

/// Something with people on it: a task or a recurring task.
protocol AssignedItem {
    var id: UUID { get }
    var title: String { get }
    var assigneeEmails: [String] { get }
    var isAssignedToEveryone: Bool { get }
    var createdBy: String { get }
}

extension FamilyTask: AssignedItem {}
extension RecurringTask: AssignedItem {}

extension AssignedItem {
    /// Whether it's on this person's own list: assigned to them or everyone, or nobody's
    /// and theirs. With no profile email, everything counts.
    func isAssigned(to email: String) -> Bool {
        let email = FamilyAlert.normalized(email)
        guard !email.isEmpty, !isAssignedToEveryone else { return true }
        let assignees = assigneeEmails
        if assignees.isEmpty {
            let creator = FamilyAlert.normalized(createdBy)
            return creator.isEmpty || creator == email
        }
        return assignees.contains(email)
    }

    /// The people it's for: its assignees, or the whole family when it's for everyone.
    func people(familyMembers: [String]) -> Set<String> {
        let emails = isAssignedToEveryone ? familyMembers : assigneeEmails
        return Set(emails.map(FamilyAlert.normalized).filter { !$0.isEmpty })
    }
}

/// A push to one family member: a nudge, or news about a task that's theirs.
struct FamilyAlert: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case nudge
        case assigned
        case updated
        case completed
    }

    var kind: Kind
    var recipient: String
    var title: String
    var body: String
    var itemID: String

    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The name alerts use for whoever sent them: their profile name, else one made from their email.
    static func senderName(email: String, profileName: String) -> String {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Assignee.memberName(for: email) : name
    }

    // MARK: Nudges

    /// Who a nudge about `item` goes to: everyone it's for except the sender.
    static func nudgeRecipients(for item: some AssignedItem, sender: String, familyMembers: [String]) -> [String] {
        var people = item.people(familyMembers: familyMembers)
        people.remove(normalized(sender))
        return people.sorted()
    }

    static func nudges(
        for item: some AssignedItem,
        dueDate: Date?,
        sender: String,
        senderName: String,
        familyMembers: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FamilyAlert] {
        let due = dueDate.map { " (\(dueText($0, now: now, calendar: calendar)))" } ?? ""
        return nudgeRecipients(for: item, sender: sender, familyMembers: familyMembers).map {
            FamilyAlert(
                kind: .nudge,
                recipient: $0,
                title: "\(senderName) nudged you",
                body: "Please do \(item.title)\(due).",
                itemID: item.id.uuidString
            )
        }
    }

    // MARK: Task changes

    /// What to tell people when this person adds, edits or finishes a task. Edits to done
    /// tasks and fields only this device uses (calendar links, reminder times) send nothing.
    static func taskAlerts(
        before: FamilyTask?,
        after: FamilyTask,
        sender: String,
        senderName: String,
        familyMembers: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FamilyAlert] {
        let sender = normalized(sender)
        var peopleAfter = after.people(familyMembers: familyMembers)
        peopleAfter.remove(sender)
        let itemID = after.id.uuidString
        let due = after.dueDate.map { " · \(dueText($0, now: now, calendar: calendar))" } ?? ""

        func alerts(_ kind: Kind, to people: Set<String>, title: String, body: String) -> [FamilyAlert] {
            people.sorted().map { FamilyAlert(kind: kind, recipient: $0, title: title, body: body, itemID: itemID) }
        }

        guard let before else {
            guard !after.isDone else { return [] }
            return alerts(.assigned, to: peopleAfter, title: "New task from \(senderName)", body: "\(after.title)\(due)")
        }

        if !before.isDone, after.isDone {
            // The person who added it hears about it too, even when it wasn't for them.
            var people = peopleAfter
            let creator = normalized(after.createdBy)
            if !creator.isEmpty, creator != sender { people.insert(creator) }
            return alerts(.completed, to: people, title: "Task done", body: "\(senderName) finished \(after.title).")
        }

        if before.isDone, !after.isDone {
            return alerts(.updated, to: peopleAfter, title: "Task reopened", body: "\(senderName) reopened \(after.title)\(due).")
        }

        guard !after.isDone else { return [] }

        var peopleBefore = before.people(familyMembers: familyMembers)
        peopleBefore.remove(sender)
        let added = peopleAfter.subtracting(peopleBefore)
        let kept = peopleAfter.intersection(peopleBefore)
        let removed = peopleBefore.subtracting(peopleAfter)
        let changes = changedFields(from: before, to: after)

        var result = alerts(.assigned, to: added, title: "New task from \(senderName)", body: "\(after.title)\(due)")
        if !changes.isEmpty {
            result += alerts(
                .updated,
                to: kept,
                title: "Task updated",
                body: "\(senderName) changed the \(ListFormatter.localizedString(byJoining: changes)) of \(after.title)\(due)."
            )
        }
        result += alerts(.updated, to: removed, title: "Task updated", body: "\(senderName) took you off \(after.title).")
        return result
    }

    /// What to tell people when this person adds, edits or does a recurring task.
    static func recurringAlerts(
        before: RecurringTask?,
        after: RecurringTask,
        completedOccurrence: Bool,
        sender: String,
        senderName: String,
        familyMembers: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FamilyAlert] {
        let sender = normalized(sender)
        var peopleAfter = after.people(familyMembers: familyMembers)
        peopleAfter.remove(sender)
        let itemID = after.id.uuidString
        let next = dueText(after.nextDueDate, now: now, calendar: calendar)

        func alerts(_ kind: Kind, to people: Set<String>, title: String, body: String) -> [FamilyAlert] {
            people.sorted().map { FamilyAlert(kind: kind, recipient: $0, title: title, body: body, itemID: itemID) }
        }

        if completedOccurrence {
            var people = peopleAfter
            let creator = normalized(after.createdBy)
            if !creator.isEmpty, creator != sender { people.insert(creator) }
            return alerts(.completed, to: people, title: "Recurring task done", body: "\(senderName) did \(after.title). Next one is \(next).")
        }

        guard after.isActive else { return [] }

        guard let before else {
            return alerts(
                .assigned,
                to: peopleAfter,
                title: "New recurring task from \(senderName)",
                body: "\(after.title) · \(after.frequency.title.lowercased()), first \(next)"
            )
        }

        var peopleBefore = before.people(familyMembers: familyMembers)
        peopleBefore.remove(sender)
        let added = peopleAfter.subtracting(peopleBefore)
        let kept = peopleAfter.intersection(peopleBefore)
        let removed = peopleBefore.subtracting(peopleAfter)
        let changes = changedFields(from: before, to: after)

        var result = alerts(
            .assigned,
            to: added,
            title: "New recurring task from \(senderName)",
            body: "\(after.title) · \(after.frequency.title.lowercased()), next \(next)"
        )
        if !changes.isEmpty || !before.isActive {
            let what = before.isActive
                ? "changed the \(ListFormatter.localizedString(byJoining: changes)) of"
                : "resumed"
            result += alerts(.updated, to: kept, title: "Recurring task updated", body: "\(senderName) \(what) \(after.title). Next one is \(next).")
        }
        result += alerts(.updated, to: removed, title: "Recurring task updated", body: "\(senderName) took you off \(after.title).")
        return result
    }

    static func changedFields(from before: FamilyTask, to after: FamilyTask) -> [String] {
        var fields: [String] = []
        if before.title != after.title { fields.append("title") }
        if before.dueDate != after.dueDate { fields.append("due date") }
        if before.isUrgent != after.isUrgent || before.isImportant != after.isImportant { fields.append("priority") }
        if before.notes != after.notes { fields.append("notes") }
        if before.location != after.location { fields.append("place") }
        return fields
    }

    static func changedFields(from before: RecurringTask, to after: RecurringTask) -> [String] {
        var fields: [String] = []
        if before.title != after.title { fields.append("title") }
        if before.nextDueDate != after.nextDueDate { fields.append("due date") }
        if before.frequency != after.frequency { fields.append("schedule") }
        if before.amount != after.amount { fields.append("amount") }
        if before.notes != after.notes { fields.append("notes") }
        return fields
    }

    /// "due today at 5:00 PM", "due tomorrow", "due Fri, Oct 16" or "overdue since Oct 10".
    static func dueText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let hasTime = calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0
        let time = hasTime ? " at \(date.formatted(date: .omitted, time: .shortened))" : ""
        if calendar.isDate(date, inSameDayAs: now) {
            return date < now && hasTime ? "overdue since \(date.formatted(date: .omitted, time: .shortened))" : "due today\(time)"
        }
        if date < now {
            return "overdue since \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "due tomorrow\(time)"
        }
        return "due \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }
}

/// A change this person made on this device, for sending alerts about it. Changes that
/// arrive from the family are applied without one.
enum LocalItemChange {
    case task(before: FamilyTask?, after: FamilyTask)
    case recurring(before: RecurringTask?, after: RecurringTask, completedOccurrence: Bool)
}

extension Notification.Name {
    /// userInfo["change"] holds the LocalItemChange.
    static let familyItemChangedLocally = Notification.Name("FamilyItemChangedLocally")
}

extension LocalItemChange {
    @MainActor
    func post() {
        NotificationCenter.default.post(name: .familyItemChangedLocally, object: nil, userInfo: ["change": self])
    }
}

/// The open tasks on one person's list for a morning or evening reminder.
struct DailyTaskList: Equatable {
    struct Entry: Equatable {
        var title: String
        /// "overdue", "5:00 PM", "repeats" or nil when it has no date.
        var detail: String?
    }

    var entries: [Entry]

    /// Open tasks for `viewer` that are due by the end of `day` (including overdue ones),
    /// recurring tasks due by then, and tasks with no date. Overdue first, then by time.
    static func make(
        on day: Date,
        tasks: [FamilyTask],
        recurringTasks: [RecurringTask],
        viewer: String,
        calendar: Calendar = .current
    ) -> DailyTaskList {
        let startOfDay = calendar.startOfDay(for: day)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return DailyTaskList(entries: []) }

        let mine = tasks.filter { !$0.isDone && $0.isAssigned(to: viewer) }
        let dated = mine
            .compactMap { task in task.dueDate.map { (task, $0) } }
            .filter { $0.1 < endOfDay }
        let recurring = recurringTasks
            .filter { $0.isActive && $0.isAssigned(to: viewer) && $0.nextDueDate < endOfDay }
            .map { ($0, $0.nextDueDate) }

        struct Dated { var title: String; var date: Date; var isRecurring: Bool }
        let datedEntries = (dated.map { Dated(title: $0.0.title, date: $0.1, isRecurring: false) } +
            recurring.map { Dated(title: $0.0.title, date: $0.1, isRecurring: true) })
            .sorted { $0.date < $1.date }
            .map { item -> Entry in
                if item.date < startOfDay { return Entry(title: item.title, detail: "overdue") }
                if item.isRecurring { return Entry(title: item.title, detail: "repeats") }
                let hasTime = calendar.component(.hour, from: item.date) != 0 || calendar.component(.minute, from: item.date) != 0
                return Entry(title: item.title, detail: hasTime ? item.date.formatted(date: .omitted, time: .shortened) : nil)
            }
        let undated = mine
            .filter { $0.dueDate == nil }
            .sorted { $0.createdAt < $1.createdAt }
            .map { Entry(title: $0.title, detail: nil) }

        return DailyTaskList(entries: datedEntries + undated)
    }

    static let maxLines = 6

    /// One line per task, "• Take out bins — overdue", then "+3 more".
    var body: String {
        var lines = entries.prefix(Self.maxLines).map { entry in
            entry.detail.map { "• \(entry.title) — \($0)" } ?? "• \(entry.title)"
        }
        if entries.count > Self.maxLines {
            lines.append("+\(entries.count - Self.maxLines) more")
        }
        return lines.joined(separator: "\n")
    }
}
