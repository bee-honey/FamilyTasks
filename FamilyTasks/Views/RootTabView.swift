import SwiftUI

/// The app's main navigation: the busiest sections as tabs, the rest one level down
/// under Family and More.
struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            TodayTasksView()
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(AppTab.today)

            TaskBoardView()
                .tabItem { Label("Tasks", systemImage: "square.grid.2x2") }
                .tag(AppTab.tasks)

            ShoppingView()
                .tabItem { Label("Shopping", systemImage: "cart") }
                .tag(AppTab.shopping)

            FamilyHubView()
                .tabItem { Label("Family", systemImage: "person.2") }
                .tag(AppTab.family)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(AppTab.more)
        }
        .tint(AppTheme.primary)
    }
}

private enum AppTab: Hashable {
    case today
    case tasks
    case shopping
    case family
    case more
}

/// Chores, meals, recurring tasks and health, each with a live summary.
private struct FamilyHubView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var choreStore: ChoreStore
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ChoresView()
                    } label: {
                        HubRow(title: "Chores", systemImage: "star.circle", tint: AppTheme.avatarPalette[1], detail: choresDetail)
                    }
                    NavigationLink {
                        MealPlanView()
                    } label: {
                        HubRow(title: "Meal Plan", systemImage: "fork.knife", tint: AppTheme.avatarPalette[2], detail: mealsDetail)
                    }
                    NavigationLink {
                        RecurringTasksView()
                    } label: {
                        HubRow(title: "Recurring", systemImage: "repeat", tint: AppTheme.success, detail: recurringDetail)
                    }
                    if healthSectionEnabled {
                        NavigationLink {
                            HealthView()
                        } label: {
                            HubRow(title: "Health", systemImage: "heart.text.square", tint: AppTheme.destructive, detail: "Steps and sleep")
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Family")
        }
    }

    private var choresDetail: String {
        let waiting = choreStore.waitingForApproval.count
        if waiting > 0 { return "\(waiting) to approve" }
        if choreStore.kids.isEmpty { return "Points for kids" }
        return "\(choreStore.chores.count) \(choreStore.chores.count == 1 ? "chore" : "chores")"
    }

    private var mealsDetail: String {
        guard let week = WeeklyIngredient.weekRange(containing: Date()) else { return "Plan the week" }
        let count = organizerStore.plannedMeals.filter { week.contains($0.date) }.count
        return count == 0 ? "Plan the week" : "\(count) \(count == 1 ? "meal" : "meals") this week"
    }

    private var recurringDetail: String {
        let active = organizerStore.visibleRecurringTasks.filter(\.isActive)
        guard let next = active.min(by: { $0.nextDueDate < $1.nextDueDate }) else { return "Bills and routines" }
        return "\(next.title) · \(next.nextDueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }
}

/// Ideas and every setting, each with a one-line summary.
private struct MoreView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.name") private var profileName = ""
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("calendar.integration.enabled") private var calendarEnabled = false
    @AppStorage("health.section.enabled") private var healthEnabled = false
    @AppStorage("health.share.enabled") private var healthSharing = false
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        IdeaNotebookView()
                    } label: {
                        HubRow(title: "Ideas", systemImage: "lightbulb", tint: SettingsTint.ideas, detail: ideasDetail)
                    }
                }
                .listRowBackground(AppTheme.surface)

                Section("Settings") {
                    NavigationLink { ProfileView() } label: {
                        HubRow(title: "Profile", systemImage: "person.crop.circle", tint: SettingsTint.profile, detail: profileDetail)
                    }
                    NavigationLink { SyncSettingsView() } label: {
                        HubRow(title: "iCloud Sharing", systemImage: "icloud", tint: SettingsTint.iCloud, detail: sharedHouseholdStore.statusMessage)
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        HubRow(title: "Notifications", systemImage: "bell.badge", tint: SettingsTint.notifications, detail: notificationsEnabled ? "On" : "Off")
                    }
                    NavigationLink { CalendarSettingsView() } label: {
                        HubRow(title: "Calendar", systemImage: "calendar.badge.clock", tint: SettingsTint.calendar, detail: calendarEnabled ? "Showing your calendar events" : "Off")
                    }
                    NavigationLink { HealthSettingsView() } label: {
                        HubRow(title: "Health", systemImage: "heart", tint: SettingsTint.health, detail: healthDetail)
                    }
                    NavigationLink { ViewSettingsView() } label: {
                        HubRow(title: "Appearance", systemImage: "paintbrush", tint: SettingsTint.appearance, detail: appearanceDetail)
                    }
                }
                .listRowBackground(AppTheme.surface)

                Section {
                } footer: {
                    Text("Version \(appVersionDisplay)")
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("More")
        }
    }

    private var profileDetail: String {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name.isEmpty, email.isEmpty) {
        case (false, false): return "\(name) · \(email)"
        case (true, false): return email
        default: return "Set up your profile"
        }
    }

    private var healthDetail: String {
        guard healthEnabled else { return "Off" }
        return healthSharing ? "Sharing steps and sleep with family" : "On, not shared"
    }

    private var appearanceDetail: String {
        "\(AppAppearance(rawValue: appearance)?.title ?? "System") · Today, tags and times"
    }

    private var ideasDetail: String {
        let count = organizerStore.ideaNotes.count
        return count == 0 ? "Notes for later" : "\(count) \(count == 1 ? "idea" : "ideas")"
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(version?.isEmpty == false ? version! : "1.0") (\(build?.isEmpty == false ? build! : "1"))"
    }
}

private struct HubRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
