import SwiftUI

@main
struct FamilyTasksApp: App {
    @StateObject private var taskStore = TaskStore()
    @StateObject private var organizerStore = OrganizerStore()
    @StateObject private var calendarSync = CalendarSyncService()
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.isSetup") private var isProfileSetup = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isProfileReady {
                    RootTabView()
                } else {
                    ProfileSetupView()
                }
            }
            .environmentObject(taskStore)
            .environmentObject(organizerStore)
            .environmentObject(calendarSync)
        }
    }

    private var isProfileReady: Bool {
        isProfileSetup && TaskStore.isValidEmail(profileEmail)
    }
}
