import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.name") private var name = ""
    @AppStorage("profile.initials") private var initials = ""
    @AppStorage("profile.imageData") private var imageData = Data()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section {
                    HStack(spacing: 16) {
                        profileImage

                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayInitials)
                                .font(.title3.weight(.semibold))
                            Text(email.isEmpty ? "No email set" : email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 6)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Profile Image", systemImage: "photo")
                    }

                    if !imageData.isEmpty {
                        Button(role: .destructive) {
                            imageData = Data()
                            syncProfileMember()
                        } label: {
                            Label("Remove Profile Image", systemImage: "trash")
                        }
                    }
                }

                Section {
                    TextField("Name (for greetings)", text: $name)
                        .textInputAutocapitalization(.words)
                        .textContentType(.givenName)

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(syncProfileMember)

                    TextField("Initials", text: $initials)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: initials) { _, newValue in
                            initials = String(newValue.prefix(3)).uppercased()
                        }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Family sharing uses this email for in-app assignees. Apple does not share invite recipients' iMessage address or phone number with the app.")
                }

            }
            .navigationTitle("Profile")
            .labelStyle(.tile(SettingsTint.profile))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        imageData = SharedMemberProfile.compressedImageData(from: data) ?? data
                        syncProfileMember()
                    }
                }
            }
            .onDisappear(perform: syncProfileMember)
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        } else {
            Text(displayInitials)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(AppTheme.primary, in: Circle())
        }
    }

    private var displayInitials: String {
        let trimmedInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInitials.isEmpty {
            return trimmedInitials.uppercased()
        }

        let localPart = email.split(separator: "@").first.map(String.init) ?? ""
        let parts = localPart.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == " " })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }

    private func syncProfileMember() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard TaskStore.isValidEmail(trimmedEmail) else { return }

        if trimmedEmail != email {
            email = trimmedEmail
        }

        taskStore.addFamilyMember(named: trimmedEmail)
        if let currentProfile = SharedMemberProfile.currentProfile() {
            SharedMemberProfile.mergeAndSave([currentProfile])
        }

        guard sharedHouseholdStore.isSharingConfigured else { return }
        Task {
            await sharedHouseholdStore.uploadNow()
        }
    }
}

struct ViewSettingsView: View {
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("schedule.showTaskTime") private var showTaskTime = true
    @AppStorage("schedule.showPriorityTags") private var showPriorityTags = true
    @AppStorage("schedule.defaultDisplayMode") private var defaultScheduleView = ScheduleDisplayMode.week.rawValue
    @AppStorage("schedule.taskSortOrder") private var taskSortOrder = ScheduleTaskSortOrder.priority.rawValue
    @AppStorage("tasks.showPriorityMarkers") private var showTaskPriorityMarkers = false
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(ThemePalette.storageKey) private var themeID = ThemePalette.defaultTheme.id
    @AppStorage(TabSection.storageKey) private var tabSlotsRaw = ""
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage(TodaySection.storageKey) private var sectionOrderRaw = ""
    @AppStorage(TodaySection.legacyPriorityKey) private var legacyPriorityRaw = ""
    @AppStorage(TodaySection.showHabitsKey) private var showHabits = true
    @AppStorage(TodayKind.colorCodeKey) private var colorCodeToday = true

