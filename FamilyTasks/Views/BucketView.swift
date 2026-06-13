import SwiftUI

struct BucketView: View {
    let bucket: TaskBucket
    let tasks: [FamilyTask]
    let syncingTaskID: FamilyTask.ID?
    let onMove: (FamilyTask, TaskBucket) -> Void
    let onDone: (FamilyTask) -> Void
    let onDelete: (FamilyTask) -> Void
    let onSync: (FamilyTask) -> Void
    let onEdit: (FamilyTask) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                SectionHeaderView(bucket: bucket, taskCount: tasks.count, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.leading, 12)

                if tasks.isEmpty {
                    EmptyBucketView()
                        .padding(10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tasks) { task in
                            MatrixTaskRowView(
                                task: task,
                                buckets: TaskBucket.allCases.filter { $0 != bucket },
                                isSyncing: syncingTaskID == task.id,
                                onMove: { target in onMove(task, target) },
                                onDone: { onDone(task) },
                                onDelete: { onDelete(task) },
                                onSync: { onSync(task) },
                                onEdit: { onEdit(task) }
                            )

                            if task.id != tasks.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SectionHeaderView: View {
    let bucket: TaskBucket
    let taskCount: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(bucket.accentColor)
                .frame(width: 4, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(bucket.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(taskCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(bucket.accentColor)
                .frame(minWidth: 26, minHeight: 26)
                .background(bucket.accentColor.opacity(0.12), in: Circle())

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .padding(12)
        .contentShape(Rectangle())
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
    @AppStorage("tasks.showBucketColors") private var showTaskBucketColors = false
    @AppStorage("tasks.showPriorityMarkers") private var showTaskPriorityMarkers = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDone) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? AppTheme.success : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.footnote)
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
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(width: 58, alignment: .trailing)

            AssigneeAvatarView(name: task.assignedTo)
                .scaleEffect(0.76)
                .frame(width: 32, height: 32)

            Menu {
                Button {
                    onSync()
                } label: {
                    Label(task.calendarEventIdentifier == nil ? "Sync to Calendar" : "Update Calendar", systemImage: "calendar.badge.plus")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(showTaskBucketColors ? task.bucket.taskBackgroundColor : Color.clear)
        .overlay(alignment: .leading) {
            if showTaskBucketColors {
                Rectangle()
                    .fill(task.bucket.accentColor.opacity(0.45))
                    .frame(width: 3)
            }
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
                Label(task.calendarEventIdentifier == nil ? "Sync to Calendar" : "Update Calendar", systemImage: "calendar.badge.plus")
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

private struct EmptyBucketView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.callout)
            Text("No tasks here")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
