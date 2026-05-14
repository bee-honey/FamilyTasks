import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
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

                Section("Calendar") {
                    Toggle("Has due date", isOn: $draft.includeDueDate)
                    if draft.includeDueDate {
                        DatePicker("Due", selection: $draft.dueDate)
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
        }
    }
}
