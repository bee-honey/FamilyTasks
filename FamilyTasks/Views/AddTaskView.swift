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
                    TaskAssignmentEditor(draft: $draft, familyMembers: taskStore.familyMembers)
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

                if draft.includeDueDate {
                    Section("Notifications") {
                        NotificationPreferenceEditor(preference: $draft.notificationPreference)
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

struct TaskAssignmentEditor: View {
    @Binding var draft: TaskDraft
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
            return "Everyone in your family can see this task."
        }

        switch draft.assignedToEmails.count {
        case 0:
            return "Only you can see this task."
        case 1:
            return "Only you can see this task."
        case 2:
            return "Only you and the selected assignee can see this task."
        default:
            return "Only you and the selected assignees can see this task."
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
