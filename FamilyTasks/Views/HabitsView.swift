import SwiftUI

/// Your habits, today's first, and the ones the family shares.
struct HabitsView: View {
    @EnvironmentObject private var habitStore: HabitStore
    var isPushed = false
    @State private var isAdding = false
    @State private var editingHabit: Habit?

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from More.
        let today = habitStore.myHabits(on: Date())
        let todayIDs = Set(today.map(\.id))
        let notToday = habitStore.myHabits.filter { !todayIDs.contains($0.id) }
        let family = habitStore.familyHabits
        List {
            Section {
                ScreenHeader(eyebrow: summary(today: today), title: "Habits") {
                    HeaderAddButton(accessibilityLabel: "Add habit") { isAdding = true }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            if habitStore.myHabits.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Habits Yet", systemImage: "flame")
                    } description: {
                        Text("Drink water, read, walk the dog: something you do on certain days, once or a few times a day.")
                    } actions: {
                        Button("Add Habit") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }
            if !today.isEmpty {
                Section {
                    ForEach(today) { habit in myRow(habit) }
                } header: {
                    SectionTitle(text: "Today")
                }
            }
            if !notToday.isEmpty {
                Section {
                    ForEach(notToday) { habit in myRow(habit, isScheduledToday: false) }
                } header: {
                    SectionTitle(text: "Not Today")
                }
            }
            if !family.isEmpty {
                Section {
                    ForEach(family) { habit in
                        HabitRow(habit: habit, date: Date(), showsOwner: true)
                            .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    SectionTitle(text: "Family")
                } footer: {
                    Text("Habits others share. Only the person they belong to can check them off.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Habits", isPushed: isPushed)
        .sheet(isPresented: $isAdding) {
            HabitEditorView()
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
    }

    /// "2 of 4 done today", or how many habits there are when none are on today.
    private func summary(today: [Habit]) -> String {
        guard !today.isEmpty else {
            let count = habitStore.myHabits.count
            return count == 1 ? "1 habit" : "\(count) habits"
        }
        let done = today.filter { habitStore.isDone($0) }.count
        return "\(done) of \(today.count) done today"
    }

    private func myRow(_ habit: Habit, isScheduledToday: Bool = true) -> some View {
        HabitRow(habit: habit, date: Date(), canLog: isScheduledToday) {
            editingHabit = habit
        }
        .listRowBackground(AppTheme.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                habitStore.delete(habit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingHabit = habit
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.primary)
        }
    }
}

/// A habit with its progress on `date`, "3 of 8 done", and a button to record one more
/// time. Used on Habits and Today. Other people's habits show their avatar instead.
struct HabitRow: View {
    @EnvironmentObject private var habitStore: HabitStore
    let habit: Habit
    let date: Date
    var canLog = true
    var showsOwner = false
    var onEdit: (() -> Void)?

    var body: some View {
        let count = habitStore.count(of: habit, on: date)
        let isDone = count >= habit.timesPerDay
        let isMine = habitStore.isMine(habit)
        HStack(spacing: 12) {
            HabitProgressRing(habit: habit, count: count)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if canLog {
                        Text("\(count) of \(habit.timesPerDay) done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isDone ? AppTheme.success : habit.color.color)
                            .contentTransition(.numericText())
                    }
                    StreakBadge(streak: habitStore.streak(for: habit).current)
                }

                HStack(spacing: 6) {
                    Text(Self.timesText(habit.timesPerDay))
                    Text("·")
                    Text(habit.scheduleText(includesTimes: false))
                    if isMine && habit.isShared {
                        Image(systemName: "person.2.fill")
                            .accessibilityLabel("Shared with family")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsOwner {
                AssigneeAvatarView(name: habit.ownerEmail, size: 28, showsPhoto: false)
            } else if isMine && canLog {
                HabitLogButton(habit: habit, count: count) {
                    withAnimation(.snappy) {
                        habitStore.log(habit, on: date)
                    }
                }
            }
        }
        .opacity(canLog || !isMine ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { onEdit?() }
        // Taking one back is a swipe (or the menu), so a tap on a finished habit never undoes it.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isMine && canLog && count > 0 {
                Button {
                    withAnimation(.snappy) {
                        habitStore.undo(habit, on: date)
                    }
                } label: {
                    Label("Undo One", systemImage: "arrow.uturn.backward")
                }
                .tint(AppTheme.goldAccent)
            }
        }
        .contextMenu {
            if isMine && canLog && count > 0 {
                Button {
                    habitStore.undo(habit, on: date)
                } label: {
                    Label("Undo One", systemImage: "arrow.uturn.backward")
                }
            }
            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
    }

    /// "Once a day", "8× a day": short, so it fits beside the days.
    static func timesText(_ times: Int) -> String {
        times == 1 ? "Once a day" : "\(times)× a day"
    }
}

/// Records the habit: "Done" when it's once a day, "+1" when it's more. Once the day's
/// target is reached it becomes a green "Done" badge that does nothing when tapped.
private struct HabitLogButton: View {
    let habit: Habit
    let count: Int
    let action: () -> Void

    var body: some View {
        let isDone = count >= habit.timesPerDay
        let isOnce = habit.timesPerDay == 1
        let tint = habit.color.color
        Button(action: action) {
            Group {
                if isDone || isOnce {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("+1")
                }
            }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isDone ? AppTheme.onAvatar : tint)
                .padding(.horizontal, 12)
                .frame(minWidth: 56, minHeight: 34)
                .background(isDone ? AppTheme.success : tint.opacity(0.15), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDone)
        .accessibilityLabel(isDone ? "\(habit.name) done" : "Record \(habit.name)")
        .accessibilityValue("\(count) of \(habit.timesPerDay) done")
    }
}

/// The habit's symbol in a ring that fills as it's logged, with a check when done.
struct HabitProgressRing: View {
    let habit: Habit
    let count: Int
    var size: CGFloat = 30

    var body: some View {
        let tint = habit.color.color
        let progress = min(Double(count) / Double(max(habit.timesPerDay, 1)), 1)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress >= 1 {
                Circle()
                    .fill(tint)
                    .padding(3)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: habit.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: count)
    }
}

/// "🔥 5": days in a row, shown once there's a streak.
private struct StreakBadge: View {
    let streak: Int

    var body: some View {
        if streak > 0 {
            Label("\(streak)", systemImage: "flame.fill")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
                .accessibilityLabel("\(streak) day streak")
        }
    }
}

// MARK: Editor

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var habitStore: HabitStore
    let habit: Habit?
    @State private var name: String
    @State private var symbol: String
    @State private var color: HabitColor
    @State private var timesPerDay: Int
    @State private var weekdays: Set<Int>
    @State private var isShared: Bool
    @FocusState private var isNameFocused: Bool

    private let calendar = Calendar.current

    init(habit: Habit? = nil) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _symbol = State(initialValue: habit?.symbol ?? HabitSymbols.all[0])
        _color = State(initialValue: habit?.color ?? .teal)
        _timesPerDay = State(initialValue: habit?.timesPerDay ?? 1)
        // Every day is stored as no days; here it's all seven, so each can be turned off.
        let days = habit?.weekdays ?? []
        _weekdays = State(initialValue: days.isEmpty ? Set(1...7) : Set(days))
        _isShared = State(initialValue: habit?.isShared ?? false)
    }

    /// The latest copy, so the history shows what was just tapped.
    private var currentHabit: Habit? {
        habit.flatMap { habit in habitStore.habits.first { $0.id == habit.id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 14) {
                        IconTile(systemImage: symbol, tint: color.color, size: 52)
                        TextField("New habit", text: $name, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isNameFocused)
                    }

                    EditorSection("Days") {
                        HStack(spacing: 6) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                weekdayButton(day)
                            }
                        }
                        Text(weekdays.isEmpty ? "Pick at least one day." : previewSchedule)
                            .font(.footnote)
                            .foregroundStyle(weekdays.isEmpty ? AppTheme.destructive : .secondary)
                    }

                    EditorSection("Times a Day") {
                        Stepper(value: $timesPerDay, in: 1...20) {
                            Text(timesPerDay == 1 ? "Once" : "\(timesPerDay) times")
                                .font(.body.weight(.semibold))
                        }
                        .padding(12)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    EditorSection("Color") {
                        HStack(spacing: 0) {
                            ForEach(HabitColor.allCases) { option in
                                Button {
                                    color = option
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 26, height: 26)
                                        .overlay {
                                            if option == color {
                                                Circle().strokeBorder(AppTheme.ink, lineWidth: 2).padding(-4)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.rawValue.capitalized)
                                .accessibilityAddTraits(option == color ? .isSelected : [])
                            }
                        }
                    }

                    EditorSection("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(HabitSymbols.all, id: \.self) { option in
                                Button {
                                    symbol = option
                                } label: {
                                    Image(systemName: option)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(option == symbol ? AppTheme.onPrimary : color.color)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            option == symbol ? color.color : AppTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option)
                                .accessibilityAddTraits(option == symbol ? .isSelected : [])
                            }
                        }
                    }

                    EditorSection("Sharing") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $isShared) {
                                Label("Share with family", systemImage: "person.2")
                                    .labelStyle(.tile(AppTheme.coolAccent))
                            }
                            .padding(12)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(isShared
                                 ? "Your family sees this habit and its streak. Only you can check it off."
                                 : "Private: it stays on this phone.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let currentHabit {
                        EditorSection("Last 5 Weeks") {
                            HabitHistoryGrid(habit: currentHabit)
                            Text("Tap a day to fix it: each tap adds one, then starts over.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        EditorDeleteButton(
                            title: "Delete Habit",
                            message: currentHabit.isShared ? "It's removed for everyone in the family, with its history." : "Its history is removed too."
                        ) {
                            habitStore.delete(currentHabit)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit == nil ? "Add" : "Save") {
                        let days = Array(weekdays)
                        if let habit {
                            habitStore.update(habit, name: name, symbol: symbol, color: color, timesPerDay: timesPerDay, weekdays: days, isShared: isShared)
                        } else {
                            habitStore.add(name: name, symbol: symbol, color: color, timesPerDay: timesPerDay, weekdays: days, isShared: isShared)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty)
                }
            }
            .onAppear {
                if habit == nil { isNameFocused = true }
            }
        }
    }

    /// Weekdays in the calendar's own order, so Monday-first places start on Monday.
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var previewSchedule: String {
        Habit(name: name, timesPerDay: timesPerDay, weekdays: weekdays.count == 7 ? [] : Array(weekdays), ownerEmail: "")
            .scheduleText(calendar: calendar)
    }

    private func weekdayButton(_ day: Int) -> some View {
        let isOn = weekdays.contains(day)
        return Button {
            if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(calendar.veryShortWeekdaySymbols[day - 1])
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? AppTheme.onPrimary : AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isOn ? color.color : AppTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.weekdaySymbols[day - 1])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The last five weeks, a square per day filled by how much was done. Days it isn't
/// on are faint; tapping a day up to today cycles its count.
private struct HabitHistoryGrid: View {
    @EnvironmentObject private var habitStore: HabitStore
    let habit: Habit

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private var weekdayLetters: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    /// Five full weeks ending with this one.
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
            let start = calendar.date(byAdding: .weekOfYear, value: -4, to: thisWeek.start)
        else { return [today] }
        return (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > Date()
        let isScheduled = habit.isScheduled(on: day, calendar: calendar)
        let count = habitStore.count(of: habit, on: day)
        let progress = min(Double(count) / Double(habit.timesPerDay), 1)
        let tint = habit.color.color
        return Button {
            habitStore.cycle(habit, on: day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(.caption.weight(calendar.isDateInToday(day) ? .heavy : .medium))
                .foregroundStyle(progress >= 1 ? .white : (isFuture ? .secondary : AppTheme.ink))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    progress > 0 ? tint.opacity(0.35 + 0.65 * progress) : tint.opacity(isScheduled ? 0.12 : 0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isFuture || !habitStore.isMine(habit))
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(isScheduled ? "\(count) of \(habit.timesPerDay)" : "Not scheduled, \(count) logged")
    }
}
