import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @State private var isAddingTask = false
    @State private var syncingTaskID: FamilyTask.ID?
    @State private var editingTask: FamilyTask?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(TaskBucket.allCases) { bucket in
                        BucketView(
                            bucket: bucket,
                            tasks: taskStore.tasks(in: bucket),
                            syncingTaskID: syncingTaskID,
                            onMove: { task, target in taskStore.move(task, to: target) },
                            onDone: taskStore.markDone,
                            onDelete: taskStore.delete,
                            onSync: syncToCalendar,
                            onEdit: { editingTask = $0 }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 76)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                addTaskButton
                    .padding(.bottom, 6)
            }
            .navigationTitle("Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isAddingTask) {
                AddTaskView()
            }
            .sheet(item: $editingTask) { task in
                EditTaskView(task: task)
            }
            .alert("Calendar Sync", isPresented: Binding(
                get: { calendarSync.lastErrorMessage != nil },
                set: { if !$0 { calendarSync.lastErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(calendarSync.lastErrorMessage ?? "")
            }
        }
    }

    private var addTaskButton: some View {
        Button {
            isAddingTask = true
        } label: {
            Label("New Task", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppTheme.primary, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
    }

    private func syncToCalendar(_ task: FamilyTask) {
        syncingTaskID = task.id
        Task {
            do {
                let identifier = try await calendarSync.sync(task)
                taskStore.setCalendarEventIdentifier(identifier, for: task)
            } catch {
                calendarSync.lastErrorMessage = error.localizedDescription
            }
            syncingTaskID = nil
        }
    }
}
