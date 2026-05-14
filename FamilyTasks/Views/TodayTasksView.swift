import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @State private var editingTask: FamilyTask?

    var body: some View {
        NavigationStack {
            List {
                let todayTasks = taskStore.tasksScheduledToday()

                if todayTasks.isEmpty {
                    ContentUnavailableView("Nothing Scheduled Today", systemImage: "calendar.badge.checkmark")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(todayTasks) { task in
                            TodayTaskRow(task: task) {
                                taskStore.markDone(task)
                            } onEdit: {
                                editingTask = task
                            }
                        }
                    } header: {
                        Text(Date().formatted(date: .complete, time: .omitted))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTask) { task in
                EditTaskView(task: task)
            }
        }
    }
}

private struct TodayTaskRow: View {
    let task: FamilyTask
    let onDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AssigneeAvatarView(name: task.assignedTo)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)

                    if task.isUrgent {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    }

                    Text(task.bucket.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDone) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}
