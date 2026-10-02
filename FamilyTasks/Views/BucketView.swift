import SwiftUI

/// Every task in one quadrant of the matrix, open ones first.
struct BucketDetailView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    let bucket: TaskBucket
    @State private var syncingTaskID: FamilyTask.ID?
    @State private var editingTask: FamilyTask?

    var body: some View {
        let tasks = taskStore.tasks(in: bucket)
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone)

        List {
            if tasks.isEmpty {
                Label("No tasks here", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppTheme.surface)
            }
            if !open.isEmpty {
                Section {
                    rows(open)
                } header: {
                    SectionTitle(text: "Open · \(open.count)")
                }
            }
            if !done.isEmpty {
                Section {
                    rows(done)
                } header: {
                    SectionTitle(text: "Done · \(done.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(bucket.tagTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTask) { task in
            EditTaskView(task: task)
        }
    }

    private func rows(_ tasks: [FamilyTask]) -> some View {
        ForEach(tasks) { task in
            MatrixTaskRowView(
                task: task,
                buckets: TaskBucket.allCases.filter { $0 != bucket },
                isSyncing: syncingTaskID == task.id,
                onMove: { target in taskStore.move(task, to: target) },
                onDone: { taskStore.markDone(task) },
                onDelete: { taskStore.delete(task) },
                onSync: { syncToCalendar(task) },
                onEdit: { editingTask = task }
            )
            .listRowBackground(AppTheme.surface)
        }
    }

    private func syncToCalendar(_ task: FamilyTask) {
        syncingTaskID = task.id
        Task {
            do {
                try await calendarSync.sync(task)
            } catch {
                calendarSync.lastErrorMessage = error.localizedDescription
            }
            syncingTaskID = nil
        }
    }
}

private struct MatrixTaskRowView: View {
    let task: FamilyTask
    let buckets: [TaskBucket]
    let isSyncing: Bool
    let onMove: (TaskBucket) -> Void
    let onDone: () -> Void
    let onDelete: () -> Void
    let onSync: () -> Void
    let onEdit: () -> Void
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("tasks.showPriorityMarkers") private var showTaskPriorityMarkers = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Group {
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(AppTheme.onAvatar)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.success, in: Circle())
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone)
                    .lineLimit(2)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showTaskPriorityMarkers {
                    TaskPriorityMarkerGroup(task: task)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(dateText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            AssigneeAvatarView(name: task.primaryAssigneeForAvatar, size: 28, showsPhoto: false)

            Menu {
                Button {
                    onSync()
                } label: {
                    Label(calendarSync.hasCalendarEvent(for: task) ? "Update Calendar" : "Sync to Calendar", systemImage: "calendar.badge.plus")
                }

                Menu("Move To") {
                    ForEach(buckets) { bucket in
                        Button(bucket.title) { onMove(bucket) }
                    }
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onEdit()
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                onSync()
            } label: {
                Label(calendarSync.hasCalendarEvent(for: task) ? "Update Calendar" : "Sync to Calendar", systemImage: "calendar.badge.plus")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var dateText: String {
        guard let dueDate = task.dueDate else { return "No date" }

        if Calendar.current.isDateInToday(dueDate) {
            return dueDate.formatted(date: .omitted, time: .shortened)
        }

        return dueDate.formatted(.dateTime.month(.abbreviated).day())
    }
}
