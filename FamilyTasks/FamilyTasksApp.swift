import SwiftUI

@main
struct FamilyTasksApp: App {
    @StateObject private var taskStore = TaskStore()
    @StateObject private var organizerStore = OrganizerStore()
    @StateObject private var calendarSync = CalendarSyncService()
    @Environment(\.scenePhase) private var scenePhase
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    organizerStore.refreshShopping()
                }
            }
        }
    }

    private var isProfileReady: Bool {
        isProfileSetup && TaskStore.isValidEmail(profileEmail)
    }
}
