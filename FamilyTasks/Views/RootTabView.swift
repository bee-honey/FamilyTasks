import SwiftUI

/// The sections that can sit in the tab bar between Today and More.
enum TabSection: String, CaseIterable, Identifiable {
    case tasks
    case shopping
    case mealPlan
    case family
    case chores
    case recurring
    case ideas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .shopping: "Shopping"
        case .mealPlan: "Meal Plan"
        case .family: "Family"
        case .chores: "Chores"
        case .recurring: "Recurring"
        case .ideas: "Ideas"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "square.grid.2x2"
        case .shopping: "cart"
        case .mealPlan: "fork.knife"
        case .family: "person.2"
        case .chores: "star.circle"
        case .recurring: "repeat"
        case .ideas: "lightbulb"
        }
    }

    static let storageKey = "tabs.middle"
    static let defaultSlots: [TabSection] = [.mealPlan, .shopping, .family]
    static let slotCount = 3

    /// The saved middle tabs: three different sections, filled from the defaults.
    static func slots(from raw: String) -> [TabSection] {
        var slots: [TabSection] = []
        for section in raw.split(separator: ",").compactMap({ TabSection(rawValue: String($0)) }) where !slots.contains(section) {
            slots.append(section)
        }
        for section in defaultSlots + allCases where slots.count < slotCount && !slots.contains(section) {
            slots.append(section)
        }
        return Array(slots.prefix(slotCount))
    }

    /// Puts `section` in slot `index`; if it was already in another slot, the two swap.
    static func replacing(_ slots: [TabSection], at index: Int, with section: TabSection) -> [TabSection] {
        var updated = slots
        guard updated.indices.contains(index) else { return updated }
        if let existing = updated.firstIndex(of: section) {
            updated.swapAt(existing, index)
        } else {
            updated[index] = section
        }
        return updated
    }

    static func encode(_ slots: [TabSection]) -> String {
        slots.map(\.rawValue).joined(separator: ",")
    }
}

/// The app's main navigation: Today, three chosen sections and More.
struct RootTabView: View {
    /// Kept across the rebuild that follows a theme change.
    @SceneStorage("root.selectedTab") private var selection = "today"
    @AppStorage(TabSection.storageKey) private var slotsRaw = ""

    var body: some View {
        let slots = TabSection.slots(from: slotsRaw)
        TabView(selection: $selection) {
            TodayTasksView()
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag("today")

            ForEach(slots) { section in
                NavigationStack {
                    TabSectionScreen(section: section)
                }
                .tabItem { Label(section.title, systemImage: section.systemImage) }
                .tag(section.rawValue)
            }

            MoreView(tabSections: slots)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag("more")
        }
        .tint(AppTheme.primary)
        .onAppear {
            // The tab saved last time may no longer be in the tab bar.
            let valid = ["today", "more"] + TabSection.slots(from: slotsRaw).map(\.rawValue)
            if !valid.contains(selection) {
                selection = "today"
            }
        }
        .onChange(of: slotsRaw) { _, newValue in
            // A section taken out of the tab bar can't stay selected.
            let valid = ["today", "more"] + TabSection.slots(from: newValue).map(\.rawValue)
            if !valid.contains(selection) {
                selection = "more"
            }
        }
    }
}

/// A section's screen, as a tab or pushed from More.
struct TabSectionScreen: View {
    let section: TabSection
    var isPushed = false

    var body: some View {
        switch section {
        case .tasks: TaskBoardView(showsNavigationBar: isPushed)
        case .shopping: ShoppingView(showsNavigationBar: isPushed)
        case .mealPlan: MealPlanView()
        case .family: FamilyHubView()
        case .chores: ChoresView()
        case .recurring: RecurringTasksView()
        case .ideas: IdeaNotebookView()
        }
    }
}

/// Chores, meals, recurring tasks and health, each with a live summary.
struct FamilyHubView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var choreStore: ChoreStore
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from More.
        Group {
            List {
                Section {
                    NavigationLink {
                        ChoresView()
                    } label: {
                        HubRow(title: "Chores", systemImage: "star.circle", tint: AppTheme.softAccent, detail: choresDetail)
                    }
                    NavigationLink {
                        MealPlanView()
                    } label: {
                        HubRow(title: "Meal Plan", systemImage: "fork.knife", tint: AppTheme.warmAccent, detail: mealsDetail)
                    }
                    NavigationLink {
                        RecurringTasksView()
                    } label: {
                        HubRow(title: "Recurring", systemImage: "repeat", tint: AppTheme.coolAccent, detail: recurringDetail)
                    }
                    if healthSectionEnabled {
                        NavigationLink {
                            HealthView()
                        } label: {
                            HubRow(title: "Health", systemImage: "heart.text.square", tint: SettingsTint.health, detail: "Steps and sleep")
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
    /// The sections in the tab bar; More lists the others.
    let tabSections: [TabSection]
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var taskStore: TaskStore
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
                let sections = moreSections
                if !sections.isEmpty {
                    Section {
                        ForEach(sections) { section in
                            NavigationLink {
                                TabSectionScreen(section: section, isPushed: true)
                            } label: {
                                HubRow(title: section.title, systemImage: section.systemImage, tint: tint(for: section), detail: detail(for: section))
                            }
                        }
                    }
                    .listRowBackground(AppTheme.surface)
                }

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

    /// Sections not in the tab bar. Chores, Meal Plan and Recurring also live in Family.
    private var moreSections: [TabSection] {
        [TabSection.tasks, .shopping, .family, .ideas].filter { !tabSections.contains($0) }
    }

    private func tint(for section: TabSection) -> Color {
        switch section {
        case .tasks: AppTheme.warmAccent
        case .shopping: AppTheme.coolAccent
        case .family: AppTheme.primary
        default: SettingsTint.ideas
        }
    }

    private func detail(for section: TabSection) -> String {
        switch section {
        case .tasks:
            let open = taskStore.visibleTasks.filter { !$0.isDone }.count
            return open == 1 ? "1 open task" : "\(open) open tasks"
        case .shopping:
            let toBuy = organizerStore.shoppingItems.filter { $0.isNeeded && !$0.isPurchased }.count
            return "\(toBuy) to buy"
        case .family:
            return "Chores, meals and routines"
        default:
            return ideasDetail
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
