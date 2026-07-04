import SwiftUI

struct EditTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    let task: FamilyTask
    @State private var draft: TaskDraft

    init(task: FamilyTask) {
        self.task = task
        _draft = State(initialValue: TaskDraft(task: task))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)

                    if taskStore.familyMembers.isEmpty {
                        TextField("Assignee email", text: $draft.assignedTo)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Assigned to", selection: $draft.assignedTo) {
                            Text("Unassigned").tag("")
                            Text("Everyone").tag(Assignee.everyone)
                            ForEach(taskStore.familyMembers, id: \.self) { member in
                                Text(member).tag(member)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Toggle(isOn: $draft.isUrgent) {
                        PriorityToggleLabel(title: "Urgent", marker: "U", color: AppTheme.warning)
                    }
                    Toggle(isOn: $draft.isImportant) {
                        PriorityToggleLabel(title: "Important", marker: "I", color: AppTheme.taskSchedule)
                    }
                }

                Section("Schedule") {
                    Toggle("Has due date", isOn: $draft.includeDueDate)
                    if draft.includeDueDate {
                        DatePicker("Due", selection: $draft.dueDate, in: Date()...)
                    }
                }

                if draft.includeDueDate {
                    Section("Notifications") {
                        NotificationPreferenceEditor(preference: $draft.notificationPreference)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        taskStore.update(task, with: draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: draft.includeDueDate) { _, includeDueDate in
                if includeDueDate {
                    clampDueDateToFuture()
                }
            }
            .onChange(of: draft.dueDate) { _, _ in
                clampDueDateToFuture()
            }
            .onAppear {
                clampDueDateToFuture()
            }
        }
    }

    private func clampDueDateToFuture() {
        guard draft.includeDueDate, draft.dueDate < Date() else { return }
        draft.dueDate = Date()
    }
}

private struct PriorityToggleLabel: View {
    let title: String
    let marker: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            TaskPriorityMarkerBadge(marker: marker, color: color)
        }
    }
}

private struct NotificationPreferenceEditor: View {
    @Binding var preference: TaskNotificationPreference

    var body: some View {
        Toggle("Use Default Notification", isOn: $preference.usesDefaultSettings)

        if !preference.usesDefaultSettings {
            Toggle("Notify For This Task", isOn: $preference.customEnabled)

            if preference.customEnabled {
                NotificationLeadTimeEditor(selectedMinutes: selectedLeadMinutes)
            }
        }
    }

    private var selectedLeadMinutes: Binding<[Int]> {
        Binding(
            get: { preference.selectedLeadMinutes },
            set: { newValue in
                let normalized = NotificationLeadTimeEditor.normalizedLeadMinutes(newValue)
                preference.leadMinutesList = normalized
                preference.leadMinutes = normalized.first ?? 60
            }
        )
    }
}
