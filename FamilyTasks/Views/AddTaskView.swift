import SwiftUI

struct AddTaskView: View {
    var body: some View {
        TaskEditorView(mode: .new)
    }
}

/// Adding and editing a task: the title, who it's for, when, and its priority.
struct TaskEditorView: View {
    enum Mode {
        case new
        case edit(FamilyTask)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage("profile.email") private var profileEmail = ""
    let mode: Mode
    @State private var draft: TaskDraft
    @State private var dueChoice: TaskDueChoice
    @State private var isChoosingLocation = false
    @FocusState private var isTitleFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new:
            var draft = TaskDraft()
            draft.dueDate = TaskDueChoice.today.dueDate() ?? draft.dueDate
            _draft = State(initialValue: draft)
            _dueChoice = State(initialValue: .today)
        case .edit(let task):
            _draft = State(initialValue: TaskDraft(task: task))
            _dueChoice = State(initialValue: TaskDueChoice.matching(task.dueDate))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What needs doing?", text: $draft.title, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isTitleFocused)
                        TextField("Add notes", text: $draft.notes, axis: .vertical)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...5)
                    }

                    EditorSection("For") {
                        AssigneePicker(draft: $draft, familyMembers: taskStore.familyMembers)
                    }

                    EditorSection("When") {
                        whenPicker
                    }

                    EditorSection("Where") {
                        locationRow
                    }

                    EditorSection("Priority") {
                        PriorityPicker(draft: $draft)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if isNew { isTitleFocused = true }
            }
            .sheet(isPresented: $isChoosingLocation) {
                LocationSearchView { location in
                    draft.location = location
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    @ViewBuilder
    private var locationRow: some View {
        if let location = draft.location {
            HStack(spacing: 12) {
                IconTile(systemImage: "mappin", tint: AppTheme.coolAccent, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let address = location.address, !address.isEmpty {
                        Text(address)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Button("Change") { isChoosingLocation = true }
                    .font(.subheadline.weight(.semibold))
                Button {
                    draft.location = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove location")
            }
            .padding(12)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Button {
                isChoosingLocation = true
            } label: {
                Label("Add Location", systemImage: "mappin.and.ellipse")
                    .labelStyle(.tile(AppTheme.coolAccent))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        switch mode {
        case .new:
            taskStore.add(draft)
        case .edit(let task):
            taskStore.update(task, with: draft)
        }
    }

    @ViewBuilder
    private var whenPicker: some View {
        WrappingStack(spacing: 8) {
            ForEach(TaskDueChoice.allCases) { choice in
                ChoiceChip(title: choice.title, isSelected: dueChoice == choice) {
                    choose(choice)
                }
            }
        }

        if draft.includeDueDate {
            HStack(spacing: 8) {
                // New tasks can't be due in the past; editing keeps an overdue date as it is.
                if isNew {
                    DatePicker("Due", selection: dueDateBinding, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                } else {
                    DatePicker("Due", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Spacer(minLength: 0)
            }

            ReminderMenu(preference: $draft.notificationPreference)
        }
    }

    /// Moving the date by hand makes it a picked date.
    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate },
            set: { newValue in
                draft.dueDate = newValue
                dueChoice = TaskDueChoice.matching(newValue)
            }
        )
    }

    private func choose(_ choice: TaskDueChoice) {
        dueChoice = choice
        switch choice {
        case .noDate:
            draft.includeDueDate = false
        case .pickDate:
            draft.includeDueDate = true
        default:
            draft.includeDueDate = true
            if let date = choice.dueDate() {
                draft.dueDate = date
            }
        }
    }
}

/// A small bold uppercase heading over a group of controls.
private struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.footnote.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? AppTheme.primary : AppTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Everyone, or specific family members (you're always included then, so the task stays
/// on your own list).
private struct AssigneePicker: View {
    @Binding var draft: TaskDraft
    let familyMembers: [String]
    @AppStorage("profile.email") private var profileEmail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    person(Assignee.everyone, name: "Everyone", isSelected: draft.assignsToEveryone) {
                        draft.assignsToEveryone = true
                        draft.assignedTo = Assignee.everyone
                        draft.assignedToEmails = []
                    }

                    if TaskStore.isValidEmail(creatorEmail) {
                        person(creatorEmail, name: "You", isSelected: !draft.assignsToEveryone) {
                            if draft.assignsToEveryone {
                                setAssignees([creatorEmail])
                            }
                        }
                    }

                    ForEach(otherMembers, id: \.self) { member in
                        person(member, name: firstName(member), isSelected: isAssigned(member)) {
                            toggle(member)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }

            Text(privacyNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func person(_ value: String, name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AssigneeAvatarView(name: value, size: 46, showsPhoto: false)
                    .padding(3)
                    .overlay(Circle().strokeBorder(isSelected ? AppTheme.primary : .clear, lineWidth: 2.5))
                Text(name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.ink : .secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var creatorEmail: String {
        profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var otherMembers: [String] {
        familyMembers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != creatorEmail }
    }

    private func firstName(_ email: String) -> String {
        let name = Assignee.memberName(for: email)
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private func isAssigned(_ member: String) -> Bool {
        !draft.assignsToEveryone && draft.assignedToEmails.contains { $0.caseInsensitiveCompare(member) == .orderedSame }
    }

    private func toggle(_ member: String) {
        var assignees = draft.assignsToEveryone ? Set<String>() : Set(draft.assignedToEmails.map { $0.lowercased() })
        if assignees.contains(member) {
            assignees.remove(member)
        } else {
            assignees.insert(member)
        }
        setAssignees(assignees)
    }

    private func setAssignees(_ members: Set<String>) {
        var assignees = members
        if TaskStore.isValidEmail(creatorEmail) {
            assignees.insert(creatorEmail)
        }
        draft.assignsToEveryone = false
        draft.assignedToEmails = assignees.sorted()
        draft.assignedTo = draft.assignedToEmails.first ?? ""
    }

    private var privacyNote: String {
        if draft.assignsToEveryone {
            return "Everyone in your family sees this task."
        }

        // Tasks still sync to every device in the family share; other members' apps just
        // don't list them, so describe it as "shown to" rather than "can see".
        let others = draft.assignedToEmails.filter { $0.caseInsensitiveCompare(creatorEmail) != .orderedSame }
        switch others.count {
        case 0: return "Shown only to you in Family Tasks."
        case 1: return "Shown only to you and \(firstName(others[0])) in Family Tasks."
        default: return "Shown only to you and \(others.count) others in Family Tasks."
        }
    }
}

/// Do now / Schedule / Delegate / Someday, which set the task's urgent and important flags.
private struct PriorityPicker: View {
    @Binding var draft: TaskDraft

    var body: some View {
        let selected = TaskBucket(urgent: draft.isUrgent, important: draft.isImportant)
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(TaskBucket.allCases) { bucket in
                    let isSelected = bucket == selected
                    Button {
                        let flags = bucket.flags
                        draft.isUrgent = flags.urgent
                        draft.isImportant = flags.important
                    } label: {
                        Text(bucket.tagTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(bucket.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(bucket.accentColor.opacity(isSelected ? 0.24 : 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? bucket.accentColor : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Text(selected.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The task's reminder: the default from notification settings, none, or one lead time.
private struct ReminderMenu: View {
    @Binding var preference: TaskNotificationPreference

    private static let quickChoices = [15, 30, 60, 120, 1_440]

    var body: some View {
        Menu {
            Button("Default reminder") {
                preference.usesDefaultSettings = true
            }
            Button("No reminder") {
                preference.usesDefaultSettings = false
                preference.customEnabled = false
            }
            Divider()
            ForEach(Self.quickChoices.filter(Self.isValid), id: \.self) { minutes in
                Button(Self.title(for: minutes)) {
                    preference.usesDefaultSettings = false
                    preference.customEnabled = true
                    preference.leadMinutes = minutes
                    preference.leadMinutesList = [minutes]
                }
            }
        } label: {
            Label(summary, systemImage: "bell")
                .font(.subheadline)
        }
    }

    private var summary: String {
        if preference.usesDefaultSettings { return "Default reminder" }
        if !preference.customEnabled { return "No reminder" }
        let minutes = preference.selectedLeadMinutes
        if minutes.count == 1, let only = minutes.first {
            return "Remind \(Self.title(for: only).lowercased())"
        }
        return "\(minutes.count) reminders (custom)"
    }

    private static func isValid(_ minutes: Int) -> Bool {
        NotificationLeadTimeOption.options.contains { $0.minutes == minutes }
    }

    private static func title(for minutes: Int) -> String {
        NotificationLeadTimeOption.options.first { $0.minutes == minutes }?.title ?? "\(minutes) minutes before"
    }
}
