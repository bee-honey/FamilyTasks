import SwiftUI

struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    private var trimmedEmail: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddMember: Bool {
        TaskStore.isValidEmail(trimmedEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $name)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addMember)

                    Button(action: addMember) {
                        Label("Add Family Member", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canAddMember)

                    if !name.isEmpty && !canAddMember {
                        Label("Enter a valid email address.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                } header: {
                    Text("Add Member")
                } footer: {
                    Text("Use the Apple Account email they will accept the shared task list with.")
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isNameFocused = true
                    }
                }

                Section {
                    if taskStore.familyMembers.isEmpty {
                        Text("No members yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(taskStore.familyMembers.enumerated()), id: \.element) { index, member in
                            HStack(spacing: 10) {
                                AssigneeAvatarView(name: member)
                                    .scaleEffect(0.78)
                                    .frame(width: 32, height: 32)
                                Text(member)
                                    .lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    removeMembers(at: IndexSet(integer: index))
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onDelete(perform: removeMembers)
                    }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Removing a person here removes them from app assignees. Use iCloud Settings > Manage iCloud Share to remove their iCloud access.")
                }
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addMember() {
        guard canAddMember else { return }
        isNameFocused = false
        taskStore.addFamilyMember(named: trimmedEmail)
        name = ""
    }

    private func removeMembers(at offsets: IndexSet) {
        let removedMembers = offsets.map { taskStore.familyMembers[$0] }
        taskStore.deleteFamilyMember(at: offsets)
        removedMembers.forEach(organizerStore.clearRecurringAssignee)
    }
}