    private func tabSlotBinding(_ index: Int) -> Binding<TabSection> {
        Binding(
            get: { TabSection.slots(from: tabSlotsRaw)[index] },
            set: { section in
                tabSlotsRaw = TabSection.encode(TabSection.replacing(TabSection.slots(from: tabSlotsRaw), at: index, with: section))
            }
        )
    }

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section("Appearance") {
                    Picker("Mode", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("System follows the iPhone appearance setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(ThemePalette.all) { theme in
                            ThemeCard(theme: theme, isSelected: theme.id == ThemePalette.named(themeID).id) {
                                themeID = theme.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Theme")
                } footer: {
                    Text(ThemePalette.named(themeID).summary)
                }

                Section {
                    ForEach(0..<TabSection.slotCount, id: \.self) { index in
                        Picker(selection: tabSlotBinding(index)) {
                            ForEach(TabSection.allCases) { section in
                                Label(section.title, systemImage: section.systemImage).tag(section)
                            }
                        } label: {
                            Label("Tab \(index + 2)", systemImage: TabSection.slots(from: tabSlotsRaw)[index].systemImage)
                                .labelStyle(.tile(AppTheme.primary))
                        }
                    }
                    Button("Reset to Default") {
                        tabSlotsRaw = TabSection.encode(TabSection.defaultSlots)
                    }
                    .disabled(TabSection.slots(from: tabSlotsRaw) == TabSection.defaultSlots)
                } header: {
                    Text("Tab Bar")
                } footer: {
                    Text("Today, Family and Settings always stay. Picking a section already in the other tab swaps them; everything not in the tab bar is in Family.")
                }

                Section("Today") {
                    Picker(selection: $defaultScheduleView) {
                        ForEach(ScheduleDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    } label: {
                        Label("Default View", systemImage: "calendar")
                            .labelStyle(.tile(AppTheme.primary))
                    }

                    Picker(selection: $taskSortOrder) {
                        ForEach(ScheduleTaskSortOrder.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        Label("Task Sort", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.tile(AppTheme.taskSchedule))
                    }

                    Toggle(isOn: $showPriorityTags) {
                        Label("Show Priority Tags", systemImage: "tag.fill")
                            .labelStyle(.tile(AppTheme.taskDo))
                    }
                    Toggle(isOn: $showTaskTime) {
                        Label("Show Times", systemImage: "clock.fill")
                            .labelStyle(.tile(AppTheme.warning))
                    }
                    Toggle(isOn: $showHabits) {
                        Label("Show Habits on Today", systemImage: "flame.fill")
                            .labelStyle(.tile(AppTheme.success))
                    }
                    Toggle(isOn: $colorCodeToday) {
                        Label("Color-Code Today", systemImage: "paintpalette.fill")
                            .labelStyle(.tile(AppTheme.softAccent))
                    }
                }

                Section {
                    let order = TodaySection.order(from: sectionOrderRaw, legacyPriority: legacyPriorityRaw)
                    ForEach(Array(order.enumerated()), id: \.element) { index, section in
                        HStack(spacing: 12) {
                            Label(section.title, systemImage: section.systemImage)
                                .labelStyle(.tile(AppTheme.taskSchedule))
                            Spacer()
                            orderButton("arrow.up", label: "Move \(section.title) up", disabled: index == 0) {
                                sectionOrderRaw = TodaySection.encode(TodaySection.moving(section, .up, in: order))
                            }
                            orderButton("arrow.down", label: "Move \(section.title) down", disabled: index == order.count - 1) {
                                sectionOrderRaw = TodaySection.encode(TodaySection.moving(section, .down, in: order))
                            }
                        }
                    }
                } header: {
                    Text("Order on Today")
                } footer: {
                    Text("You can also move a block from the arrows on its heading on Today.")
                }

                Section("Task Matrix") {
                    Toggle(isOn: $showTaskPriorityMarkers) {
                        Label("Show Bucket Markers", systemImage: "square.grid.2x2.fill")
                            .labelStyle(.tile(AppTheme.success))
                    }
                }

                Section("Tasks and Calendars") {
                    Toggle(isOn: $calendarIntegrationEnabled) {
                        Label("Show Calendar Events on Today", systemImage: "calendar.badge.plus")
                            .labelStyle(.tile(SettingsTint.calendar))
                    }
                        .onChange(of: calendarIntegrationEnabled) { _, enabled in
                            Task {
                                if enabled {
                                    let connected = await calendarSync.requestFullAccessForReadingIfNeeded()
                                    calendarIntegrationEnabled = connected
                                    if connected {
                                        await calendarSync.loadTodayEvents()
                                    }
                                } else {
                                    calendarSync.clearTodayEvents()
                                }
                            }
                        }
                }
            }
            .navigationTitle("Appearance")
            .labelStyle(.tile(SettingsTint.appearance))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }

    private func orderButton(_ systemImage: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy, action)
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(AppTheme.surfaceMuted, in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct HealthSettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @StateObject private var healthService = HealthMetricsService()
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false
    @AppStorage("health.share.enabled") private var healthSharingEnabled = false
    @AppStorage(HealthSyncCoordinator.shareHeartKey) private var shareHeart = false
    @AppStorage(HealthSyncCoordinator.shareBodyKey) private var shareBody = false
    @AppStorage(WindDownSettings.dailyTipKey) private var dailyTip = false
    @AppStorage(WindDownSettings.dailyTipHourKey) private var dailyTipHour = WindDownSettings.defaultTipHour
    @AppStorage(WindDownSettings.dailyTipMinuteKey) private var dailyTipMinute = 0
    @AppStorage(WindDownSettings.enabledKey) private var windDownEnabled = false
    @AppStorage(WindDownStep.food.settingsKey) private var windDownFood = true
    @AppStorage(WindDownStep.drinks.settingsKey) private var windDownDrinks = true
    @AppStorage(WindDownStep.screens.settingsKey) private var windDownScreens = true
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @State private var isShowingDataList = false

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section("Health") {
                    Toggle(isOn: $healthSectionEnabled) {
                        Label("Enable Health", systemImage: "heart.fill")
                            .labelStyle(.tile(SettingsTint.health))
                    }
                        .disabled(!healthService.isHealthAvailable)
                        .onChange(of: healthSectionEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    await healthService.requestAccessAndRefresh()
                                    HealthSyncCoordinator.shared.scheduleDailyRefresh()
                                }
                            } else {
                                healthSharingEnabled = false
                            }
                        }

                    Text(healthSectionEnabled ? "Your activity, sleep, heart and body numbers show in More → Health once Health access is allowed." : "Turn on to see activity, sleep score, heart and BMI in More → Health. You'll be asked for Health access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if healthSectionEnabled {
                    Section {
                        DisclosureGroup(isExpanded: $isShowingDataList) {
                            ForEach(HealthDataKind.allCases) { kind in
                                dataRow(kind)
                            }
                        } label: {
                            HStack {
                                Label("Data Arriving", systemImage: "checklist")
                                Spacer(minLength: 8)
                                Text(receivingSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            openHealthApp()
                        } label: {
                            Label("Open the Health App", systemImage: "heart.text.square")
                        }
                    } header: {
                        Text("Data From Health")
                    } footer: {
                        Text("iOS doesn't let apps see which Health permissions you allowed, only the data that arrives. If something you allowed shows No Data, nothing has recorded it in the last few weeks. To change access: Health app → your picture → Apps → Family Tasks.")
                    }

                    Section {
                        Toggle(isOn: $healthSharingEnabled) {
                            Label("Share With Family", systemImage: "person.2.fill")
                                .labelStyle(.tile(AppTheme.primary))
                        }
                            .disabled(!healthService.isHealthAvailable)
                            .onChange(of: healthSharingEnabled) { _, enabled in
                                if enabled {
                                    Task {
                                        await healthService.requestAccessAndRefresh()
                                        await HealthSyncCoordinator.shared.syncNow(
                                            taskStore: taskStore,
                                            organizerStore: organizerStore,
                                            sharedHouseholdStore: sharedHouseholdStore
                                        )
                                    }
                                } else {
                                    HealthSyncCoordinator.shared.scheduleDailyRefresh()
                                }
                            }

                        if healthSharingEnabled {
                            Toggle(isOn: $shareHeart) {
                                Label("Also Share Heart", systemImage: "heart.fill")
                                    .labelStyle(.tile(AppTheme.warmAccent))
                            }
                            .onChange(of: shareHeart) { _, _ in resyncAll() }

                            Toggle(isOn: $shareBody) {
                                Label("Also Share Weight and BMI", systemImage: "scalemass.fill")
                                    .labelStyle(.tile(AppTheme.coolAccent))
                            }
                            .onChange(of: shareBody) { _, _ in resyncAll() }
                        }

                        RefreshRow(title: "Sync Health Summary Now", busyTitle: "Syncing Health Summary") {
                            await HealthSyncCoordinator.shared.syncNow(
                                taskStore: taskStore,
                                organizerStore: organizerStore,
                                sharedHouseholdStore: sharedHouseholdStore
                            )
                        }
                        .disabled(!healthSharingEnabled)

                    } header: {
                        Text("What Your Family Sees")
                    } footer: {
                        Text("These only decide what your family sees, not what Family Tasks can read. Sharing sends a small daily summary: steps, exercise, active energy, sleep and sleep score, plus heart and weight if you add them. It goes around 6 AM and when you open Health. Raw Health data stays on this phone.")
                    }

                }

                Section {
                    Toggle(isOn: $windDownEnabled) {
                        Label("3-2-1 Wind-Down", systemImage: "moon.zzz.fill")
                            .labelStyle(.tile(AppTheme.softAccent))
                    }
                    .onChange(of: windDownEnabled) { _, on in
                        HealthReminders.changed(turningOn: on, notificationsEnabled: $notificationsEnabled)
                    }
                    if windDownEnabled {
                        Toggle("No Food, 3 Hours Before", isOn: $windDownFood)
                            .onChange(of: windDownFood) { _, _ in HealthReminders.reschedule() }
                        Toggle("No Drinks, 2 Hours Before", isOn: $windDownDrinks)
                            .onChange(of: windDownDrinks) { _, _ in HealthReminders.reschedule() }
                        Toggle("No Screens, 1 Hour Before", isOn: $windDownScreens)
                            .onChange(of: windDownScreens) { _, _ in HealthReminders.reschedule() }
                    }

                    Toggle(isOn: $dailyTip) {
                        Label("Daily Health Tip", systemImage: "lightbulb.fill")
                            .labelStyle(.tile(AppTheme.success))
                    }
                    .onChange(of: dailyTip) { _, on in
                        HealthReminders.changed(turningOn: on, notificationsEnabled: $notificationsEnabled)
                    }
                    if dailyTip {
                        DatePicker("Tip Time", selection: tipTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Set your bedtime on the Health screen. Reminders work without Health access.")
                }

                if healthSectionEnabled {
                    Section("Access") {
                        RefreshRow(title: "Allow Health Access", busyTitle: "Asking for Health Access", systemImage: "heart") {
                            await healthService.requestAccessAndRefresh()
                        }
                        .disabled(!healthService.isHealthAvailable)

                        Button {
                            openAppSettings()
                        } label: {
                            Label("Manage or Revoke Health Access", systemImage: "gear")
                        }

                        Text(healthService.authorizationStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Health Settings")
            .labelStyle(.tile(SettingsTint.health))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .task {
                if healthSectionEnabled {
                    await healthService.refresh()
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    private func isArriving(_ kind: HealthDataKind) -> Bool {
        kind.isArriving(
            in: healthService.recentDays,
            sleepStages: healthService.receivesSleepStages,
            weight: healthService.weight,
            height: healthService.height
        )
    }

    /// "7 of 10", for the list while it's closed.
    private var receivingSummary: String {
        if healthService.isLoading && healthService.recentDays.isEmpty { return "Checking…" }
        return "\(HealthDataKind.allCases.filter(isArriving).count) of \(HealthDataKind.allCases.count)"
    }

    /// One kind of Health data, with whether any of it is arriving.
    private func dataRow(_ kind: HealthDataKind) -> some View {
        let arriving = isArriving(kind)
        return HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                    if !arriving, let source = kind.source {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: kind.systemImage)
            }
            Spacer(minLength: 8)
            if healthService.isLoading && healthService.recentDays.isEmpty {
                ProgressView()
            } else {
                Text(arriving ? "Receiving" : "No Data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(arriving ? AppTheme.success : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Sends every day again, so heart or weight numbers already shared are taken back
    /// when they're turned off.
    private func resyncAll() {
        Task {
            await HealthSyncCoordinator.shared.syncNow(
                taskStore: taskStore,
                organizerStore: organizerStore,
                sharedHouseholdStore: sharedHouseholdStore
            )
        }
    }

    private var tipTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: dailyTipHour, minute: dailyTipMinute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                dailyTipHour = parts.hour ?? dailyTipHour
                dailyTipMinute = parts.minute ?? dailyTipMinute
                HealthReminders.reschedule()
            }
        )
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var notificationScheduler: NotificationScheduler
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("notifications.todayDigest") private var todayDigestEnabled = true
    @AppStorage("notifications.dueSoon") private var dueSoonEnabled = true
    @AppStorage("notifications.familyCompletions") private var familyCompletionsEnabled = true
    @AppStorage("notifications.familyShopping") private var familyShoppingEnabled = true
    @AppStorage("notifications.familyHabits") private var familyHabitsEnabled = true
    @AppStorage("notifications.familyHealth") private var familyHealthEnabled = true
    @AppStorage("notifications.todayDigestHour") private var todayDigestHour = 8
    @AppStorage("notifications.todayDigestMinute") private var todayDigestMinute = 0
    @AppStorage("notifications.eveningDigest") private var eveningDigestEnabled = true
    @AppStorage("notifications.eveningDigestHour") private var eveningDigestHour = 20
    @AppStorage("notifications.eveningDigestMinute") private var eveningDigestMinute = 0
    @AppStorage("notifications.taskChanges") private var taskChangesEnabled = true
    @AppStorage("notifications.dueSoonLeadMinutes") private var dueSoonLeadMinutes = 60
    @AppStorage("notifications.dueSoonLeadMinutesList") private var dueSoonLeadMinutesList = "60"

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section("Notifications") {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Enable Notifications", systemImage: "bell.fill")
                            .labelStyle(.tile(SettingsTint.notifications))
                    }
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                requestNotificationPermission()
                            } else {
                                rescheduleNotifications()
                            }
                            updateFamilyAlerts()
                        }

                    Toggle(isOn: $dueSoonEnabled) {
                        Label("Due Soon Alerts", systemImage: "clock.badge.exclamationmark")
                            .labelStyle(.tile(AppTheme.taskSchedule))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: dueSoonEnabled) { _, _ in
                            rescheduleNotifications()
                        }

                    if dueSoonEnabled {
                        NotificationLeadTimeEditor(selectedMinutes: dueSoonLeadMinutesSelection)
                            .disabled(!notificationsEnabled)
                            .onChange(of: dueSoonLeadMinutesList) { _, _ in
                                rescheduleNotifications()
                            }
                    }

                    Text(notificationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $todayDigestEnabled) {
                        Label("Morning List", systemImage: "sun.max.fill")
                            .labelStyle(.tile(AppTheme.warning))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: todayDigestEnabled) { _, _ in
                            rescheduleNotifications()
                        }

                    if todayDigestEnabled {
                        DatePicker(
                            "Morning Time",
                            selection: timeBinding(hour: $todayDigestHour, minute: $todayDigestMinute),
                            displayedComponents: .hourAndMinute
                        )
                        .disabled(!notificationsEnabled)
                    }

                    Toggle(isOn: $eveningDigestEnabled) {
                        Label("Evening List", systemImage: "moon.stars.fill")
                            .labelStyle(.tile(AppTheme.primary))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: eveningDigestEnabled) { _, _ in
                            rescheduleNotifications()
                        }

                    if eveningDigestEnabled {
                        DatePicker(
                            "Evening Time",
                            selection: timeBinding(hour: $eveningDigestHour, minute: $eveningDigestMinute),
                            displayedComponents: .hourAndMinute
                        )
                        .disabled(!notificationsEnabled)
                    }
                } header: {
                    Text("Your Daily Tasks")
                } footer: {
                    Text("Lists your open tasks: overdue ones, ones due that day, recurring ones and ones with no date. Skipped on days with nothing to do.")
                }

                Section {
                    Toggle(isOn: $taskChangesEnabled) {
                        Label("New & Changed Tasks", systemImage: "square.and.pencil")
                            .labelStyle(.tile(AppTheme.taskSchedule))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: taskChangesEnabled) { _, _ in
                            updateFamilyAlerts()
                        }

                    Toggle(isOn: $familyCompletionsEnabled) {
                        Label("When Family Finishes a Task", systemImage: "checkmark.circle.fill")
                            .labelStyle(.tile(AppTheme.success))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: familyCompletionsEnabled) { _, _ in
                            updateFamilyAlerts()
                        }

                    Toggle(isOn: $familyShoppingEnabled) {
                        Label("When Shopping Is Done", systemImage: "cart.fill.badge.plus")
                            .labelStyle(.tile(AppTheme.coolAccent))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: familyShoppingEnabled) { _, _ in
                            updateFamilyAlerts()
                        }

                    Toggle(isOn: $familyHabitsEnabled) {
                        Label("When Family Finishes a Habit", systemImage: "flame.fill")
                            .labelStyle(.tile(AppTheme.goldAccent))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: familyHabitsEnabled) { _, _ in
                            updateFamilyAlerts()
                        }

                    Toggle(isOn: $familyHealthEnabled) {
                        Label("When Family Reaches a Health Goal", systemImage: "trophy.fill")
                            .labelStyle(.tile(SettingsTint.health))
                    }
                        .disabled(!notificationsEnabled)
                        .onChange(of: familyHealthEnabled) { _, _ in
                            updateFamilyAlerts()
                        }
                } header: {
                    Text("From Your Family")
                } footer: {
                    Text("Nudges and cheers always come through. Tap the bell on a task to nudge everyone else on it. Habits and health goals only send news when they're shared.")
                }

                Section("Status") {
                    HStack {
                        Label("Notification Status", systemImage: "bell.badge")
                        Spacer()
                        Text(notificationScheduler.pendingAlertCount == 1 ? "1 pending" : "\(notificationScheduler.pendingAlertCount) pending")
                            .foregroundStyle(.secondary)
                    }

                    Text(notificationScheduler.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await notificationScheduler.sendTestNotification()
                        }
                    } label: {
                        Label("Send Test Notification", systemImage: "paperplane.fill")
                            .labelStyle(.tile(AppTheme.primary))
                    }
                    .disabled(!notificationsEnabled)

                    NavigationLink {
                        FamilyAlertCheckView()
                    } label: {
                        Label("Check Family Alerts", systemImage: "stethoscope")
                            .labelStyle(.tile(AppTheme.warmAccent))
                    }
                }
            }
            .navigationTitle("Notifications")
            .labelStyle(.tile(SettingsTint.notifications))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .task {
                await notificationScheduler.refreshStatus()
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    notificationsEnabled = false
                }
            } else {
                Task { @MainActor in
                    await notificationScheduler.reschedule()
                }
            }
        }
    }

    private func rescheduleNotifications() {
        Task {
            await notificationScheduler.reschedule()
        }
    }

    private func updateFamilyAlerts() {
        Task {
            await FamilyAlertService.shared.updateSubscription()
        }
    }

    /// A time of day stored as an hour and a minute; changing it reschedules.
    private func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour.wrappedValue = components.hour ?? hour.wrappedValue
                minute.wrappedValue = components.minute ?? minute.wrappedValue
                rescheduleNotifications()
            }
        )
    }

    private var notificationDetail: String {
        var details: [String] = []

        if dueSoonEnabled {
            let descriptions = selectedDueSoonLeadMinutes.compactMap { minutes in
                NotificationLeadTimeOption.options.first(where: { $0.minutes == minutes })?.description
            }
            if !descriptions.isEmpty {
                details.append("Due soon alerts are sent \(formattedLeadTimeDescriptions(descriptions)).")
            }
        }

        if details.isEmpty {
            return "Turn on Due Soon Alerts to get reminders before tasks are due."
        }

        return details.joined(separator: " ")
    }

    private var dueSoonLeadMinutesSelection: Binding<[Int]> {
        Binding(
            get: { selectedDueSoonLeadMinutes },
            set: { newValue in
                let normalized = NotificationLeadTimeEditor.normalizedLeadMinutes(newValue)
                dueSoonLeadMinutesList = normalized.map(String.init).joined(separator: ",")
                dueSoonLeadMinutes = normalized.first ?? 60
            }
        )
    }

    private var selectedDueSoonLeadMinutes: [Int] {
        let parsedList = dueSoonLeadMinutesList
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !parsedList.isEmpty {
            return NotificationLeadTimeEditor.normalizedLeadMinutes(parsedList)
        }
        return NotificationLeadTimeEditor.normalizedLeadMinutes([dueSoonLeadMinutes])
    }

    private func formattedLeadTimeDescriptions(_ descriptions: [String]) -> String {
        switch descriptions.count {
        case 0:
            return "1 hour before the due time"
        case 1:
            return descriptions[0]
        case 2:
            return "\(descriptions[0]) and \(descriptions[1])"
        default:
            return "\(descriptions.dropLast().joined(separator: ", ")), and \(descriptions.last ?? "")"
        }
    }
}

/// Walks through what nudges and task alerts need, for when they don't arrive.
struct FamilyAlertCheckView: View {
    @State private var checks: [FamilyAlertService.Check] = []
    @State private var testResult: String?

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Form {
            Section {
                if checks.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Checking…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: check.isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(check.isOK ? AppTheme.success : AppTheme.warning)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.title)
                                .font(.subheadline.weight(.semibold))
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Every phone in the family needs all of these. Both phones must also run the same kind of build: both from TestFlight or the App Store, or both from Xcode.")
            }

