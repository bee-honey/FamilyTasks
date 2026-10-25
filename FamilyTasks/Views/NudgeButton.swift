import SwiftUI

/// A bell that sends everyone else on a task a push reminding them to do it. It turns
/// yellow once they've been nudged today. Hidden when there's nobody else to nudge, or the
/// task is done.
struct NudgeButton<Item: AssignedItem>: View {
    let item: Item
    let dueDate: Date?
    var isDone = false
    var size: Font = .body
    @EnvironmentObject private var taskStore: TaskStore
    @State private var isSending = false
    @State private var nudgedToday = false
    @State private var errorMessage: String?

    var body: some View {
        // Reading familyMembers keeps the button current as people join.
        if !isDone, !taskStore.familyMembers.isEmpty, FamilyAlertService.shared.canNudge(item) {
            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else if nudgedToday {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Image(systemName: "bell")
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                .font(size)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel(nudgedToday ? "Nudged today about \(item.title)" : "Nudge about \(item.title)")
            .accessibilityHint("Sends a reminder to everyone else on this task.")
            .onAppear { nudgedToday = FamilyAlertService.shared.wasNudgedToday(item) }
            .sensoryFeedback(trigger: nudgedToday) { _, new in new ? .success : nil }
            .sensoryFeedback(trigger: errorMessage) { _, new in new == nil ? nil : .error }
            .alert("Couldn't Nudge", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() {
        isSending = true
        Task {
            do {
                let names = try await FamilyAlertService.shared.nudge(item, dueDate: dueDate)
                nudgedToday = true
                AccessibilityNotification.Announcement("Nudged \(ListFormatter.localizedString(byJoining: names))").post()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
