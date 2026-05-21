import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.showTaskTime") private var showTaskTime = false
    @AppStorage("schedule.showTaskBucket") private var showTaskBucket = false
    @AppStorage("schedule.defaultDisplayMode") private var defaultDisplayModeRaw = ScheduleDisplayMode.week.rawValue
    @State private var isAddingTask = false
    @State private var editingTask: FamilyTask?
    @State private var selectedDate = Date()
    @State private var displayMode: ScheduleDisplayMode = .week

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scheduleControls
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                List {
                    let selectedTasks = taskStore.tasksScheduled(on: selectedDate)
                    let recurringTasks = organizerStore.recurringTasks(on: selectedDate)
                    let pendingTasks = pendingTasksForCurrentView
                    let calendarEvents = calendarSync.dayEvents

                    switch displayMode {
                    case .today:
                        dayContent(selectedTasks: selectedTasks, recurringTasks: recurringTasks, calendarEvents: calendarEvents, pendingTasks: pendingTasks)

                    case .week:
                        Section {
                            WeekStripView(selectedDate: $selectedDate) { day in
                                taskStore.tasksScheduled(on: day)
                            } recurringForDay: { day in
                                organizerStore.recurringTasks(on: day)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)

                        dayContent(selectedTasks: selectedTasks, recurringTasks: recurringTasks, calendarEvents: calendarEvents, pendingTasks: pendingTasks)

                    case .month:
                        Section {
                            MonthGridView(selectedDate: $selectedDate) { day in
                                taskStore.tasksScheduled(on: day)
                            } recurringForDay: { day in
                                organizerStore.recurringTasks(on: day)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)

                        dayContent(selectedTasks: selectedTasks, recurringTasks: recurringTasks, calendarEvents: calendarEvents, pendingTasks: pendingTasks)
                    }

                    if let message = calendarSync.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .contentMargins(.top, 0, for: .scrollContent)
                .refreshable {
                    guard calendarIntegrationEnabled else { return }
                    await calendarSync.loadEvents(on: selectedDate)
                }
                .scrollContentBackground(.hidden)
                .simultaneousGesture(scheduleSwipeGesture)
            }
            .background(AppTheme.background)
            .navigationTitle("Schedule")
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
            .task {
                displayMode = ScheduleDisplayMode(rawValue: defaultDisplayModeRaw) ?? .week

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
            .sheet(isPresented: $isAddingTask) {
                AddTaskView()
            }
            .onChange(of: defaultDisplayModeRaw) { _, rawValue in
                displayMode = ScheduleDisplayMode(rawValue: rawValue) ?? .week
            }
        }
    }

    private var scheduleSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard displayMode == .week else { return }
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 48 else { return }
                selectedDate = calendar.date(
                    byAdding: .weekOfYear,
                    value: value.translation.width > 0 ? 1 : -1,
                    to: selectedDate
                ) ?? selectedDate
            }
    }

    private var scheduleControls: some View {
        VStack(spacing: 10) {
            Picker("Schedule View", selection: $displayMode) {
                ForEach(ScheduleDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch displayMode {
            case .month:
                monthNavigator
            case .today:
                dayNavigator
            case .week:
                weekNavigator
            }
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.primary)
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Label(previousMonthText, systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                HStack(spacing: 4) {
                    Text(nextMonthText)
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.primary)
        .padding(.horizontal, 2)
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(weekTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.primary)
    }

    private var previousMonthText: String {
        let date = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        return date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    private var nextMonthText: String {
        let date = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        return date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    private var weekTitle: String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return selectedDate.formatted(.dateTime.month(.abbreviated).day().year())
        }

        let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var monthTaskSections: [(date: Date, tasks: [FamilyTask])] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
        let pendingIDs = Set(taskStore.pendingTasks(before: Date()).map(\.id))

        let grouped = Dictionary(grouping: taskStore.tasks) { task -> Date? in
            guard !pendingIDs.contains(task.id) else { return nil }
            guard let dueDate = task.dueDate, monthInterval.contains(dueDate) else { return nil }
            return calendar.startOfDay(for: dueDate)
        }

        return grouped.compactMap { date, tasks -> (date: Date, tasks: [FamilyTask])? in
            guard let date else { return nil }
            return (date, tasks.sorted { lhs, rhs in
                (lhs.dueDate ?? lhs.updatedAt) < (rhs.dueDate ?? rhs.updatedAt)
            })
        }
        .sorted { $0.date < $1.date }
    }

    private var pendingTasksForCurrentView: [FamilyTask] {
        let pending = taskStore.pendingTasks(before: Date())
        let today = calendar.startOfDay(for: Date())
        let selectedDay = calendar.startOfDay(for: selectedDate)
        return selectedDay == today ? pending : []
    }

    @ViewBuilder
    private func dayContent(selectedTasks: [FamilyTask], recurringTasks: [RecurringTask], calendarEvents: [CalendarDayEvent], pendingTasks: [FamilyTask]) -> some View {
        if selectedTasks.isEmpty && recurringTasks.isEmpty && calendarEvents.isEmpty && pendingTasks.isEmpty {
            ContentUnavailableView("Nothing Scheduled", systemImage: "calendar.badge.checkmark")
                .listRowBackground(Color.clear)
        }

        if !selectedTasks.isEmpty {
            Section {
                ForEach(selectedTasks) { task in
                    taskRow(task)
                }
            } header: {
                ScheduleDateHeader(date: selectedDate)
            }
        }

        if !recurringTasks.isEmpty {
            Section("Recurring") {
                ForEach(recurringTasks) { task in
                    RecurringScheduleRow(task: task) {
                        organizerStore.markRecurringDone(task)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            organizerStore.deleteRecurringTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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

private enum ScheduleDisplayMode: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

private struct ScheduleDateHeader: View {
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primary)

            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
        }
        .textCase(nil)
    }
}

private struct WeekStripView: View {
    @Binding var selectedDate: Date
    let tasksForDay: (Date) -> [FamilyTask]
    let recurringForDay: (Date) -> [RecurringTask]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(weekDays, id: \.self) { day in
                    dayButton(day)
                }
            }

            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private var weekDays: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }

        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let tasks = tasksForDay(day)
        let recurringTasks = recurringForDay(day)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2)
                    .foregroundStyle(isSelected ? AppTheme.primary : .secondary)

                Text(day.formatted(.dateTime.day()))
                    .font(.headline.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? AppTheme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 9))

                ScheduleDots(tasks: tasks, recurringTasks: recurringTasks)
                    .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct MonthGridView: View {
    @Binding var selectedDate: Date
    let tasksForDay: (Date) -> [FamilyTask]
    let recurringForDay: (Date) -> [RecurringTask]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }

            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayButton(day)
                } else {
                    Color.clear
                        .frame(height: 56)
                }
            }
        }
        .padding(.vertical, 2)
        .background(AppTheme.surface)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols.map { String($0.prefix(3)).uppercased() }
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var monthDays: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: selectedDate),
            let dayRange = calendar.range(of: .day, in: .month, for: selectedDate)
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
        let tasks = tasksForDay(day)
        let recurringTasks = recurringForDay(day)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? AppTheme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if isToday && !isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1)
                        }
                    }

                ScheduleDots(tasks: tasks, recurringTasks: recurringTasks)
                    .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.plain)
    }
}

private struct ScheduleDots: View {
    let tasks: [FamilyTask]
    let recurringTasks: [RecurringTask]

    var body: some View {
        HStack(spacing: 3) {
            let colors = dotColors
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var dotColors: [Color] {
        var colors = tasks.prefix(3).map { $0.bucket.scheduleColor }
        let remaining = max(0, 3 - colors.count)
        colors.append(contentsOf: recurringTasks.prefix(remaining).map { _ in AppTheme.primary })
        return colors
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

private struct RecurringScheduleRow: View {
    let task: RecurringTask
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AssigneeAvatarView(name: task.assignedTo)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.footnote)
                        .lineLimit(2)

                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(AppTheme.primary)

                    if !task.amount.isEmpty {
                        Text(task.amount)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(task.frequency.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onDone) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark recurring task done")
        }
        .padding(.vertical, 6)
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
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}

private extension TaskBucket {
    var scheduleColor: Color {
        switch self {
        case .doNow:
            AppTheme.taskDo
        case .schedule:
            AppTheme.taskSchedule
        case .delegate:
            AppTheme.taskDelegate
        case .delete:
            AppTheme.taskDrop
        }
    }
}
