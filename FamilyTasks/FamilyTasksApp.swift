import SwiftUI

@main
struct FamilyTasksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var taskStore = TaskStore()
    @StateObject private var organizerStore = OrganizerStore()
    @StateObject private var calendarSync = CalendarSyncService()
    @StateObject private var sharedHouseholdStore = SharedHouseholdStore.shared
    @StateObject private var notificationScheduler = NotificationScheduler.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.isSetup") private var isProfileSetup = false
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue

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
            .environmentObject(notificationScheduler)
            .preferredColorScheme(selectedAppearance.colorScheme)
            .onAppear {
                sharedHouseholdStore.configure(taskStore: taskStore, organizerStore: organizerStore)
                notificationScheduler.configure(taskStore: taskStore, organizerStore: organizerStore)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    organizerStore.refreshShopping()
                    Task {
                        await sharedHouseholdStore.syncOnAppActivation()
                        await notificationScheduler.reschedule()
                    }
                }
            }
        }
    }

    private var isProfileReady: Bool {
        isProfileSetup && TaskStore.isValidEmail(profileEmail)
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }
}
