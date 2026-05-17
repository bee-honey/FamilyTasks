import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.showTaskTime") private var showTaskTime = false
    @AppStorage("schedule.showTaskBucket") private var showTaskBucket = false
    @State private var editingTask: FamilyTask?
    @State private var selectedDate = Date()
    @State private var isChoosingDate = false

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
                    Section("Tasks") {
                        ForEach(selectedTasks) { task in
                            taskRow(task)
                        }
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
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isChoosingDate = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Choose date")
                }
            }
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
            .sheet(isPresented: $isChoosingDate) {
                ScheduleDatePickerView(selectedDate: $selectedDate) { day in
                    !taskStore.tasksScheduled(on: day).isEmpty
                }
                .presentationDetents([.medium])
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

            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func taskRow(_ task: FamilyTask) -> some View {
        TodayTaskRow(task: task, showTime: showTaskTime, showBucket: showTaskBucket) {
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

private struct ScheduleDatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    @State private var visibleMonth: Date

    let hasTasks: (Date) -> Bool
    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>, hasTasks: @escaping (Date) -> Bool) {
        _selectedDate = selectedDate
        _visibleMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start ?? selectedDate.wrappedValue)
        self.hasTasks = hasTasks
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                monthHeader

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayButton(day)
                        } else {
                            Color.clear
                                .frame(height: 38)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.background)
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)

            Spacer()

            Button {
                visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var monthDays: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }

        return Array(repeating: nil, count: leadingBlanks) + days
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selectedDate = day
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Circle()
                    .fill(hasTasks(day) ? (isSelected ? Color.white : AppTheme.primary) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(isSelected ? AppTheme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
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
    let showTime: Bool
    let showBucket: Bool
    let onDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AssigneeAvatarView(name: task.assignedTo)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.footnote)
                        .lineLimit(2)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)

                    if task.isUrgent {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                }

                if showTime || showBucket {
                    HStack(spacing: 8) {
                        if showTime, let dueDate = task.dueDate {
                            Label(dueDate.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        }

                        if showBucket {
                            Text(task.bucket.title)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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
