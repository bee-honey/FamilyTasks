import SwiftUI

struct RecurringTasksView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var isAdding = false
    @State private var editingTask: RecurringTask?

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            if organizerStore.visibleRecurringTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Tasks", systemImage: "repeat")
                } description: {
                    Text("Bills, filters, birthdays: anything that comes round again.")
                } actions: {
                    Button("Add Recurring Task") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add recurring task")
            }
        }
        .sheet(isPresented: $isAdding) {
            RecurringTaskEditorView()
        }
        .sheet(item: $editingTask) { task in
            RecurringTaskEditorView(task: task)
        }
    }

    private var list: some View {
        let sorted = organizerStore.visibleRecurringTasks.sorted { $0.nextDueDate < $1.nextDueDate }
        let active = sorted.filter(\.isActive)
        let paused = sorted.filter { !$0.isActive }
        return List {
            if !active.isEmpty {
                Section {
                    ForEach(active) { task in row(task) }
                } header: {
                    SectionTitle(text: "Coming Up")
                }
            }
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { task in row(task) }
                } header: {
                    SectionTitle(text: "Paused")
                } footer: {
                    Text("Paused tasks don't remind anyone or show on Today. Swipe to resume.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ task: RecurringTask) -> some View {
        RecurringTaskRow(task: task) {
            organizerStore.markRecurringDone(task)
        } onEdit: {
            editingTask = task
        }
        .listRowBackground(AppTheme.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                organizerStore.deleteRecurringTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingTask = task
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.primary)
        }
        .swipeActions(edge: .leading) {
            Button {
                organizerStore.toggleRecurringActive(task)
            } label: {
                Label(task.isActive ? "Pause" : "Resume", systemImage: task.isActive ? "pause" : "play")
            }
            .tint(task.isActive ? AppTheme.goldAccent : AppTheme.success)
        }
    }
}

/// A circle to mark this time done, the title, how often and when next, and who it's for.
private struct RecurringTaskRow: View {
    let task: RecurringTask
    let onDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Circle()
                    .strokeBorder(isOverdue ? AppTheme.overdue : Color.secondary, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .disabled(!task.isActive)
            .accessibilityLabel("Mark \(task.title) done for this time")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                    Text(task.frequency.title)
                    Text("·")
                    Text(nextText)
                        .foregroundStyle(isOverdue ? AppTheme.overdue : .secondary)
                    if !task.amount.isEmpty {
                        Text("·")
                        Text(task.amount)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            AssigneeAvatarView(name: task.primaryAssigneeForAvatar, size: 28, showsPhoto: false)
        }
        .opacity(task.isActive ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    private var isOverdue: Bool {
        task.isActive && task.nextDueDate < Calendar.current.startOfDay(for: Date())
    }

    private var nextText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(task.nextDueDate) { return "Today" }
        if calendar.isDateInTomorrow(task.nextDueDate) { return "Tomorrow" }
        if isOverdue { return "Was due \(task.nextDueDate.formatted(.dateTime.month(.abbreviated).day()))" }
        return task.nextDueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct RecurringTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var taskStore: TaskStore
    let task: RecurringTask?
    @State private var draft: RecurringTaskDraft
    @FocusState private var isTitleFocused: Bool

    init(task: RecurringTask? = nil) {
        self.task = task
        _draft = State(initialValue: task.map(RecurringTaskDraft.init(task:)) ?? RecurringTaskDraft())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What repeats?", text: $draft.title, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isTitleFocused)
                        TextField("Add notes", text: $draft.notes, axis: .vertical)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...5)
                    }

                    EditorSection("For") {
                        AssigneePicker(draft: $draft, familyMembers: taskStore.familyMembers, noun: "recurring task")
                    }

                    EditorSection("Repeats") {
                        WrappingStack(spacing: 8) {
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                ChoiceChip(title: frequency.title, isSelected: draft.frequency == frequency) {
                                    draft.frequency = frequency
                                }
                            }
                        }
                    }

                    EditorSection("Next Due") {
                        HStack(spacing: 8) {
                            DatePicker("Next due", selection: $draft.nextDueDate, displayedComponents: [.date])
                                .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        ReminderMenu(preference: $draft.notificationPreference)
                    }

                    EditorSection("Amount") {
                        TextField("Optional, like $45 or 2 bags", text: $draft.amount)
                            .padding(12)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(task == nil ? "New Recurring Task" : "Edit Recurring Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save") {
                        if let task {
                            organizerStore.updateRecurringTask(task, with: draft)
                        } else {
                            organizerStore.addRecurringTask(draft)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if task == nil { isTitleFocused = true }
            }
        }
    }
}
