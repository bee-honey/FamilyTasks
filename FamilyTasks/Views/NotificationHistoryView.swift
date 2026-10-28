import SwiftUI

/// The last week's notifications, newest first, grouped by day.
struct NotificationHistoryView: View {
    @ObservedObject private var history = NotificationHistory.shared
    @State private var isConfirmingClear = false

    var body: some View {
        // Shown inside a tab's NavigationStack.
        List {
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Notifications", systemImage: "bell.slash")
                } description: {
                    Text("Notifications from the last week show up here.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        row(entry)
                            .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    SectionTitle(text: Self.dayTitle(group.day))
                }
            }

            if !history.entries.isEmpty {
                Section {
                } footer: {
                    Text("Kept for a week. A notification you clear before opening the app may not appear.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Notification History")
        .toolbar {
            if !history.entries.isEmpty {
                Button("Clear") { isConfirmingClear = true }
            }
        }
        .confirmationDialog("Clear notification history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .task {
            await history.collectDelivered()
        }
    }

    private func row(_ entry: NotificationHistory.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: entry.kind.systemImage, tint: tint(for: entry.kind), size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func tint(for kind: NotificationHistory.Kind) -> Color {
        switch kind {
        case .dailyList: AppTheme.warning
        case .dueSoon, .recurringDueSoon: AppTheme.taskSchedule
        case .shopping: AppTheme.coolAccent
        case .nudge: AppTheme.warmAccent
        case .assigned, .updated: AppTheme.primary
        case .completed: AppTheme.success
        case .habit: AppTheme.goldAccent
        case .other: AppTheme.softAccent
        }
    }

    private var days: [(day: Date, entries: [NotificationHistory.Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    /// "Today", "Yesterday", or "Tuesday, Oct 13".
    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