            Section {
                ForEach(FamilyAlertService.shared.testRecipients, id: \.self) { email in
                    Button {
                        sendTest(to: email)
                    } label: {
                        Label("Send Test to \(Assignee.memberName(for: email))", systemImage: "paperplane.fill")
                            .labelStyle(.tile(AppTheme.primary))
                    }
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Test")
            } footer: {
                Text("Run this check on their phone too. A test that sends but never arrives means their phone isn't subscribed.")
            }
        }
        .navigationTitle("Family Alerts")
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .refreshable { await check() }
        .task { await check() }
    }

    private func check() async {
        checks = await FamilyAlertService.shared.runChecks()
    }

    private func sendTest(to email: String) {
        testResult = "Sending…"
        Task {
            do {
                try await FamilyAlertService.shared.sendTestAlert(to: email)
                testResult = "Sent to \(email). It should arrive on their phone within a few seconds."
            } catch {
                testResult = "Couldn't send: \(FamilyAlertService.NudgeError.cloud(error).localizedDescription)"
            }
            await check()
        }
    }
}

struct NotificationLeadTimeEditor: View {
    @Binding var selectedMinutes: [Int]

    var body: some View {
        ForEach(selectedMinutes.indices, id: \.self) { index in
            NotificationLeadTimeRow(
                minutes: binding(for: index),
                canDelete: selectedMinutes.count > 1,
                onDelete: {
                    removeNotification(at: index)
                }
            )
        }

        Button {
            addNotification()
        } label: {
            Label("Add Notification", systemImage: "plus.circle")
        }
    }

