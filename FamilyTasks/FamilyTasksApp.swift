import SwiftUI

@main
struct FamilyTasksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var taskStore = TaskStore.shared
    @StateObject private var organizerStore = OrganizerStore.shared
    @StateObject private var choreStore = ChoreStore.shared
    @StateObject private var habitStore = HabitStore.shared
    @StateObject private var healthGoalStore = HealthGoalStore.shared
    @StateObject private var tripStore = TripStore.shared
    @StateObject private var budgetStore = BudgetStore.shared
    @StateObject private var calendarSync = CalendarSyncService()
    @StateObject private var sharedHouseholdStore = SharedHouseholdStore.shared
    @StateObject private var notificationScheduler = NotificationScheduler.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.isSetup") private var isProfileSetup = false
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(ThemePalette.storageKey) private var themeID = ThemePalette.defaultTheme.id
    @AppStorage("health.share.enabled") private var healthSharingEnabled = false

    /// Ideas saved from other apps' share sheets since the app was last open.
    private func takeSharedIdeas() {
        let added = organizerStore.takeSharedIdeas(from: IdeaInbox.shared)
        guard let first = added.first else { return }
        let message = added.count == 1 ? "Saved “\(first.title)” to Ideas" : "\(added.count) ideas saved to Ideas"
        ToastCenter.shared.show(message, systemImage: "lightbulb.fill", actionTitle: "View") {
            AppNavigator.shared.open(.section(.ideas))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isProfileReady {
                    // Screens read theme colors as they draw, so rebuild them when the theme changes.
                    RootTabView()
                        .id(themeID)
                } else {
                    ProfileSetupView()
                }
            }
            .environmentObject(taskStore)
            .environmentObject(organizerStore)
            .environmentObject(choreStore)
            .environmentObject(habitStore)
            .environmentObject(healthGoalStore)
            .environmentObject(tripStore)
            .environmentObject(budgetStore)
            .environmentObject(calendarSync)
            .environmentObject(sharedHouseholdStore)
            .environmentObject(notificationScheduler)
            .preferredColorScheme(selectedAppearance.colorScheme)
            .onAppear {
                calendarSync.configure(taskStore: taskStore)
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
                    WidgetBridge.shared.applyPendingActions()
                    takeSharedIdeas()
                    FamilyTasksShortcuts.updateAppShortcutParameters()
                    Task {
                        await FamilyAlertService.shared.refresh()
                    }
                    Task {
                        await NotificationHistory.shared.collectDelivered()
                    }
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
