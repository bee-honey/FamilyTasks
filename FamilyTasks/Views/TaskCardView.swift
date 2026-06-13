import SwiftUI

struct TaskCardView: View {
    let task: FamilyTask
    let buckets: [TaskBucket]
    let isSyncing: Bool
    let onMove: (TaskBucket) -> Void
    let onDone: () -> Void
    let onDelete: () -> Void
    let onSync: () -> Void
    @AppStorage("tasks.showBucketColors") private var showTaskBucketColors = true
    @AppStorage("tasks.showPriorityMarkers") private var showTaskPriorityMarkers = true

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            VStack(spacing: 5) {
                Button(action: onDone) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.isDone ? AppTheme.success : .secondary)
                .frame(width: 24, height: 24)

                AssigneeAvatarView(name: task.assignedTo)
                    .scaleEffect(0.68)
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 5) {
                        Text(task.title)
                            .font(.caption.weight(.semibold))
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.82)

                        if showTaskPriorityMarkers {
                            TaskPriorityMarkerGroup(task: task)
                        }
                    }

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                HStack(spacing: 9) {
                    Button(action: onSync) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: task.calendarEventIdentifier == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Sync to calendar")

                    Menu {
                        ForEach(buckets) { bucket in
                            Button(bucket.title) { onMove(bucket) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.caption)
                    .help("Move task")

                    Spacer()

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Delete task")
                }
            }
        }
        .padding(8)
        .background(showTaskBucketColors ? task.bucket.taskBackgroundColor : AppTheme.surfaceMuted)
        .overlay(alignment: .leading) {
            if showTaskBucketColors {
                Rectangle()
                    .fill(task.bucket.accentColor.opacity(0.55))
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