    static func normalizedLeadMinutes(_ values: [Int]) -> [Int] {
        let validValues = Set(NotificationLeadTimeOption.options.map(\.minutes))
        let normalized = Array(Set(values.filter { validValues.contains($0) })).sorted()
        return normalized.isEmpty ? [60] : normalized
    }

    private func binding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                guard selectedMinutes.indices.contains(index) else { return 60 }
                return selectedMinutes[index]
            },
            set: { newValue in
                guard selectedMinutes.indices.contains(index) else { return }
                var nextSelection = selectedMinutes
                nextSelection[index] = newValue
                selectedMinutes = Self.normalizedLeadMinutes(nextSelection)
            }
        )
    }

    private func addNotification() {
        let selected = Set(selectedMinutes)
        let preferredValues = [60, 30, 15, 180, 1_440]
        let nextValue = preferredValues.first { !selected.contains($0) } ?? 120
        selectedMinutes = Self.normalizedLeadMinutes(selectedMinutes + [nextValue])
    }

    private func removeNotification(at index: Int) {
        guard selectedMinutes.count > 1, selectedMinutes.indices.contains(index) else { return }
        var nextSelection = selectedMinutes
        nextSelection.remove(at: index)
        selectedMinutes = Self.normalizedLeadMinutes(nextSelection)
    }
}

