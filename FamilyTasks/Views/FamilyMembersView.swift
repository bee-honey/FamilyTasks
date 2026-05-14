import SwiftUI

struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
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
                    HStack {
                        TextField("Email", text: $name)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit(addMember)

                        Button(action: addMember) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canAddMember)
                    }
                } header: {
                    Text("Add Member")
                } footer: {
                    Text("Use the Apple Account email they will accept the shared task list with.")
                }

                Section("Family") {
                    if taskStore.familyMembers.isEmpty {
                        Text("No members yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(taskStore.familyMembers, id: \.self) { member in
                            HStack(spacing: 10) {
                                AssigneeAvatarView(name: member)
                                    .scaleEffect(0.78)
                                    .frame(width: 32, height: 32)
                                Text(member)
                            }
                        }
                        .onDelete(perform: taskStore.deleteFamilyMember)
                    }
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
}
