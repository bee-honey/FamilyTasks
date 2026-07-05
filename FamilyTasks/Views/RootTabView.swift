import SwiftUI

struct RootTabView: View {
    @State private var selection: AppSection? = .today
    @AppStorage("menu.primarySectionOrder") private var primarySectionOrder = AppSection.defaultPrimarySectionOrder
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Family Tasks") {
                    ForEach(primarySections) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    .onMove(perform: movePrimarySections)
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
            .safeAreaInset(edge: .bottom) {
                Text("Version: \(appVersionDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.background)
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
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
            case .ideas:
                IdeaNotebookView()
            case .health:
                HealthView()
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

    private var primarySections: [AppSection] {
        let savedSections = primarySectionOrder
            .split(separator: ",")
            .compactMap { AppSection(rawValue: String($0)) }
            .filter(\.isPrimary)

        let availableSections = AppSection.defaultPrimarySections(healthEnabled: healthSectionEnabled)
        let savedAvailableSections = savedSections.filter { availableSections.contains($0) }
        let missingSections = availableSections.filter { !savedAvailableSections.contains($0) }
        let orderedSections = savedAvailableSections + missingSections
        return orderedSections.isEmpty ? availableSections : orderedSections
    }

    private func movePrimarySections(from source: IndexSet, to destination: Int) {
        var sections = primarySections
        sections.move(fromOffsets: source, toOffset: destination)
        primarySectionOrder = sections.map(\.rawValue).joined(separator: ",")
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(version?.isEmpty == false ? version! : "1.0")(\(build?.isEmpty == false ? build! : "1"))"
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case today
    case matrix
    case shopping
    case mealPlan
    case recurring
    case ideas
    case health
    case syncSettings
    case calendarSettings
    case notificationSettings
    case viewSettings
    case profile

    var id: String { rawValue }

    static func defaultPrimarySections(healthEnabled: Bool) -> [AppSection] {
        var sections: [AppSection] = [.today, .matrix, .shopping, .mealPlan, .recurring, .ideas]
        if healthEnabled {
            sections.append(.health)
        }
        return sections
    }

    static let defaultPrimarySections = defaultPrimarySections(healthEnabled: false)
    static let defaultPrimarySectionOrder = defaultPrimarySections.map(\.rawValue).joined(separator: ",")

    var isPrimary: Bool {
        switch self {
        case .today, .matrix, .shopping, .mealPlan, .recurring, .ideas, .health:
            return true
        case .syncSettings, .calendarSettings, .notificationSettings, .viewSettings, .profile:
            return false
        }
    }

    var title: String {
        switch self {
        case .today: "Schedule"
        case .matrix: "Task Matrix"
        case .shopping: "Shopping"
        case .mealPlan: "Meal Plan"
        case .recurring: "Recurring"
        case .ideas: "Ideas"
        case .health: "Health"
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
        case .ideas: "lightbulb"
        case .health: "heart.text.square"
        case .syncSettings: "icloud"
        case .calendarSettings: "calendar.badge.clock"
        case .notificationSettings: "bell.badge"
        case .viewSettings: "slider.horizontal.3"
        case .profile: "person.crop.circle"
        }
    }
}
