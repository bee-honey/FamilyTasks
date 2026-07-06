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
    @AppStorage("health.share.enabled") private var healthSharingEnabled = false

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
                HealthSyncCoordinator.shared.scheduleDailyRefresh()
            }
            .onChange(of: healthSharingEnabled) { _, enabled in
                if enabled {
                    HealthSyncCoordinator.shared.scheduleDailyRefresh()
                    Task {
                        await HealthSyncCoordinator.shared.syncNow(
                            taskStore: taskStore,
                            organizerStore: organizerStore,
                            sharedHouseholdStore: sharedHouseholdStore
                        )
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    organizerStore.refreshShopping()
                    Task {
                        await sharedHouseholdStore.syncOnAppActivation()
                        await HealthSyncCoordinator.shared.syncIfNeeded(
                            taskStore: taskStore,
                            organizerStore: organizerStore,
                            sharedHouseholdStore: sharedHouseholdStore
                        )
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