private struct NotificationLeadTimeRow: View {
    @Binding var minutes: Int
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Amount", selection: amountBinding) {
                ForEach(unit.values, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Picker("Unit", selection: unitBinding) {
                ForEach(NotificationLeadTimeUnit.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .accessibilityLabel("Remove notification")
        }
    }

    private var unit: NotificationLeadTimeUnit {
        NotificationLeadTimeUnit.unit(for: minutes)
    }

    private var amount: Int {
        unit.amount(for: minutes)
    }

    private var amountBinding: Binding<Int> {
        Binding(
            get: { amount },
            set: { newValue in
                minutes = unit.minutes(for: newValue)
            }
        )
    }

    private var unitBinding: Binding<NotificationLeadTimeUnit> {
        Binding(
            get: { unit },
            set: { newUnit in
                let boundedAmount = min(max(amount, newUnit.values.first ?? 1), newUnit.values.last ?? amount)
                minutes = newUnit.minutes(for: boundedAmount)
            }
        )
    }
}

private enum NotificationLeadTimeUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days
    case weeks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        case .days: return "Days"
        case .weeks: return "Weeks"
        }
    }

    var values: [Int] {
        switch self {
        case .minutes: return [15, 30, 45]
        case .hours: return Array(1...24)
        case .days: return Array(1...7)
        case .weeks: return Array(1...4)
        }
    }

    static func unit(for minutes: Int) -> NotificationLeadTimeUnit {
        if minutes % 10_080 == 0, minutes >= 10_080 {
            return .weeks
        }
        if minutes % 1_440 == 0, minutes >= 1_440 {
            return .days
        }
        if minutes % 60 == 0, minutes >= 60 {
            return .hours
        }
        return .minutes
    }

    func amount(for minutes: Int) -> Int {
        switch self {
        case .minutes:
            return values.contains(minutes) ? minutes : 15
        case .hours:
            return min(max(minutes / 60, 1), 24)
        case .days:
            return min(max(minutes / 1_440, 1), 7)
        case .weeks:
            return min(max(minutes / 10_080, 1), 4)
        }
    }

    func minutes(for amount: Int) -> Int {
        switch self {
        case .minutes:
            return amount
        case .hours:
            return amount * 60
        case .days:
            return amount * 1_440
        case .weeks:
            return amount * 10_080
        }
    }
}

