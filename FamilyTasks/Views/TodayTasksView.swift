import SwiftUI

struct TodayTasksView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @EnvironmentObject private var habitStore: HabitStore
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.showTaskTime") private var showTaskTime = true
    @AppStorage("schedule.showPriorityTags") private var showPriorityTags = true
    @AppStorage("schedule.defaultDisplayMode") private var defaultDisplayModeRaw = ScheduleDisplayMode.week.rawValue
    @AppStorage(TodaySection.storageKey) private var sectionOrderRaw = ""
    @AppStorage(TodaySection.legacyPriorityKey) private var legacyPriorityRaw = ""
    @AppStorage(TodaySection.showHabitsKey) private var showHabits = true
    @AppStorage(TodayKind.colorCodeKey) private var colorCode = true
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("schedule.taskSortOrder") private var taskSortOrderRaw = ScheduleTaskSortOrder.priority.rawValue
    @State private var isAddingTask = false
    @State private var editingTask: FamilyTask?
    @State private var editingHabit: Habit?
    @State private var selectedDate = Date()
    @State private var displayMode: ScheduleDisplayMode = .week
    @State private var hasLoaded = false
    @Environment(\.scenePhase) private var scenePhase

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
                    overdueTasks: overdueTasksForSelectedDay,
                    habits: showHabits ? habitStore.myHabits(on: selectedDate) : []
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
                // Once, not on every switch to this tab: reloading as the tab appeared
                // redrew the list mid-transition. Coming back to the app reloads instead.
                guard !hasLoaded else { return }
                hasLoaded = true
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, calendarIntegrationEnabled else { return }
                Task {
                    await calendarSync.loadEvents(on: selectedDate)
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
            .sheet(item: $editingHabit) { habit in
                HabitEditorView(habit: habit)
            }
            .sheet(isPresented: $isAddingTask, onDismiss: {
                // Back to today, even when the new task is for another day.
                selectedDate = Date()
            }) {
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
                    .minimumScaleFactor(0.7)
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
            return Self.weekTitle(from: interval.start, to: end, calendar: calendar)
        }
    }

    /// "Oct 11 – 17", or "Sep 28 – Oct 4" across months: short enough to fit beside the
    /// Week/Month switch.
    nonisolated static func weekTitle(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
        let startText = start.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startText) – \(end.formatted(.dateTime.day()))"
        }
        return "\(startText) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
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
    private func dayContent(selectedTasks: [FamilyTask], recurringTasks: [RecurringTask], calendarEvents: [CalendarDayEvent], overdueTasks: [FamilyTask], habits: [Habit]) -> some View {
        let hasTasks = !selectedTasks.isEmpty || !overdueTasks.isEmpty || !recurringTasks.isEmpty
        let visible = sectionOrder.filter { section in
            switch section {
            case .tasks: hasTasks
            case .habits: !habits.isEmpty
            case .calendar: !calendarEvents.isEmpty
            }
        }
        if selectedTasks.isEmpty && recurringTasks.isEmpty && calendarEvents.isEmpty && habits.isEmpty {
            Section {
                Label(calendar.isDateInToday(selectedDate) ? "Nothing planned today" : "Nothing planned", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppTheme.surface)
            } header: {
                SectionTitle(text: dayTitle)
            }
        }

        ForEach(visible) { section in
            let arrange: SectionArrangeMenu? = visible.count > 1 ? SectionArrangeMenu(section: section, visible: visible) { direction in
                moveSection(section, direction, among: visible)
            } : nil
            switch section {
            case .tasks:
                scheduledTaskSections(selectedTasks: selectedTasks, recurringTasks: recurringTasks, overdueTasks: overdueTasks, arrange: arrange)
            case .habits:
                habitSection(habits, arrange: arrange)
            case .calendar:
                calendarSection(calendarEvents, arrange: arrange)
            }
        }
    }

    /// Tasks, Habits and Calendar in the order chosen here or in Appearance.
    private var sectionOrder: [TodaySection] {
        TodaySection.order(from: sectionOrderRaw, legacyPriority: legacyPriorityRaw)
    }

    /// Swaps `section` with the block shown just above or below it, so a move always
    /// changes what's on screen even when a block in between is empty today.
    private func moveSection(_ section: TodaySection, _ direction: TodaySection.Direction, among visible: [TodaySection]) {
        withAnimation(.snappy) {
            sectionOrderRaw = TodaySection.encode(TodaySection.moving(section, direction, in: sectionOrder, among: visible))
        }
    }

    /// "Today (3)"
    private static func counted(_ title: String, _ count: Int) -> String {
        "\(title) (\(count))"
    }

    /// "Today", "Tomorrow" or "Fri, Oct 2".
    private var dayTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
    private func scheduledTaskSections(selectedTasks: [FamilyTask], recurringTasks: [RecurringTask], overdueTasks: [FamilyTask], arrange: SectionArrangeMenu?) -> some View {
        // The block's arrange menu sits on whichever of its headers comes first.
        let firstHeader = !selectedTasks.isEmpty ? 0 : (!overdueTasks.isEmpty ? 1 : 2)
        if !selectedTasks.isEmpty {
            Section {
                ForEach(selectedTasks) { task in
                    taskRow(task)
                }
            } header: {
                SectionHeader(title: Self.counted(dayTitle, selectedTasks.count), dot: dot(.task), arrange: arrange)
            }
        }

        // Overdue tasks are shown with today, after the ones due today.
        if !overdueTasks.isEmpty {
            Section {
                ForEach(overdueTasks) { task in
                    taskRow(task, isOverdue: true)
                }
            } header: {
                SectionHeader(title: Self.counted("Overdue", overdueTasks.count), color: AppTheme.overdue, dot: dot(.overdue), arrange: firstHeader == 1 ? arrange : nil)
            }
        }

        if !recurringTasks.isEmpty {
            Section {
                ForEach(recurringTasks) { task in
                    RecurringScheduleRow(task: task) {
                        organizerStore.markRecurringDone(task)
                    }
                    .listRowBackground(rowBackground(.recurring))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            organizerStore.deleteRecurringTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                SectionHeader(title: Self.counted("Recurring", recurringTasks.count), dot: dot(.recurring), arrange: firstHeader == 2 ? arrange : nil)
            }
        }
    }

    /// The day's habits, apart from the tasks. Days ahead can't be checked off yet.
    @ViewBuilder
    private func habitSection(_ habits: [Habit], arrange: SectionArrangeMenu?) -> some View {
        if !habits.isEmpty {
            let done = habits.filter { habitStore.isDone($0, on: selectedDate) }.count
            Section {
                ForEach(habits) { habit in
                    HabitRow(habit: habit, date: selectedDate, canLog: selectedDate <= Date()) {
                        editingHabit = habit
                    }
                    .listRowBackground(rowBackground(.habit))
                }
            } header: {
                SectionHeader(title: "Habits (\(done)/\(habits.count))", dot: dot(.habit), arrange: arrange)
            }
        }
    }

    @ViewBuilder
    private func calendarSection(_ calendarEvents: [CalendarDayEvent], arrange: SectionArrangeMenu?) -> some View {
        if !calendarEvents.isEmpty {
            Section {
                ForEach(calendarEvents) { event in
                    CalendarEventRow(event: event)
                        .listRowBackground(rowBackground(.calendar))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                calendarSync.removeTodayEvent(event)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } header: {
                SectionHeader(title: "Calendar", dot: dot(.calendar), arrange: arrange)
            }
        }
    }

    /// The card color behind a row: the surface with a light wash of its kind's color.
    private func rowBackground(_ kind: TodayKind) -> some View {
        ZStack {
            AppTheme.surface
            if colorCode {
                kind.tint.opacity(TodayKind.washOpacity(for: colorScheme))
            }
        }
    }

    private func dot(_ kind: TodayKind) -> Color? {
        colorCode ? kind.tint : nil
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
        .listRowBackground(rowBackground(isOverdue ? .overdue : .task))
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
struct SectionTitle: View {
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
        case .overdue: AppTheme.overdue
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

            NudgeButton(item: task, dueDate: task.nextDueDate)

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

            if let location = task.location {
                MapPinButton(location: location)
            }

            NudgeButton(item: task, dueDate: task.dueDate, isDone: task.isDone)

            AssigneeAvatarView(name: task.primaryAssigneeForAvatar, size: 28, showsPhoto: false)
        }
        .contentShape(Rectangle())
        // One tap opens the task; the circle marks it done.
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "Edit", onEdit)
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
                .strokeBorder(isOverdue ? AppTheme.overdue : Color.secondary, lineWidth: 2)
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
                .foregroundStyle(AppTheme.overdue)
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
        Text(bucket.tagTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(bucket.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(bucket.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// The blocks Today shows below the week, in an order the family picks.
enum TodaySection: String, CaseIterable, Identifiable {
    case tasks
    case habits
    case calendar

    enum Direction {
        case up
        case down
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .calendar: "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "checklist"
        case .habits: "flame"
        case .calendar: "calendar"
        }
    }

    static let storageKey = "schedule.sectionOrder"
    static let showHabitsKey = "schedule.showHabits"
    /// The earlier Tasks First / Calendar First choice, read once there's no order saved.
    static let legacyPriorityKey = "schedule.contentPriority"

    /// The saved order, each block once, with any missing ones added at the end.
    static func order(from raw: String, legacyPriority: String = "") -> [TodaySection] {
        var order: [TodaySection] = []
        for section in raw.split(separator: ",").compactMap({ TodaySection(rawValue: String($0)) }) where !order.contains(section) {
            order.append(section)
        }
        if order.isEmpty {
            order = legacyPriority == "calendarFirst" ? [.calendar, .tasks, .habits] : [.tasks, .habits, .calendar]
        }
        return order + allCases.filter { !order.contains($0) }
    }

    /// Swaps `section` with its neighbor among `visible` (all of them when nil).
    static func moving(_ section: TodaySection, _ direction: Direction, in order: [TodaySection], among visible: [TodaySection]? = nil) -> [TodaySection] {
        let shown = visible ?? order
        guard let index = shown.firstIndex(of: section) else { return order }
        let neighborIndex = direction == .up ? index - 1 : index + 1
        guard shown.indices.contains(neighborIndex),
              let from = order.firstIndex(of: section),
              let to = order.firstIndex(of: shown[neighborIndex]) else { return order }
        var updated = order
        updated.swapAt(from, to)
        return updated
    }

    static func encode(_ order: [TodaySection]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}

/// The kinds of item on Today, each with its own light color so they're easy to tell apart.
/// The colors come from the theme, so they suit every theme and dark mode.
enum TodayKind {
    case task
    case overdue
    case recurring
    case habit
    case calendar

    static let colorCodeKey = "schedule.colorCodeSections"
    /// Light enough that text keeps its contrast, strong enough to see. Dark mode needs a
    /// little more, since the theme's dark tints are pale and the cards are dark.
    static func washOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.18 : 0.10
    }

    var tint: Color {
        switch self {
        case .task: AppTheme.coolAccent
        case .overdue: AppTheme.overdue
        case .recurring: AppTheme.softAccent
        case .habit: AppTheme.success
        case .calendar: AppTheme.goldAccent
        }
    }
}

/// What a section header needs to offer Move Up and Move Down.
struct SectionArrangeMenu {
    let section: TodaySection
    let visible: [TodaySection]
    let move: (TodaySection.Direction) -> Void
}

/// A section title with, when there's more than one block, a small menu to move its block.
private struct SectionHeader: View {
    let title: String
    var color: Color = .secondary
    /// The kind's color, matching its rows, when Today is color-coded.
    var dot: Color?
    let arrange: SectionArrangeMenu?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            SectionTitle(text: title, color: color)
            Spacer(minLength: 8)
            if let arrange {
                Menu {
                    Button {
                        arrange.move(.up)
                    } label: {
                        Label("Move \(arrange.section.title) Up", systemImage: "arrow.up")
                    }
                    .disabled(arrange.visible.first == arrange.section)
                    Button {
                        arrange.move(.down)
                    } label: {
                        Label("Move \(arrange.section.title) Down", systemImage: "arrow.down")
                    }
                    .disabled(arrange.visible.last == arrange.section)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Arrange \(arrange.section.title)")
                .textCase(nil)
            }
        }
    }
}

/// "THURSDAY, OCT 1 / Naveen 👋" with the add button.
private struct TodayHeader: View {
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.name") private var profileName = ""
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.primary)
                Text(Self.greeting(name: profileName, email: profileEmail))
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
    }

    /// "Naveen 👋": the name set in Profile, else the first part of the email.
    static func greeting(name: String = "", email: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return "\(trimmedName) 👋"
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TaskStore.isValidEmail(trimmed) else { return "Hello 👋" }
        return "\(firstName(for: trimmed)) 👋"
    }

    /// "naveen.keerthy@…" → "Naveen"
    static func firstName(for email: String) -> String {
        let name = Assignee.memberName(for: email)
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}

private struct MapPinButton: View {
    let location: TaskLocation
    @Environment(\.openURL) private var openURL
    @State private var isChoosingApp = false

    var body: some View {
        Button {
            isChoosingApp = true
        } label: {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.coolAccent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Directions to \(location.name)")
        .confirmationDialog("Open \(location.name) in", isPresented: $isChoosingApp, titleVisibility: .visible) {
            ForEach(availableApps) { app in
                Button(app.title) {
                    if let url = app.url(for: location) {
                        openURL(url)
                    }
                }
            }
        } message: {
            if let address = location.address, !address.isEmpty {
                Text(address)
            }
        }
    }

    /// Apple and Google Maps always (Google opens its website when the app isn't
    /// installed); Waze only when it is.
    private var availableApps: [MapApp] {
        MapApp.allCases.filter { app in
            guard let check = app.installCheckURL else { return true }
            return UIApplication.shared.canOpenURL(check)
        }
    }
}
