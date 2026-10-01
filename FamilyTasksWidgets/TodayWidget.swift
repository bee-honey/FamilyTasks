import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let due: [WidgetSnapshot.TaskRow]
    let overdue: [WidgetSnapshot.TaskRow]

    var openCount: Int { due.count + overdue.count }

    static let sample = TodayEntry(
        date: Date(),
        due: [
            WidgetSnapshot.TaskRow(id: UUID(), title: "Book pediatrician appointment", dueDate: Date(), isUrgent: true, isImportant: true),
            WidgetSnapshot.TaskRow(id: UUID(), title: "Plan school lunches", dueDate: Date(), isUrgent: false, isImportant: true)
        ],
        overdue: []
    )
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? .sample : entry(for: Date(), from: loadSnapshot()))
    }

    /// One entry now and one at each of the next seven midnights, so the list moves
    /// on to the next day even if the app is not opened.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let calendar = Calendar.current
        let now = Date()
        var dates = [now]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.append(next)
            day = next
        }
        completion(Timeline(entries: dates.map { entry(for: $0, from: snapshot) }, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        WidgetStorage.shared?.loadSnapshot() ?? WidgetSnapshot()
    }

    private func entry(for date: Date, from snapshot: WidgetSnapshot) -> TodayEntry {
        let tasks = snapshot.tasks(for: date)
        return TodayEntry(date: date, due: tasks.due, overdue: tasks.overdue)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FamilyTasksToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your tasks for today. Tap a circle to mark one done.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checklist")
                        .font(.caption)
                    Text("\(entry.openCount)")
                        .font(.title3.weight(.semibold))
                }
            }
        case .accessoryInline:
            Text(entry.openCount == 0 ? "All done today" : "\(entry.openCount) \(entry.openCount == 1 ? "task" : "tasks") today")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Today · \(entry.openCount)")
                    .font(.headline)
                if entry.openCount == 0 {
                    Text("All done")
                } else {
                    ForEach(rows.prefix(2)) { row in
                        Text(row.task.title)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            listView
        }
    }

    private var listView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                if entry.openCount > 0 {
                    Text("\(entry.openCount)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.openCount == 0 {
                Spacer()
                Label("All done for today", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows.prefix(maxRows)) { row in
                    TaskRowView(row: row)
                }
                if rows.count > maxRows {
                    Text("+\(rows.count - maxRows) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rows: [DisplayedTask] {
        entry.overdue.map { DisplayedTask(task: $0, isOverdue: true) } + entry.due.map { DisplayedTask(task: $0, isOverdue: false) }
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        default: 9
        }
    }
}

private struct DisplayedTask: Identifiable {
    let task: WidgetSnapshot.TaskRow
    let isOverdue: Bool
    var id: UUID { task.id }
}

private struct TaskRowView: View {
    let row: DisplayedTask

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: CompleteTaskIntent(taskID: row.task.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(row.task.isUrgent && row.task.isImportant ? .red : .secondary)
            }
            .buttonStyle(.plain)

            Text(row.task.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 0)

            if row.isOverdue {
                Text(row.task.dueDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview("Today", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry.sample
    TodayEntry(date: Date(), due: [], overdue: [])
}

#Preview("Today, Lock Screen", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry.sample
}