struct SyncSettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var profileEmail = ""
    @State private var preparedCloudShare: PreparedCloudShare?
    @State private var inviteLinkText = ""

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconTile(systemImage: sharedHouseholdStore.isSharingConfigured ? "icloud.fill" : "icloud", tint: SettingsTint.iCloud, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sharedHouseholdStore.isSharingConfigured ? "Sharing with your family" : "Not sharing yet")
                                .font(.headline)
                            Text(sharingDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    if sharedHouseholdStore.isSharingConfigured {
                        RefreshRow(
                            title: "Refresh Shared Data",
                            busyTitle: "Refreshing Shared Data",
                            isBusy: sharedHouseholdStore.isSyncing
                        ) {
                            await sharedHouseholdStore.refreshFromCloud()
                        }
                    }

                    if let message = sharedHouseholdStore.lastErrorMessage, !message.isEmpty {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.tile(AppTheme.destructive))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.destructive)
                    }
                }

                Section {
                    if taskStore.familyMembers.isEmpty {
                        Text("No one yet. Invite someone, or finish your own profile to start the family list.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(taskStore.familyMembers, id: \.self) { member in
                        HStack(spacing: 12) {
                            AssigneeAvatarView(name: member, size: 36, showsPhoto: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isYou(member) ? "You" : Assignee.memberName(for: member))
                                    .font(.body.weight(.semibold))
                                Text(member)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    SectionTitle(text: "Family")
                } footer: {
                    Text(memberStatusDetail)
                }

                Section {
                    Button {
                        prepareShare()
                    } label: {
                        if sharedHouseholdStore.isSyncing {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .frame(width: 30, height: 30)
                                Text("Preparing Invite")
                            }
                        } else {
                            Label("Invite Family Member", systemImage: "person.2.badge.plus")
                                .labelStyle(.tile(SettingsTint.iCloud))
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(sharedHouseholdStore.isSyncing)

                    if sharedHouseholdStore.isSharingConfigured {
                        Button {
                            prepareShare()
                        } label: {
                            Label("Manage Who Has Access", systemImage: "person.2.slash")
                                .labelStyle(.tile(AppTheme.softAccent))
                        }
                        .disabled(sharedHouseholdStore.isSyncing)
                    }
                } header: {
                    SectionTitle(text: "Invite")
                } footer: {
                    Text("Send the iCloud invite by Messages, email or phone. Each person appears here once they accept it and set up their profile in the app.")
                }

                Section {
                    TextField("Paste iCloud invite link", text: $inviteLinkText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await sharedHouseholdStore.acceptShareLink(inviteLinkText)
                            if sharedHouseholdStore.lastErrorMessage == nil {
                                inviteLinkText = ""
                            }
                        }
                    } label: {
                        if sharedHouseholdStore.isSyncing {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .frame(width: 30, height: 30)
                                Text("Joining")
                            }
                        } else {
                            Label("Join With This Link", systemImage: "link.badge.plus")
                                .labelStyle(.tile(AppTheme.primary))
                        }
                    }
                    .disabled(!canAcceptInviteLink || sharedHouseholdStore.isSyncing)
                } header: {
                    SectionTitle(text: "Got an invite?")
                } footer: {
                    Text("If the invite opened the App Store instead, install the app, then paste the original invite link here.")
                }

                Section {
                    Label("Tasks and who they're for", systemImage: "checklist")
                        .labelStyle(.tile(AppTheme.warmAccent))
                    Label("Shopping lists", systemImage: "cart")
                        .labelStyle(.tile(AppTheme.coolAccent))
                    Label("Meals and the meal plan", systemImage: "fork.knife")
                        .labelStyle(.tile(AppTheme.brightAccent))
                    Label("Recurring tasks and chores", systemImage: "repeat")
                        .labelStyle(.tile(AppTheme.softAccent))
                    Label("Profile initials and photos", systemImage: "person.crop.circle")
                        .labelStyle(.tile(AppTheme.primary))
                } header: {
                    SectionTitle(text: "What's Shared")
                } footer: {
                    Text("Calendar access and events, notification settings and appearance stay on each phone.")
                }
            }
            .navigationTitle("Family & Sharing")
            .labelStyle(.tile(SettingsTint.iCloud))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .sheet(item: $preparedCloudShare) { preparedShare in
                CloudSharingView(preparedShare: preparedShare)
            }
        }
    }

    private func prepareShare() {
        Task {
            do {
                preparedCloudShare = try await sharedHouseholdStore.prepareCloudShare()
            } catch {
                // The store exposes the user-facing error in the status card.
            }
        }
    }

    /// The status under the card's title, without repeating it.
    private var sharingDetail: String {
        let message = sharedHouseholdStore.statusMessage
        if message.caseInsensitiveCompare("Not sharing yet") == .orderedSame || message.isEmpty {
            return "Invite your family to share tasks, meals and shopping."
        }
        return message
    }

    private func isYou(_ member: String) -> Bool {
        member.caseInsensitiveCompare(profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private var memberStatusDetail: String {
        if sharedHouseholdStore.isSharingConfigured {
            return "New members appear once their profile syncs to the family."
        }

        return "Each person confirms their own email in their profile. The list is shared once you send the first invite."
    }

    private var canAcceptInviteLink: Bool {
        let trimmedLink = inviteLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedLink) else { return false }
        return url.scheme?.lowercased().hasPrefix("http") == true
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            Form {
                Section("Calendar Access") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Calendar Status", systemImage: "calendar")
                            Spacer()
                            Text(calendarSync.authorizationStatus.displayTitle)
                                .foregroundStyle(.secondary)
                        }

                        Text(calendarStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: isCalendarConnected ? .destructive : nil) {
                        if isCalendarConnected {
                            revokeCalendarAccess()
                        } else {
                            requestCalendarAccess()
                        }
                    } label: {
                        Label(calendarAccessActionTitle, systemImage: calendarAccessActionIcon)
                    }

                    RefreshRow(
                        title: "Refresh Calendar Events",
                        busyTitle: "Refreshing Calendar Events",
                        detail: calendarRefreshDetail,
                        isBusy: calendarSync.isLoadingTodayEvents
                    ) {
                        await refreshCalendar()
                    }
                    .disabled(!calendarIntegrationEnabled)

                    if let message = calendarSync.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                }

                if isCalendarConnected {
                    Section {
                        if calendarSync.availableCalendars.isEmpty {
                            ContentUnavailableView(
                                "No Calendars Found",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("No readable calendars are available on this device.")
                            )
                        } else {
                            Button {
                                calendarSync.selectAllReadCalendars()
                                refreshCalendarIfEnabled()
                            } label: {
                                Label("Select All Calendars", systemImage: "checklist.checked")
                            }

                            ForEach(calendarSync.availableCalendars) { option in
                                Toggle(isOn: Binding(
                                    get: { calendarSync.selectedReadCalendarIDs.contains(option.id) },
                                    set: { isSelected in
                                        calendarSync.setReadCalendar(option, isSelected: isSelected)
                                        refreshCalendarIfEnabled()
                                    }
                                )) {
                                    CalendarOptionLabel(option: option)
                                }
                            }
                        }
                    } header: {
                        Text("Show Events From")
                    } footer: {
                        Text("iOS grants calendar permission to the app, but Family Tasks only loads events from the calendars selected here on this device.")
                    }

                    Section {
                        Picker("Calendar", selection: writeCalendarSelection) {
                            Text("Automatic").tag("")
                            ForEach(calendarSync.availableCalendars.filter(\.allowsContentModifications)) { option in
                                Text(option.displayTitle).tag(option.id)
                            }
                        }

                        Text("Tasks synced from Family Tasks are added to this calendar. Choose a family-safe calendar if this device is shared with children.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Sync Tasks To")
                    }
                }
            }
            .navigationTitle("Calendar")
            .labelStyle(.tile(SettingsTint.calendar))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }

    private var calendarStatusDetail: String {
        if calendarIntegrationEnabled {
            switch calendarSync.authorizationStatus {
            case .fullAccess:
                return "Calendar access is connected. Choose below which calendars Family Tasks can show and where synced tasks are added."
            case .notDetermined:
                return "Calendar is enabled, but access has not been requested yet."
            case .writeOnly:
                return "Write-only access can sync tasks out, but full access is needed to show events."
            case .denied:
                return "Calendar access was denied. Enable access in iOS Settings to show events."
            case .restricted:
                return "Calendar access is restricted on this device."
            @unknown default:
                return "Calendar access status could not be determined."
            }
        }

        return "Turn on calendar events in View Settings, then choose which calendars Family Tasks may show here."
    }

    private var isCalendarConnected: Bool {
        switch calendarSync.authorizationStatus {
        case .fullAccess:
            return true
        default:
            return false
        }
    }

    private var calendarAccessActionTitle: String {
        isCalendarConnected ? "Revoke Calendar Access" : "Request Calendar Access"
    }

    private var calendarAccessActionIcon: String {
        isCalendarConnected ? "calendar.badge.minus" : "calendar.badge.checkmark"
    }

    private func requestCalendarAccess() {
        Task {
            let connected = await calendarSync.requestFullAccessForReadingIfNeeded()
            calendarIntegrationEnabled = connected
            if connected {
                await calendarSync.loadTodayEvents()
            }
        }
    }

    private func revokeCalendarAccess() {
        calendarIntegrationEnabled = false
        calendarSync.clearTodayEvents()

        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }


    private var writeCalendarSelection: Binding<String> {
        Binding(
            get: { calendarSync.selectedWriteCalendarID ?? "" },
            set: { selectedID in
                let option = calendarSync.availableCalendars.first { $0.id == selectedID }
                calendarSync.setWriteCalendar(option)
            }
        )
    }

    private func refreshCalendarIfEnabled() {
        guard calendarIntegrationEnabled else { return }
        Task { await refreshCalendar() }
    }

    private var calendarRefreshDetail: String {
        if let lastRefreshDate = calendarSync.lastRefreshDate {
            let eventCount = calendarSync.dayEvents.count
            let eventText = eventCount == 1 ? "1 event" : "\(eventCount) events"
            return "Last refreshed \(lastRefreshDate.formatted(date: .omitted, time: .shortened)); \(eventText) loaded for today."
        }

        return "Pulls events only from the selected calendars for Schedule."
    }

    private func refreshCalendar() async {
        let connected = await calendarSync.requestFullAccessForReadingIfNeeded()
        calendarIntegrationEnabled = connected
        if connected {
            await calendarSync.loadTodayEvents()
        }
    }
}


