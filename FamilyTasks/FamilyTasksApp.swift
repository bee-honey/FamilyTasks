import SwiftUI

@main
struct FamilyTasksApp: App {
    @StateObject private var taskStore = TaskStore()
    @StateObject private var organizerStore = OrganizerStore()
    @StateObject private var calendarSync = CalendarSyncService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(taskStore)
                .environmentObject(organizerStore)
                .environmentObject(calendarSync)
        }
    }
}
