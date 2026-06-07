import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @State private var isAddingTask = false
    @State private var syncingTaskID: FamilyTask.ID?
    @State private var editingTask: FamilyTask?
    @State private var analyticsRange: TaskAnalyticsRange = .week

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    TaskAnalyticsDashboard(
                        summary: TaskAnalyticsSummary(
                            tasks: taskStore.tasks,
                            familyMembers: taskStore.familyMembers,
                            range: analyticsRange
                        ),
                        selectedRange: $analyticsRange
                    )

                    ForEach(TaskBucket.allCases) { bucket in
                        BucketView(
                            bucket: bucket,
                            tasks: taskStore.tasks(in: bucket),
                            syncingTaskID: syncingTaskID,
                            onMove: { task, target in taskStore.move(task, to: target) },
                            onDone: taskStore.markDone,
                            onDelete: taskStore.delete,
                            onSync: syncToCalendar,
                            onEdit: { editingTask = $0 }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 76)
            }
            .background(AppTheme.background)
            .navigationTitle("Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $isAddingTask) {
                AddTaskView()
            }
            .sheet(item: $editingTask) { task in
                EditTaskView(task: task)
            }
            .alert("Calendar Sync", isPresented: Binding(
                get: { calendarSync.lastErrorMessage != nil },
                set: { if !$0 { calendarSync.lastErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(calendarSync.lastErrorMessage ?? "")
            }
        }
    }

    private func syncToCalendar(_ task: FamilyTask) {
        syncingTaskID = task.id
        Task {
            do {
                let identifier = try await calendarSync.sync(task)
                taskStore.setCalendarEventIdentifier(identifier, for: task)
            } catch {
                calendarSync.lastErrorMessage = error.localizedDescription
            }
            syncingTaskID = nil
        }
    }
}

private struct TaskAnalyticsDashboard: View {
    let summary: TaskAnalyticsSummary
    @Binding var selectedRange: TaskAnalyticsRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Family Performance")
                        .font(.headline)
                    Text(summary.range.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(TaskAnalyticsRange.allCases) { range in
                        Text(range.shortTitle).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                AnalyticsMetricView(title: "Total Tasks", value: "\(summary.totalTasks)", detail: "\(summary.completedTasks) done")
                AnalyticsMetricView(title: "Left", value: "\(summary.openTasks)", detail: "\(summary.overdueTasks) overdue")
                AnalyticsMetricView(title: "Completed", value: "\(summary.completionPercent)%", detail: "All-time")
                AnalyticsMetricView(title: "This \(summary.range.noun)", value: "\(summary.completedInRange)", detail: "completed")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("By Person")
                    .font(.subheadline.weight(.semibold))

                if summary.people.isEmpty {
                    Text("Assign tasks to family members to see individual performance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.people) { person in
                        PersonPerformanceRow(person: person)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AnalyticsMetricView: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surfaceMuted.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PersonPerformanceRow: View {
    let person: PersonTaskPerformance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AssigneeAvatarView(name: person.assignee)
                    .scaleEffect(0.68)
                    .frame(width: 28, height: 28)

                Text(person.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(person.completionPercent)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            ProgressView(value: Double(person.completedTasks), total: Double(max(person.totalTasks, 1)))
                .tint(AppTheme.primary)

            Text("\(person.completedTasks) of \(person.totalTasks) completed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct TaskAnalyticsSummary {
    let range: TaskAnalyticsRange
    let totalTasks: Int
    let completedTasks: Int
    let openTasks: Int
    let overdueTasks: Int
    let completedInRange: Int
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
        completedInRange = rangeTasks.filter { $0.isDone && $0.updatedAt >= startDate }.count

        let assignees = Self.assignees(from: tasks, familyMembers: familyMembers)
        people = assignees.compactMap { assignee in
            let assignedTasks = rangeTasks.filter { Self.matchesAssignee($0.assignedTo, assignee: assignee) }
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
        let taskAssignees = tasks.map(\.assignedTo)
        let combined = familyMembers + taskAssignees
        let normalized = combined
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.isEmpty ? PersonTaskPerformance.unassigned : $0 }

        return Array(Set(normalized))
            .sorted { lhs, rhs in
                PersonTaskPerformance.displayName(for: lhs).localizedCaseInsensitiveCompare(PersonTaskPerformance.displayName(for: rhs)) == .orderedAscending
            }
    }

    private static func matchesAssignee(_ value: String, assignee: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = normalized.isEmpty ? PersonTaskPerformance.unassigned : normalized
        return candidate.caseInsensitiveCompare(assignee) == .orderedSame
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
