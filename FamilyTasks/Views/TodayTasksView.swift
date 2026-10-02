import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.showTaskTime") private var showTaskTime = true
    @AppStorage("schedule.showPriorityTags") private var showPriorityTags = true
    @AppStorage("schedule.defaultDisplayMode") private var defaultDisplayModeRaw = ScheduleDisplayMode.week.rawValue
    @AppStorage("schedule.contentPriority") private var contentPriorityRaw = ScheduleContentPriority.tasksFirst.rawValue
    @AppStorage("schedule.taskSortOrder") private var taskSortOrderRaw = ScheduleTaskSortOrder.priority.rawValue
    @State private var isAddingTask = false
    @State private var editingTask: FamilyTask?
    @State private var selectedDate = Date()
    @State private var displayMode: ScheduleDisplayMode = .week

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TodayHeader {
                        isAddingTask = true
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)

                Section {
                    VStack(spacing: 14) {
                        periodControls

                        switch displayMode {
                        case .week:
                            WeekStripView(selectedDate: $selectedDate) { day in
                                dayMarker(for: day)
                            }
                        case .month:
                            MonthGridView(selectedDate: $selectedDate) { day in
                                dayMarker(for: day)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                dayContent(
                    selectedTasks: sortedTasks(taskStore.tasksScheduled(on: selectedDate)),
                    recurringTasks: organizerStore.recurringTasks(on: selectedDate),
                    calendarEvents: calendarSync.dayEvents,
                    overdueTasks: overdueTasksForSelectedDay
                )

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
            .background(AppTheme.background)
            .navigationTitle("Today")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if ScheduleDisplayMode(rawValue: defaultDisplayModeRaw) == nil {
                    // Earlier versions also had a "today" view; it is now the week view.
                    defaultDisplayModeRaw = ScheduleDisplayMode.week.rawValue
                }
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

    /// `‹ Sep 27 – Oct 3 ›` (or the month) with the Week/Month switch. Tapping the title
    /// goes back to today.
    private var periodControls: some View {
        HStack(spacing: 6) {
            periodArrow("chevron.left", label: displayMode == .week ? "Previous week" : "Previous month", step: -1)

            Button {
                selectedDate = Date()
            } label: {
                Text(periodTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes back to today")

            periodArrow("chevron.right", label: displayMode == .week ? "Next week" : "Next month", step: 1)

            Spacer(minLength: 8)

            Picker("View", selection: $displayMode) {
                ForEach(ScheduleDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, 16)
    }

    private func periodArrow(_ systemImage: String, label: String, step: Int) -> some View {
        Button {
            let component: Calendar.Component = displayMode == .week ? .weekOfYear : .month
            selectedDate = calendar.date(byAdding: component, value: step, to: selectedDate) ?? selectedDate
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 32, height: 32)
                .background(AppTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var periodTitle: String {
        switch displayMode {
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                return selectedDate.formatted(.dateTime.month(.abbreviated).day())
            }
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// The dot under a day: red when it still has overdue tasks, a quiet dot when it has anything planned.
    private func dayMarker(for day: Date) -> DayMarker {
        let tasks = taskStore.tasksScheduled(on: day)
        let isPast = day < calendar.startOfDay(for: Date())
        if isPast && tasks.contains(where: { !$0.isDone }) {
            return .overdue
        }
        if !tasks.isEmpty || !organizerStore.recurringTasks(on: day).isEmpty {
            return .planned
        }
        return .none
    }

    /// Overdue tasks are shown with today, the day they need doing.
    private var overdueTasksForSelectedDay: [FamilyTask] {
        guard calendar.isDateInToday(selectedDate) else { return [] }
        return sortedTasks(taskStore.pendingTasks(before: Date()))
    }

    @ViewBuilder
    private func dayContent(selectedTasks: [FamilyTask], recurringTasks: [RecurringTask], calendarEvents: [CalendarDayEvent], overdueTasks: [FamilyTask]) -> some View {
        if !overdueTasks.isEmpty {
            Section {
                ForEach(overdueTasks) { task in
                    taskRow(task, isOverdue: true)
                }
            } header: {
                SectionTitle(text: "Overdue", color: AppTheme.destructive)
            }
        }

        if selectedTasks.isEmpty && recurringTasks.isEmpty && calendarEvents.isEmpty {
            Section {
                Label(calendar.isDateInToday(selectedDate) ? "Nothing else planned today" : "Nothing planned", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppTheme.surface)
            } header: {
                SectionTitle(text: dayTitle)
            }
        }

        if scheduleContentPriority == .tasksFirst {
            scheduledTaskSections(selectedTasks: selectedTasks, recurringTasks: recurringTasks)
            calendarSection(calendarEvents)
        } else {
            calendarSection(calendarEvents)
            scheduledTaskSections(selectedTasks: selectedTasks, recurringTasks: recurringTasks)
        }
    }

    /// "Today", "Tomorrow" or "Fri, Oct 2".
    private var dayTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var scheduleContentPriority: ScheduleContentPriority {
        ScheduleContentPriority(rawValue: contentPriorityRaw) ?? .tasksFirst
    }

    private var taskSortOrder: ScheduleTaskSortOrder {
        ScheduleTaskSortOrder(rawValue: taskSortOrderRaw) ?? .priority
    }

    private func sortedTasks(_ tasks: [FamilyTask]) -> [FamilyTask] {
        tasks.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone {
                return !lhs.isDone
            }

            switch taskSortOrder {
            case .priority:
                if lhs.bucket.sortPriority != rhs.bucket.sortPriority {
                    return lhs.bucket.sortPriority < rhs.bucket.sortPriority
                }
                return taskDeadlineSort(lhs, rhs)
            case .deadline:
                if taskDeadlineKey(lhs) != taskDeadlineKey(rhs) {
                    return taskDeadlineKey(lhs) < taskDeadlineKey(rhs)
                }
                return lhs.bucket.sortPriority < rhs.bucket.sortPriority
            }
        }
    }

    private func taskDeadlineSort(_ lhs: FamilyTask, _ rhs: FamilyTask) -> Bool {
        if taskDeadlineKey(lhs) != taskDeadlineKey(rhs) {
            return taskDeadlineKey(lhs) < taskDeadlineKey(rhs)
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func taskDeadlineKey(_ task: FamilyTask) -> Date {
        task.dueDate ?? Date.distantFuture
    }

    @ViewBuilder
    private func scheduledTaskSections(selectedTasks: [FamilyTask], recurringTasks: [RecurringTask]) -> some View {
        if !selectedTasks.isEmpty {
            Section {
                ForEach(selectedTasks) { task in
                    taskRow(task)
                }
            } header: {
                SectionTitle(text: dayTitle)
            }
        }

        if !recurringTasks.isEmpty {
            Section {
                ForEach(recurringTasks) { task in
                    RecurringScheduleRow(task: task) {
                        organizerStore.markRecurringDone(task)
                    }
                    .listRowBackground(AppTheme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            organizerStore.deleteRecurringTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                SectionTitle(text: "Recurring")
            }
        }
    }

    @ViewBuilder
    private func calendarSection(_ calendarEvents: [CalendarDayEvent]) -> some View {
        if !calendarEvents.isEmpty {
            Section {
                ForEach(calendarEvents) { event in
                    CalendarEventRow(event: event)
                        .listRowBackground(AppTheme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                calendarSync.removeTodayEvent(event)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } header: {
                SectionTitle(text: "Calendar")
            }
        }
    }

    private func taskRow(_ task: FamilyTask, isOverdue: Bool = false) -> some View {
        TodayTaskRow(
            task: task,
            isOverdue: isOverdue,
            showTime: showTaskTime,
            showTag: showPriorityTags
        ) {
            taskStore.markDone(task)
        } onEdit: {
            editingTask = task
        }
        .listRowBackground(AppTheme.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                taskStore.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

enum ScheduleDisplayMode: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// Small bold uppercase section title: "OVERDUE", "TODAY", "FRI, OCT 2".
private struct SectionTitle: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .textCase(nil)
    }
}

enum DayMarker {
    case none
    case planned
    case overdue

    var color: Color {
        switch self {
        case .none: .clear
        case .planned: .secondary
        case .overdue: AppTheme.destructive
        }
    }
}

private struct WeekStripView: View {
    @Binding var selectedDate: Date
    let marker: (Date) -> DayMarker

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                dayButton(day)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .gesture(weekSwipeGesture)
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 48 else { return }
                selectedDate = calendar.date(
                    byAdding: .weekOfYear,
                    value: value.translation.width < 0 ? 1 : -1,
                    to: selectedDate
                ) ?? selectedDate
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
        let isToday = calendar.isDateInToday(day)
        let dayMarker = marker(day)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : (isToday ? AppTheme.primary : .secondary))
                Text(day.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : .primary)
                Circle()
                    .fill(isSelected && dayMarker != .none ? AppTheme.onPrimary : dayMarker.color)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.primary : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A month at a glance; tap a day to see its tasks below.
private struct MonthGridView: View {
    @Binding var selectedDate: Date
    let marker: (Date) -> DayMarker

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            // Indexed: the one-letter names repeat (S, T), and ForEach drops duplicate IDs.
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 20)
            }

            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayButton(day)
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
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
        let dayMarker = marker(day)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : (isToday ? AppTheme.primary : .primary))
                    .frame(width: 34, height: 30)
                    .background(isSelected ? AppTheme.primary : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Circle()
                    .fill(dayMarker.color)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CalendarEventRow: View {
    let event: CalendarDayEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                Text("\(timeText) · \(event.calendarTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

private struct RecurringScheduleRow: View {
    let task: RecurringTask
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel("Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(task.frequency.title, systemImage: "repeat")
                    if !task.amount.isEmpty {
                        Text(task.amount)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            AssigneeAvatarView(name: task.assignedTo, size: 28, showsPhoto: false)
        }
    }
}

private struct TodayTaskRow: View {
    let task: FamilyTask
    var isOverdue = false
    let showTime: Bool
    let showTag: Bool
    let onDone: () -> Void
    let onEdit: () -> Void
    @AppStorage("profile.email") private var profileEmail = ""

    /// "Was due yesterday", "Was due Tuesday" (this past week) or "Was due Sep 12".
    static func overdueText(for dueDate: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...1: return "Was due yesterday"
        case 2...6: return "Was due \(dueDate.formatted(.dateTime.weekday(.wide)))"
        default: return "Was due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                checkCircle
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                detailLine
            }

            Spacer(minLength: 8)

            AssigneeAvatarView(name: task.primaryAssigneeForAvatar, size: 28, showsPhoto: false)
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
        }
    }

    @ViewBuilder
    private var checkCircle: some View {
        if task.isDone {
            Image(systemName: "checkmark")
                .font(.caption.weight(.heavy))
                .foregroundStyle(AppTheme.onAvatar)
                .frame(width: 26, height: 26)
                .background(AppTheme.success, in: Circle())
        } else {
            Circle()
                .strokeBorder(isOverdue ? AppTheme.destructive : Color.secondary, lineWidth: 2)
                .frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        if let completion = task.completionSummary(viewerEmail: profileEmail) {
            Text(completion)
                .font(.footnote)
                .foregroundStyle(AppTheme.success)
        } else if isOverdue, let dueDate = task.dueDate {
            Text(Self.overdueText(for: dueDate))
                .font(.footnote)
                .foregroundStyle(AppTheme.destructive)
        } else if showTag || showTime {
            HStack(spacing: 8) {
                if showTag {
                    PriorityTag(bucket: task.bucket)
                }
                if showTime {
                    Text(task.dueDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Anytime")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// "Do now", "Schedule", "Delegate" or "Someday" in the bucket's color.
private struct PriorityTag: View {
    let bucket: TaskBucket

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(bucket.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(bucket.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var title: String {
        switch bucket {
        case .doNow: "Do now"
        case .schedule: "Schedule"
        case .delegate: "Delegate"
        case .delete: "Someday"
        }
    }
}

enum ScheduleContentPriority: String, CaseIterable, Identifiable {
    case tasksFirst
    case calendarFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasksFirst: "Tasks First"
        case .calendarFirst: "Calendar First"
        }
    }
}

/// "THURSDAY, OCT 1 / Good evening, Naveen" with today's progress and family news.
private struct TodayHeader: View {
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.name") private var profileName = ""
    let onAdd: () -> Void

    var body: some View {
        let now = Date()
        let today = taskStore.tasksScheduledToday()
        let done = today.filter(\.isDone).count
        let overdue = taskStore.pendingTasks(before: now).count

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        .font(.footnote.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(AppTheme.primary)
                    Text(Self.greeting(at: now, name: profileName, email: profileEmail))
                        .font(.title.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 12)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.primary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }

            HStack(spacing: 14) {
                ProgressRing(fraction: today.isEmpty ? 0 : Double(done) / Double(today.count))
                    .overlay {
                        if today.isEmpty {
                            Image(systemName: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.isEmpty ? "Nothing due today" : "\(done) of \(today.count) done today")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let detail = detail(overdue: overdue, now: now) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                FamilyAvatarStack(emails: familyForStack)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// You first, then up to two others.
    private var familyForStack: [String] {
        let me = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let others = taskStore.exportFamilyMembers().filter { $0 != me }
        return Array(((me.isEmpty ? [] : [me]) + others).prefix(3))
    }

    /// "1 overdue · Sam finished Take out bins"
    private func detail(overdue: Int, now: Date) -> String? {
        var parts: [String] = []
        if overdue > 0 {
            parts.append("\(overdue) overdue")
        }
        let me = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let latestByOthers = taskStore.visibleTasks
            .filter { task in
                guard let by = task.completedBy?.lowercased(), by != me, let at = task.completedAt else { return false }
                return Calendar.current.isDate(at, inSameDayAs: now)
            }
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        if let latest = latestByOthers, let by = latest.completedBy {
            parts.append("\(Self.firstName(for: by)) finished \(latest.title)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Good evening, Naveen": the name set in Profile, else the first part of the email.
    static func greeting(at date: Date, name: String = "", email: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let partOfDay = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return "\(partOfDay), \(trimmedName)"
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TaskStore.isValidEmail(trimmed) else { return partOfDay }
        return "\(partOfDay), \(firstName(for: trimmed))"
    }

    /// "naveen.keerthy@…" → "Naveen"
    static func firstName(for email: String) -> String {
        let name = Assignee.memberName(for: email)
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}

private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.surfaceMuted, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(AppTheme.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut, value: fraction)
        .accessibilityHidden(true)
    }
}

private struct FamilyAvatarStack: View {
    let emails: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(emails, id: \.self) { email in
                AssigneeAvatarView(name: email, size: 30, showsPhoto: false)
                    .overlay(Circle().stroke(AppTheme.surface, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
