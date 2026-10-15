import SwiftUI

/// A bell that sends everyone else on a task a push reminding them to do it. Hidden when
/// there's nobody else to nudge, or the task is done.
struct NudgeButton<Item: AssignedItem>: View {
    let item: Item
    let dueDate: Date?
    var isDone = false
    var size: Font = .body
    @EnvironmentObject private var taskStore: TaskStore
    @State private var state = SendState.idle
    @State private var errorMessage: String?

    private enum SendState: Equatable {
        case idle
        case sending
        case sent
    }

    var body: some View {
        // Reading familyMembers keeps the button current as people join.
        if !isDone, !taskStore.familyMembers.isEmpty, FamilyAlertService.shared.canNudge(item) {
            Button(action: send) {
                Group {
                    switch state {
                    case .idle:
                        Image(systemName: "bell")
                            .foregroundStyle(AppTheme.warning)
                    case .sending:
                        ProgressView()
                            .controlSize(.small)
                    case .sent:
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(AppTheme.success)
                    }
                }
                .font(size)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state != .idle)
            .accessibilityLabel(state == .sent ? "Nudge sent" : "Nudge about \(item.title)")
            .accessibilityHint("Sends a reminder to everyone else on this task.")
            .sensoryFeedback(trigger: state) { _, new in new == .sent ? .success : nil }
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
        state = .sending
        Task {
            do {
                let names = try await FamilyAlertService.shared.nudge(item, dueDate: dueDate)
                state = .sent
                AccessibilityNotification.Announcement("Nudged \(ListFormatter.localizedString(byJoining: names))").post()
                try? await Task.sleep(for: .seconds(3))
                state = .idle
            } catch {
                state = .idle
                errorMessage = error.localizedDescription
            }
        }
    }
}