private struct CalendarOptionLabel: View {
    let option: CalendarSelectionOption

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(option.title)
            Text(option.sourceTitle + (option.allowsContentModifications ? "" : " - read only"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.initials") private var initials = ""
    @AppStorage("profile.isSetup") private var isProfileSetup = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set Up Your Profile")
                            .font(.title2.weight(.semibold))
                        Text("This profile is used as the default assignee when you create tasks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)

                    TextField("Initials", text: $initials)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .initials)
                        .onChange(of: initials) { _, newValue in
                            initials = String(newValue.prefix(3)).uppercased()
                        }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Family members can still be added later from Settings.")
                }

                Section {
                    Button {
                        completeSetup()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Continue")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isValidProfile)
                }
            }
            .navigationTitle("Welcome")
            .labelStyle(.tile(SettingsTint.profile))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .onAppear {
                focusedField = .email
            }
        }
        .tint(AppTheme.primary)
    }

    private var isValidProfile: Bool {
        TaskStore.isValidEmail(email)
    }

    private func completeSetup() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard TaskStore.isValidEmail(trimmedEmail) else { return }

        email = trimmedEmail
        if initials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initials = ProfileSetupView.initials(from: trimmedEmail)
        }

        taskStore.addFamilyMember(named: trimmedEmail)
        taskStore.assignUnassignedTasks(to: trimmedEmail)
        isProfileSetup = true

        guard sharedHouseholdStore.isSharingConfigured else { return }
        Task {
            await sharedHouseholdStore.uploadNow()
        }
    }

    private static func initials(from email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? ""
        let parts = localPart.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == " " })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }

    private enum Field {
        case email
        case initials
    }
}

