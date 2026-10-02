import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @State private var isAddingTask = false
    @State private var analyticsRange: TaskAnalyticsRange = .week

    var body: some View {
        let summary = TaskAnalyticsSummary(
            tasks: taskStore.visibleTasks,
            familyMembers: taskStore.familyMembers,
            range: analyticsRange
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(TaskBucket.allCases) { bucket in
                            NavigationLink {
                                BucketDetailView(bucket: bucket)
                            } label: {
                                QuadrantCard(bucket: bucket, openTasks: taskStore.tasks(in: bucket).filter { !$0.isDone })
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        StatTile(value: "\(summary.completedInRange)", label: "done \(analyticsRange.title.lowercased())")
                        StatTile(value: summary.onTimePercent.map { "\($0)%" } ?? "–", label: "on time")
                        StatTile(value: "\(summary.overdueTasks)", label: "overdue", isWarning: summary.overdueTasks > 0)
                    }

                    if !summary.people.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(text: "Who's done what")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(summary.people) { person in
                                        PersonRing(person: person)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background)
            .navigationTitle("Tasks")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isAddingTask) {
                AddTaskView()
            }
        }
    }

    /// "THIS WEEK ▾ / Tasks" with the add button; the caption picks the stats period.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Menu {
                    Picker("Period", selection: $analyticsRange) {
                        ForEach(TaskAnalyticsRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(analyticsRange.title.uppercased())
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.primary)
                }
                .accessibilityLabel("Stats period, \(analyticsRange.title)")
                Text("Tasks")
                    .font(.title.weight(.bold))
            }
            Spacer()
            Button {
                isAddingTask = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.onPrimary)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task")
        }
    }
}

/// One quadrant: its open-task count and the first few tasks.
private struct QuadrantCard: View {
    let bucket: TaskBucket
    let openTasks: [FamilyTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.tagTitle)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(openTasks.count)")
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(bucket.accentColor)

            if openTasks.isEmpty {
                Text("All clear")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openTasks.prefix(3)) { task in
                    Text(task.title)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                }
                if openTasks.count > 3 {
                    Text("+\(openTasks.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(bucket.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows all \(bucket.tagTitle) tasks")
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var isWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(isWarning ? AppTheme.overdue : AppTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A family member's initials inside a ring showing how much of their share is done.
private struct PersonRing: View {
    let person: PersonTaskPerformance

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceMuted, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: Double(person.completionPercent) / 100)
                    .stroke(AppTheme.success, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                AssigneeAvatarView(name: person.assignee, size: 40, showsPhoto: false)
            }
            .frame(width: 54, height: 54)

            Text(person.shortName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(person.completedTasks) of \(person.totalTasks)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.shortName): \(person.completedTasks) of \(person.totalTasks) done")
    }
}

private struct TaskAnalyticsSummary {
    let range: TaskAnalyticsRange
    let totalTasks: Int
    let completedTasks: Int
    let openTasks: Int
    let overdueTasks: Int
    let completedInRange: Int
    /// Of the tasks finished in the period that had a due date; nil when there were none.
    let onTimePercent: Int?
    let completionPercent: Int
    let people: [PersonTaskPerformance]

    init(tasks: [FamilyTask], familyMembers: [String], range: TaskAnalyticsRange, now: Date = Date(), calendar: Calendar = .current) {
        self.range = range
        totalTasks = tasks.count
        completedTasks = tasks.filter(\.isDone).count
        openTasks = tasks.filter { !$0.isDone }.count
        overdueTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return !task.isDone && dueDate < now
        }.count
        completionPercent = Self.percent(completedTasks, of: totalTasks)

        let startDate = range.startDate(from: now, calendar: calendar)
        let rangeTasks = tasks.filter { $0.createdAt >= startDate || $0.updatedAt >= startDate }
        let finishedInRange = tasks.filter { task in
            task.isDone && (task.completedAt ?? task.updatedAt) >= startDate
        }
        completedInRange = finishedInRange.count

        // On time: finished no later than the end of the day it was due.
        let dated = finishedInRange.filter { $0.dueDate != nil && $0.completedAt != nil }
        let onTime = dated.filter { task in
            guard let due = task.dueDate, let finished = task.completedAt,
                  let endOfDueDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due)) else { return false }
            return finished < endOfDueDay
        }
        onTimePercent = dated.isEmpty ? nil : Self.percent(onTime.count, of: dated.count)

        // People only: "Everyone" and unassigned tasks have no one to credit.
        let assignees = Self.assignees(from: tasks, familyMembers: familyMembers)
            .filter { !Assignee.isEveryone($0) && $0 != PersonTaskPerformance.unassigned }
        people = assignees.compactMap { assignee in
            let assignedTasks = rangeTasks.filter { Self.matchesAssignee($0, assignee: assignee) }
            guard !assignedTasks.isEmpty else { return nil }

            let completed = assignedTasks.filter(\.isDone).count
            return PersonTaskPerformance(
                assignee: assignee,
                totalTasks: assignedTasks.count,
                completedTasks: completed,
                completionPercent: Self.percent(completed, of: assignedTasks.count)
            )
        }
        .sorted { lhs, rhs in
            if lhs.completionPercent == rhs.completionPercent {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.completionPercent > rhs.completionPercent
        }
    }

    private static func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }

    private static func assignees(from tasks: [FamilyTask], familyMembers: [String]) -> [String] {
        let taskAssignees = tasks.flatMap(Self.analyticsAssignees)
        let combined = familyMembers + taskAssignees
        let normalized = combined
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.isEmpty ? PersonTaskPerformance.unassigned : $0 }

        return Array(Set(normalized))
            .sorted { lhs, rhs in
                PersonTaskPerformance.displayName(for: lhs).localizedCaseInsensitiveCompare(PersonTaskPerformance.displayName(for: rhs)) == .orderedAscending
            }
    }

    private static func analyticsAssignees(for task: FamilyTask) -> [String] {
        if task.isAssignedToEveryone {
            return [Assignee.everyone]
        }
        let emails = task.assigneeEmails
        return emails.isEmpty ? [PersonTaskPerformance.unassigned] : emails
    }

    private static func matchesAssignee(_ task: FamilyTask, assignee: String) -> Bool {
        analyticsAssignees(for: task).contains { $0.caseInsensitiveCompare(assignee) == .orderedSame }
    }
}

private struct PersonTaskPerformance: Identifiable {
    static let unassigned = "__familytasks_unassigned__"

    let assignee: String
    let totalTasks: Int
    let completedTasks: Int
    let completionPercent: Int

    var id: String { assignee.lowercased() }

    var displayName: String {
        Self.displayName(for: assignee)
    }

    static func displayName(for assignee: String) -> String {
        if assignee == unassigned {
            return "Unassigned"
        }
        return Assignee.displayName(for: assignee)
    }

    /// "You" or a first name, for the small label under the ring.
    var shortName: String {
        let me = (UserDefaults.standard.string(forKey: "profile.email") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if assignee.caseInsensitiveCompare(me) == .orderedSame { return "You" }
        let name = Assignee.memberName(for: assignee)
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}

private enum TaskAnalyticsRange: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "This Week"
        case .month: "This Month"
        case .year: "This Year"
        }
    }

    var shortTitle: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var noun: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    func startDate(from date: Date, calendar: Calendar) -> Date {
        switch self {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }
}
