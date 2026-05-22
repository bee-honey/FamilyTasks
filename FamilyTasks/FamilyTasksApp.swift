import SwiftUI

@main
struct FamilyTasksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var taskStore = TaskStore()
    @StateObject private var organizerStore = OrganizerStore()
    @StateObject private var calendarSync = CalendarSyncService()
    @StateObject private var sharedHouseholdStore = SharedHouseholdStore.shared
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
            .environmentObject(sharedHouseholdStore)
            .onAppear {
                sharedHouseholdStore.configure(taskStore: taskStore, organizerStore: organizerStore)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    organizerStore.refreshShopping()
                    Task {
                        await sharedHouseholdStore.syncOnAppActivation()
                    }
                }
            }
        }
    }

    private var isProfileReady: Bool {
        isProfileSetup && TaskStore.isValidEmail(profileEmail)
    }
}
