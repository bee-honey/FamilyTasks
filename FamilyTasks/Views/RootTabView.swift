import SwiftUI

struct RootTabView: View {
    @State private var selection: AppSection? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Family Tasks") {
                    ForEach(AppSection.primarySections) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }

                Section("Settings") {
                    NavigationLink(value: AppSection.syncSettings) {
                        Label(AppSection.syncSettings.title, systemImage: AppSection.syncSettings.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)

                    NavigationLink(value: AppSection.calendarSettings) {
                        Label(AppSection.calendarSettings.title, systemImage: AppSection.calendarSettings.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)

                    NavigationLink(value: AppSection.notificationSettings) {
                        Label(AppSection.notificationSettings.title, systemImage: AppSection.notificationSettings.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)

                    NavigationLink(value: AppSection.viewSettings) {
                        Label(AppSection.viewSettings.title, systemImage: AppSection.viewSettings.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)

                    NavigationLink(value: AppSection.profile) {
                        Label(AppSection.profile.title, systemImage: AppSection.profile.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            switch selection ?? .today {
            case .today:
                TodayTasksView()
            case .matrix:
                TaskBoardView()
            case .shopping:
                ShoppingView()
            case .mealPlan:
                MealPlanView()
            case .recurring:
                RecurringTasksView()
            case .syncSettings:
                SyncSettingsView()
            case .calendarSettings:
                CalendarSettingsView()
            case .notificationSettings:
                NotificationSettingsView()
            case .viewSettings:
                ViewSettingsView()
            case .profile:
                ProfileView()
            }
        }
        .tint(AppTheme.primary)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case today
    case matrix
    case shopping
    case mealPlan
    case recurring
    case syncSettings
    case calendarSettings
    case notificationSettings
    case viewSettings
    case profile

    var id: String { rawValue }

    static var primarySections: [AppSection] {
        [.today, .matrix, .shopping, .mealPlan, .recurring]
    }

    var title: String {
        switch self {
        case .today: "Schedule"
        case .matrix: "Task Matrix"
        case .shopping: "Shopping"
        case .mealPlan: "Meal Plan"
        case .recurring: "Recurring"
        case .syncSettings: "iCloud Settings"
        case .calendarSettings: "Calendar Settings"
        case .notificationSettings: "Notification Settings"
        case .viewSettings: "View Settings"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .matrix: "square.grid.2x2"
        case .shopping: "cart"
        case .mealPlan: "fork.knife"
        case .recurring: "repeat"
        case .syncSettings: "icloud"
        case .calendarSettings: "calendar.badge.clock"
        case .notificationSettings: "bell.badge"
        case .viewSettings: "slider.horizontal.3"
        case .profile: "person.crop.circle"
        }
    }
}
