import SwiftUI

struct RecurringTasksView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(organizerStore.recurringTasks.sorted(by: { $0.nextDueDate < $1.nextDueDate })) { task in
                        RecurringTaskRow(task: task)
                            .swipeActions(edge: .trailing) {
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
                AddRecurringTaskView()
            }
        }
    }
}

private struct RecurringTaskRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let task: RecurringTask

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
    }
}

private struct AddRecurringTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var taskStore: TaskStore
    @State private var draft = RecurringTaskDraft()

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
                        ForEach(taskStore.familyMembers, id: \.self) { member in
                            Text(member).tag(member)
                        }
                    }
                }
            }
            .navigationTitle("New Recurring")
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
                    Button("Save") {
                        organizerStore.addRecurringTask(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
