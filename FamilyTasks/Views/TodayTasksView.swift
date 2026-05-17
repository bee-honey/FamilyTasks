import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @State private var editingTask: FamilyTask?
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            List {
                let selectedTasks = taskStore.tasksScheduled(on: selectedDate)
                let pendingTasks = taskStore.pendingTasks(before: selectedDate)
                let calendarEvents = calendarSync.dayEvents

                Section {
                    dateNavigator
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                .listRowBackground(Color.clear)

                if selectedTasks.isEmpty && calendarEvents.isEmpty && pendingTasks.isEmpty {
                    ContentUnavailableView("Nothing Scheduled", systemImage: "calendar.badge.checkmark")
                        .listRowBackground(Color.clear)
                }

                if !selectedTasks.isEmpty {
                    Section {
                        ForEach(selectedTasks) { task in
                            taskRow(task)
                        }
                    } header: {
                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                    }
                }

                if !calendarEvents.isEmpty {
                    Section("Calendar") {
                        ForEach(calendarEvents) { event in
                            CalendarEventRow(event: event)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        calendarSync.removeTodayEvent(event)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                if !pendingTasks.isEmpty {
                    Section("Pending") {
                        ForEach(pendingTasks) { task in
                            taskRow(task)
                        }
                    }
                }

                if let message = calendarSync.lastErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.destructive)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                guard calendarIntegrationEnabled else { return }
                await calendarSync.loadEvents(on: selectedDate)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if calendarIntegrationEnabled {
                    await calendarSync.loadEvents(on: selectedDate)
                } else {
                    calendarSync.clearTodayEvents()
                }
            }
            .onChange(of: calendarIntegrationEnabled) { _, enabled in
                Task {
                    if enabled {
                        await calendarSync.loadEvents(on: selectedDate)
                    } else {
                        calendarSync.clearTodayEvents()
                    }
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                Task {
                    if calendarIntegrationEnabled {
                        await calendarSync.loadEvents(on: newDate)
                    } else {
                        calendarSync.clearTodayEvents()
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                EditTaskView(task: task)
            }
        }
    }

    private var dateNavigator: some View {
        HStack(spacing: 10) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func taskRow(_ task: FamilyTask) -> some View {
        TodayTaskRow(task: task) {
            taskStore.markDone(task)
        } onEdit: {
            editingTask = task
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                taskStore.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct CalendarEventRow: View {
    let event: CalendarDayEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.isAllDay ? "calendar" : "clock")
                .font(.title3)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(timeText)
                    Text(event.calendarTitle)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
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
                        .font(.footnote)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)

                    if task.isUrgent {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                }

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    }

                    Text(task.bucket.title)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDone) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? AppTheme.success : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}