/// A settings row that runs a refresh: while it works it shows a spinner and the busy title,
/// for at least a moment so even an instant refresh visibly happens, and ignores taps.
struct RefreshRow: View {
    let title: String
    let busyTitle: String
    var systemImage = "arrow.triangle.2.circlepath"
    var detail: String?
    /// Already refreshing for another reason (for example a sync the app started itself).
    var isBusy = false
    let action: () async -> Void
    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            Task {
                isRunning = true
                let started = Date()
                await action()
                let minimum: TimeInterval = 0.6
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < minimum {
                    try? await Task.sleep(for: .seconds(minimum - elapsed))
                }
                isRunning = false
            }
        } label: {
            if isRunning || isBusy {
                HStack(spacing: 12) {
                    ProgressView()
                        .frame(width: 30, height: 30)
                    Text(busyTitle)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: systemImage)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(isRunning || isBusy)
        .accessibilityLabel(isRunning || isBusy ? busyTitle : title)
    }
}

/// A theme drawn in its own colors: background, a card, the main color and its accents.
private struct ThemeCard: View {
    let theme: ThemePalette
    let isSelected: Bool
    let action: () -> Void

    private var accents: [Swatch] {
        [theme.warmAccent, theme.coolAccent, theme.goldAccent, theme.softAccent, theme.brightAccent]
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.primary.color)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: isSelected ? "checkmark" : "plus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.onPrimary.color)
                        }
                    Spacer(minLength: 0)
                    HStack(spacing: -4) {
                        ForEach(Array(accents.enumerated()), id: \.offset) { _, accent in
                            Circle()
                                .fill(accent.color)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(theme.surface.color, lineWidth: 1.5))
                        }
                    }
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.surfaceMuted.color)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.primary.color)
                            .frame(width: 44, height: 6)
                    }
                Text(theme.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
            .background(theme.surface.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(4)
            .background(theme.background.color, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(isSelected ? theme.primary.color : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
