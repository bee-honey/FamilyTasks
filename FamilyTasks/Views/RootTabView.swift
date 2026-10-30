import SwiftUI

/// The sections that can be tabs. The two chosen sit between Today and Family; Family
/// lists the rest.
enum TabSection: String, CaseIterable, Identifiable {
    case tasks
    case shopping
    case mealPlan
    case chores
    case recurring
    case habits
    case ideas
    case health
    case trips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .shopping: "Shopping"
        case .mealPlan: "Meal Plan"
        case .chores: "Chores"
        case .recurring: "Recurring"
        case .habits: "Habits"
        case .ideas: "Ideas"
        case .health: "Health"
        case .trips: "Trips"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "square.grid.2x2"
        case .shopping: "cart"
        case .mealPlan: "fork.knife"
        case .chores: "star.circle"
        case .recurring: "repeat"
        case .habits: "flame"
        case .ideas: "lightbulb"
        case .health: "heart.text.square"
        case .trips: "suitcase.rolling"
        }
    }

    static let storageKey = "tabs.middle"
    static let defaultSlots: [TabSection] = [.mealPlan, .shopping]
    static let slotCount = 2

    /// The saved tabs: two different sections, filled from the defaults. Anything saved
    /// that is no longer a choice (Family, which is always a tab now) is skipped.
    static func slots(from raw: String) -> [TabSection] {
        // The earlier three-tab setting always included Family. It was saved by just
        // opening the old picker, so it's treated as never chosen: the new default applies.
        if raw.split(separator: ",").contains("family") {
            return defaultSlots
        }
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

/// The app's main navigation: Today, two chosen sections, More (the family and everything
/// else) and Settings.
struct RootTabView: View {
    /// Kept across the rebuild that follows a theme change.
    @SceneStorage("root.selectedTab") private var selection = "today"
    @AppStorage(TabSection.storageKey) private var slotsRaw = ""
    @State private var familyPath: [FamilyDestination] = []
    @ObservedObject private var toasts = ToastCenter.shared
    @ObservedObject private var navigator = AppNavigator.shared

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

            NavigationStack(path: $familyPath) {
                FamilyHubView()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag("family")

            SettingsHomeView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
        }
        .tint(AppTheme.primary)
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                ToastView(toast: toast) { toasts.dismiss() }
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .onChange(of: navigator.request) { _, request in
            guard let request else { return }
            navigator.request = nil
            open(request, slots: slots)
        }
        .onAppear {
            // The tab saved last time may no longer be in the tab bar.
            if !validTabs(slotsRaw).contains(selection) {
                selection = "today"
            }
        }
        .onChange(of: slotsRaw) { _, newValue in
            // A section taken out of the tab bar is now in Family.
            if !validTabs(newValue).contains(selection) {
                selection = "family"
            }
        }
    }

    /// A section in the tab bar opens its tab; anything else opens inside Family.
    private func open(_ destination: FamilyDestination, slots: [TabSection]) {
        if case .section(let section) = destination, slots.contains(section) {
            selection = section.rawValue
        } else {
            familyPath = [destination]
            selection = "family"
        }
    }

    private func validTabs(_ raw: String) -> [String] {
        ["today", "family", "settings"] + TabSection.slots(from: raw).map(\.rawValue)
    }
}

/// A section's screen, as a tab or pushed from Family.
struct TabSectionScreen: View {
    let section: TabSection
    var isPushed = false

    var body: some View {
        switch section {
        case .tasks: TaskBoardView(showsNavigationBar: isPushed)
        case .shopping: ShoppingView(showsNavigationBar: isPushed)
        case .mealPlan: MealPlanView(isPushed: isPushed)
        case .chores: ChoresView(isPushed: isPushed)
        case .recurring: RecurringTasksView(isPushed: isPushed)
        case .habits: HabitsView(isPushed: isPushed)
        case .ideas: IdeaNotebookView(isPushed: isPushed)
        case .health: HealthView(isPushed: isPushed)
        case .trips: TripsView(isPushed: isPushed)
        }
    }
}

