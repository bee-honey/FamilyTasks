import SwiftUI

struct RecurringTasksView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var isAdding = false
    @State private var editingTask: RecurringTask?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(organizerStore.visibleRecurringTasks.sorted(by: { $0.nextDueDate < $1.nextDueDate })) { task in
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
            AssigneeAvatarView(name: task.primaryAssigneeForAvatar)
                .scaleEffect(0.76)
                .frame(width: 32, height: 32)

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

                    RecurringTaskAssignmentEditor(draft: $draft, familyMembers: taskStore.familyMembers)
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

private struct RecurringTaskAssignmentEditor: View {
    @Binding var draft: RecurringTaskDraft
    let familyMembers: [String]
    @AppStorage("profile.email") private var profileEmail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Everyone", isOn: everyoneBinding)

            if !draft.assignsToEveryone {
                if TaskStore.isValidEmail(creatorEmail) {
                    Toggle(isOn: .constant(true)) {
                        assigneeLabel(for: creatorEmail, suffix: "Creator")
                    }
                    .disabled(true)
                }

                if selectableMembers.isEmpty {
                    TextField("Additional assignee emails", text: manualAssigneesBinding)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    ForEach(selectableMembers, id: \.self) { member in
                        Toggle(isOn: memberBinding(for: member)) {
                            assigneeLabel(for: member)
                        }
                    }
                }
            }

            Text(privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var everyoneBinding: Binding<Bool> {
        Binding(
            get: { draft.assignsToEveryone },
            set: { isOn in
                draft.assignsToEveryone = isOn
                if isOn {
                    draft.assignedTo = Assignee.everyone
                    draft.assignedToEmails = []
                } else {
                    ensureCreatorSelected()
                    draft.assignedTo = draft.assignedToEmails.first ?? ""
                }
            }
        )
    }

    private var manualAssigneesBinding: Binding<String> {
        Binding(
            get: {
                draft.assignedToEmails
                    .filter { $0.caseInsensitiveCompare(creatorEmail) != .orderedSame }
                    .joined(separator: ", ")
            },
            set: { rawValue in
                draft.assignsToEveryone = false
                var emails = FamilyTask.normalizedAssigneeEmails([], legacyAssignedTo: rawValue)
                if TaskStore.isValidEmail(creatorEmail), !emails.contains(where: { $0.caseInsensitiveCompare(creatorEmail) == .orderedSame }) {
                    emails.append(creatorEmail)
                    emails.sort()
                }
                draft.assignedToEmails = emails
                draft.assignedTo = emails.first ?? ""
            }
        )
    }

    private func memberBinding(for member: String) -> Binding<Bool> {
        let normalized = member.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Binding(
            get: { draft.assignedToEmails.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame } },
            set: { isSelected in
                draft.assignsToEveryone = false
                var assignees = Set(draft.assignedToEmails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                if isSelected {
                    assignees.insert(normalized)
                } else if normalized.caseInsensitiveCompare(creatorEmail) != .orderedSame {
                    assignees.remove(normalized)
                }
                if TaskStore.isValidEmail(creatorEmail) {
                    assignees.insert(creatorEmail)
                }
                draft.assignedToEmails = assignees.sorted()
                draft.assignedTo = draft.assignedToEmails.first ?? ""
            }
        )
    }

    private var privacyNote: String {
        if draft.assignsToEveryone {
            return "Everyone in your family can see this recurring task."
        }

        switch draft.assignedToEmails.count {
        case 0, 1:
            return "Only you can see this recurring task."
        case 2:
            return "Only you and the selected assignee can see this recurring task."
        default:
            return "Only you and the selected assignees can see this recurring task."
        }
    }

    private var creatorEmail: String {
        profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var selectableMembers: [String] {
        familyMembers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(creatorEmail) != .orderedSame }
    }

    private func ensureCreatorSelected() {
        guard TaskStore.isValidEmail(creatorEmail) else { return }
        if !draft.assignedToEmails.contains(where: { $0.caseInsensitiveCompare(creatorEmail) == .orderedSame }) {
            draft.assignedToEmails.append(creatorEmail)
            draft.assignedToEmails.sort()
        }
    }

    private func assigneeLabel(for member: String, suffix: String? = nil) -> some View {
        HStack(spacing: 10) {
            AssigneeAvatarView(name: member)
                .scaleEffect(0.72)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(member)
                    .lineLimit(1)
                if let suffix {
                    Text(suffix)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
