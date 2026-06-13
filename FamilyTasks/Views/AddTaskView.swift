import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage("profile.email") private var profileEmail = ""
    @State private var draft = TaskDraft()

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

                Section("Calendar") {
                    Toggle("Has due date", isOn: $draft.includeDueDate)
                    if draft.includeDueDate {
                        DatePicker("Due", selection: $draft.dueDate, in: Date()...)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        taskStore.add(draft)
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
                applyDefaultAssigneeIfNeeded()
                clampDueDateToFuture()
            }
        }
    }

    private func applyDefaultAssigneeIfNeeded() {
        let email = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard draft.assignedTo.isEmpty, TaskStore.isValidEmail(email) else { return }
        taskStore.addFamilyMember(named: email)
        draft.assignedTo = email
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