/// The More tab: every section that isn't its own tab, each with a live summary.
/// The family and invites are in Settings.
struct FamilyHubView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var choreStore: ChoreStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var habitStore: HabitStore
    @EnvironmentObject private var tripStore: TripStore
    @AppStorage(TabSection.storageKey) private var slotsRaw = ""
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false

    var body: some View {
        // Shown inside the Family tab's NavigationStack.
        List {
            Section {
                ScreenHeader(eyebrow: sectionCount, title: "More")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            Section {
                ForEach(hubSections) { section in
                    NavigationLink(value: FamilyDestination.section(section)) {
                        HubRow(title: section.title, systemImage: section.systemImage, tint: tint(for: section), detail: detail(for: section))
                    }
                }
            } header: {
                SectionTitle(text: "Everything Else")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "More", isPushed: false)
        .navigationDestination(for: FamilyDestination.self) { destination in
            switch destination {
            case .section(let section): TabSectionScreen(section: section, isPushed: true)
            }
        }
    }

    private var sectionCount: String {
        "\(hubSections.count) sections"
    }

    /// Sections already in the tab bar aren't listed again.
    private var hubSections: [TabSection] {
        let tabs = TabSection.slots(from: slotsRaw)
        return TabSection.allCases.filter { !tabs.contains($0) }
    }

    private func tint(for section: TabSection) -> Color {
        switch section {
        case .tasks: AppTheme.warmAccent
        case .shopping: AppTheme.coolAccent
        case .mealPlan: AppTheme.brightAccent
        case .chores: AppTheme.softAccent
        case .recurring: AppTheme.primary
        case .habits: AppTheme.success
        case .ideas: SettingsTint.ideas
        case .health: SettingsTint.health
        case .trips: AppTheme.coolAccent
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
        case .mealPlan:
            guard let week = WeeklyIngredient.weekRange(containing: Date()) else { return "Plan the week" }
            let count = organizerStore.plannedMeals.filter { week.contains($0.date) }.count
            return count == 0 ? "Plan the week" : "\(count) \(count == 1 ? "meal" : "meals") this week"
        case .chores:
            let waiting = choreStore.waitingForApproval.count
            if waiting > 0 { return "\(waiting) to approve" }
            if choreStore.kids.isEmpty { return "Points for kids" }
            return "\(choreStore.chores.count) \(choreStore.chores.count == 1 ? "chore" : "chores")"
        case .recurring:
            let active = organizerStore.visibleRecurringTasks.filter(\.isActive)
            guard let next = active.min(by: { $0.nextDueDate < $1.nextDueDate }) else { return "Bills and routines" }
            return "\(next.title) · \(next.nextDueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        case .habits:
            let today = habitStore.myHabits(on: Date())
            if today.isEmpty {
                let count = habitStore.myHabits.count
                return count == 0 ? "Build a routine" : "None on today"
            }
            return "\(today.filter { habitStore.isDone($0) }.count) of \(today.count) done today"
        case .ideas:
            let count = organizerStore.ideaNotes.count
            return count == 0 ? "Notes for later" : "\(count) \(count == 1 ? "idea" : "ideas")"
        case .health:
            return healthSectionEnabled ? "Activity, sleep, goals and family" : "Off · tap to set up"
        case .trips:
            guard let next = tripStore.upcomingTrips.first else { return "Plan a getaway" }
            return "\(next.placeName) · \(next.phaseText())"
        }
    }
}

/// Every setting, each with a one-line summary.
private struct SettingsHomeView: View {
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @EnvironmentObject private var taskStore: TaskStore
    @State private var isShowingSharing = false
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.name") private var profileName = ""
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("calendar.integration.enabled") private var calendarEnabled = false
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue
    @ObservedObject private var notificationHistory = NotificationHistory.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    peopleRow
                } header: {
                    SectionTitle(text: "Family · \(peopleSummary)")
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(AppTheme.surface)

                Section {
                    NavigationLink { ProfileView() } label: {
                        HubRow(title: "Profile", systemImage: "person.crop.circle", tint: SettingsTint.profile, detail: profileDetail)
                    }
                    NavigationLink { SyncSettingsView() } label: {
                        HubRow(title: "Family & Sharing", systemImage: "person.2", tint: SettingsTint.iCloud, detail: sharedHouseholdStore.statusMessage)
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        HubRow(title: "Notifications", systemImage: "bell.badge", tint: SettingsTint.notifications, detail: notificationsEnabled ? "On" : "Off")
                    }
                    NavigationLink { NotificationHistoryView() } label: {
                        HubRow(title: "Notification History", systemImage: "clock.arrow.circlepath", tint: SettingsTint.notifications, detail: historyDetail)
                    }
                    NavigationLink { CalendarSettingsView() } label: {
                        HubRow(title: "Calendar", systemImage: "calendar.badge.clock", tint: SettingsTint.calendar, detail: calendarEnabled ? "Showing your calendar events" : "Off")
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
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $isShowingSharing) {
                SyncSettingsView()
            }
        }
    }

    private var members: [String] {
        let me = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let others = taskStore.familyMembers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != me }
        return (me.isEmpty ? [] : [me]) + others
    }

    private var peopleSummary: String {
        let count = members.count
        let people = count == 1 ? "1 person" : "\(count) people"
        return sharedHouseholdStore.isSharingConfigured ? "\(people) · sharing" : people
    }

    /// Everyone in the family, then Invite.
    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(members, id: \.self) { member in
                    VStack(spacing: 6) {
                        AssigneeAvatarView(name: member, size: 48, showsPhoto: false)
                        Text(member.caseInsensitiveCompare(profileEmail) == .orderedSame ? "You" : firstName(member))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(minWidth: 56)
                }
                Button {
                    isShowingSharing = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.primary.opacity(0.14), in: Circle())
                        Text("Invite")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                    .frame(minWidth: 56)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func firstName(_ email: String) -> String {
        let name = Assignee.memberName(for: email)
        return name.split(separator: " ").first.map(String.init) ?? name
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

    private var historyDetail: String {
        let count = notificationHistory.entries.count
        switch count {
        case 0: return "Nothing in the last week"
        case 1: return "1 in the last week"
        default: return "\(count) in the last week"
        }
    }

    private var appearanceDetail: String {
        "\(AppAppearance(rawValue: appearance)?.title ?? "System") · Today, tags and times"
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
