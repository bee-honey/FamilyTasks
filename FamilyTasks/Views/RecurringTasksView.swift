import SwiftUI

struct RecurringTasksView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var isAdding = false
    @State private var editingTask: RecurringTask?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(organizerStore.recurringTasks.sorted(by: { $0.nextDueDate < $1.nextDueDate })) { task in
                        RecurringTaskRow(task: task) {
                            editingTask = task
                        }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    editingTask = task
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(AppTheme.primary)

                                Button(role: .destructive) {
                                    organizerStore.deleteRecurringTask(task)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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
                }
            }
            .sheet(isPresented: $isAdding) {
                RecurringTaskEditorView()
            }
            .sheet(item: $editingTask) { task in
                RecurringTaskEditorView(task: task)
            }
        }
    }
}

private struct RecurringTaskRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let task: RecurringTask
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                organizerStore.markRecurringDone(task)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.footnote)
                    if !task.amount.isEmpty {
                        Text(task.amount)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Label(task.nextDueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    Text(task.frequency.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { task.isActive },
                set: { _ in organizerStore.toggleRecurringActive(task) }
            ))
            .labelsHidden()
        }
        .opacity(task.isActive ? 1 : 0.45)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}

private struct RecurringTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage("profile.email") private var profileEmail = ""
    let task: RecurringTask?
    @State private var draft: RecurringTaskDraft

    init(task: RecurringTask? = nil) {
        self.task = task
        _draft = State(initialValue: task.map(RecurringTaskDraft.init(task:)) ?? RecurringTaskDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)
                    TextField("Amount or note", text: $draft.amount)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $draft.frequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }

                    DatePicker("Next due", selection: $draft.nextDueDate, displayedComponents: [.date])

                    Picker("Assigned to", selection: $draft.assignedTo) {
                        Text("Unassigned").tag("")
                        Text("Everyone").tag(Assignee.everyone)
                        ForEach(taskStore.familyMembers, id: \.self) { member in
                            Text(member).tag(member)
                        }
                    }
                }

                Section("Notifications") {
                    NotificationPreferenceEditor(preference: $draft.notificationPreference)
                }
            }
            .navigationTitle(task == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Save" : "Update") {
                        if let task {
                            organizerStore.updateRecurringTask(task, with: draft)
                        } else {
                            organizerStore.addRecurringTask(draft)
                        }
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if task == nil {
                    applyDefaultAssigneeIfNeeded()
                }
            }
        }
    }

    private func applyDefaultAssigneeIfNeeded() {
        let email = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard draft.assignedTo.isEmpty, TaskStore.isValidEmail(email) else { return }
        taskStore.addFamilyMember(named: email)
        draft.assignedTo = email
    }
}

private struct NotificationPreferenceEditor: View {
    @Binding var preference: TaskNotificationPreference

    var body: some View {
        Toggle("Use Default Notification", isOn: $preference.usesDefaultSettings)

        if !preference.usesDefaultSettings {
            Toggle("Notify For This Task", isOn: $preference.customEnabled)

            if preference.customEnabled {
                NotificationLeadTimeSelectionList(selectedMinutes: selectedLeadMinutes)
            }
        }
    }

    private var selectedLeadMinutes: Binding<[Int]> {
        Binding(
            get: { preference.selectedLeadMinutes },
            set: { newValue in
                let normalized = NotificationLeadTimeSelectionList.normalizedLeadMinutes(newValue)
                preference.leadMinutesList = normalized
                preference.leadMinutes = normalized.first ?? 60
            }
        )
    }
}
