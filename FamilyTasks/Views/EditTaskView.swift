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
                            ForEach(taskStore.familyMembers, id: \.self) { member in
                                Text(member).tag(member)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Toggle("Urgent", isOn: $draft.isUrgent)
                    Toggle("Important", isOn: $draft.isImportant)
                }

                Section("Schedule") {
                    Toggle("Has due date", isOn: $draft.includeDueDate)
                    if draft.includeDueDate {
                        DatePicker("Due", selection: $draft.dueDate, in: Date()...)
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
