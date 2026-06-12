import PhotosUI
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.initials") private var initials = ""
    @AppStorage("profile.imageData") private var imageData = Data()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        imageData = data
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
    @AppStorage("schedule.showTaskTime") private var showTaskTime = false
    @AppStorage("schedule.showTaskBucket") private var showTaskBucket = false
    @AppStorage("schedule.defaultDisplayMode") private var defaultScheduleView = "week"
    @AppStorage("view.appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.contentPriority") private var scheduleContentPriority = ScheduleContentPriority.tasksFirst.rawValue

    var body: some View {
        NavigationStack {
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

                Section("Schedule View") {
                    Picker("Default View", selection: $defaultScheduleView) {
                        Text("Today").tag("today")
                        Text("Week").tag("week")
                        Text("Month").tag("month")
                    }

                    Toggle("Show Time On Tasks", isOn: $showTaskTime)
                    Toggle("Show Bucket On Tasks", isOn: $showTaskBucket)
                }

                Section("Tasks and Calendars") {
                    Toggle("Show Calendar Events in Schedule", isOn: $calendarIntegrationEnabled)
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

                    Picker("Schedule Priority", selection: $scheduleContentPriority) {
                        ForEach(ScheduleContentPriority.allCases) { priority in
                            Text(priority.title).tag(priority.rawValue)
                        }
                    }

                    Text("Choose whether Schedule leads with family tasks or calendar events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("View Settings")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var notificationScheduler: NotificationScheduler
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("notifications.todayDigest") private var todayDigestEnabled = true
    @AppStorage("notifications.dueSoon") private var dueSoonEnabled = true
    @AppStorage("notifications.todayDigestHour") private var todayDigestHour = 8
    @AppStorage("notifications.todayDigestMinute") private var todayDigestMinute = 0
    @AppStorage("notifications.dueSoonLeadMinutes") private var dueSoonLeadMinutes = 60

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                requestNotificationPermission()
                            } else {
                                rescheduleNotifications()
                            }
                        }

                    Toggle("Today Digest", isOn: $todayDigestEnabled)
                        .disabled(!notificationsEnabled)
                        .onChange(of: todayDigestEnabled) { _, _ in
                            rescheduleNotifications()
                        }

                    if todayDigestEnabled {
                        Picker("Digest Time", selection: Binding(
                            get: { todayDigestTime },
                            set: { todayDigestTime = $0 }
                        )) {
                            ForEach(NotificationDigestTimeOption.options) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .disabled(!notificationsEnabled)
                        .onChange(of: todayDigestTime) { _, _ in
                            rescheduleNotifications()
                        }
                    }

                    Toggle("Due Soon Alerts", isOn: $dueSoonEnabled)
                        .disabled(!notificationsEnabled)
                        .onChange(of: dueSoonEnabled) { _, _ in
                            rescheduleNotifications()
                        }

                    if dueSoonEnabled {
                        Picker("Due Soon Means", selection: $dueSoonLeadMinutes) {
                            ForEach(NotificationDueSoonOption.options) { option in
                                Text(option.title).tag(option.minutes)
                            }
                        }
                        .disabled(!notificationsEnabled)
                        .onChange(of: dueSoonLeadMinutes) { _, _ in
                            rescheduleNotifications()
                        }
                    }

                    Text(notificationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        Label("Send Test Notification", systemImage: "paperplane")
                    }
                    .disabled(!notificationsEnabled)
                }
            }
            .navigationTitle("Notification Settings")
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

    private var todayDigestTime: String {
        get {
            NotificationDigestTimeOption.id(hour: todayDigestHour, minute: todayDigestMinute)
        }
        nonmutating set {
            guard let option = NotificationDigestTimeOption.options.first(where: { $0.id == newValue }) else { return }
            todayDigestHour = option.hour
            todayDigestMinute = option.minute
        }
    }

    private var notificationDetail: String {
        var details: [String] = []

        if todayDigestEnabled {
            details.append("Digest at \(NotificationDigestTimeOption.title(hour: todayDigestHour, minute: todayDigestMinute)) for tasks scheduled that day.")
        }

        if dueSoonEnabled,
           let dueSoonOption = NotificationDueSoonOption.options.first(where: { $0.minutes == dueSoonLeadMinutes }) {
            details.append("Due soon alerts are sent \(dueSoonOption.description).")
        }

        if details.isEmpty {
            return "Turn on a notification type to schedule local alerts for this device."
        }

        return details.joined(separator: " ")
    }
}

private struct NotificationDigestTimeOption: Identifiable {
    let hour: Int
    let minute: Int
    let title: String

    var id: String {
        Self.id(hour: hour, minute: minute)
    }

    static let options = [
        NotificationDigestTimeOption(hour: 6, minute: 0, title: "6:00 AM"),
        NotificationDigestTimeOption(hour: 7, minute: 0, title: "7:00 AM"),
        NotificationDigestTimeOption(hour: 8, minute: 0, title: "8:00 AM"),
        NotificationDigestTimeOption(hour: 9, minute: 0, title: "9:00 AM"),
        NotificationDigestTimeOption(hour: 18, minute: 0, title: "6:00 PM"),
        NotificationDigestTimeOption(hour: 20, minute: 0, title: "8:00 PM")
    ]

    static func id(hour: Int, minute: Int) -> String {
        "\(hour):\(minute)"
    }

    static func title(hour: Int, minute: Int) -> String {
        options.first(where: { $0.hour == hour && $0.minute == minute })?.title ?? String(format: "%02d:%02d", hour, minute)
    }
}

private struct NotificationDueSoonOption: Identifiable {
    let minutes: Int
    let title: String
    let description: String

    var id: Int { minutes }

    static let options = [
        NotificationDueSoonOption(minutes: 0, title: "At due time", description: "at the due time"),
        NotificationDueSoonOption(minutes: 15, title: "15 minutes before", description: "15 minutes before the due time"),
        NotificationDueSoonOption(minutes: 30, title: "30 minutes before", description: "30 minutes before the due time"),
        NotificationDueSoonOption(minutes: 60, title: "1 hour before", description: "1 hour before the due time"),
        NotificationDueSoonOption(minutes: 180, title: "3 hours before", description: "3 hours before the due time"),
        NotificationDueSoonOption(minutes: 1_440, title: "1 day before", description: "1 day before the due date")
    ]
}

struct SyncSettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @State private var preparedCloudShare: PreparedCloudShare?
    @State private var inviteLinkText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Household Sharing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How Invites Work", systemImage: "person.crop.circle.badge.questionmark")
                        Text("The iCloud invite can be sent by iMessage, email, or phone number, but Apple keeps that contact identity private. Each person appears in this app after they accept the share and complete their profile email.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task {
                            do {
                                preparedCloudShare = try await sharedHouseholdStore.prepareCloudShare()
                            } catch {
                                // The store exposes the user-facing error in the sharing status rows.
                            }
                        }
                    } label: {
                        if sharedHouseholdStore.isSyncing {
                            HStack {
                                ProgressView()
                                Text("Preparing Share")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Invite Household Member", systemImage: "person.2.badge.plus")
                                Text("Send an iCloud invite. After they join and set up their profile, their email is added here automatically.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(sharedHouseholdStore.isSyncing)

                    if sharedHouseholdStore.isSharingConfigured {
                        Button {
                            Task {
                                do {
                                    preparedCloudShare = try await sharedHouseholdStore.prepareCloudShare()
                                } catch {
                                    // The store exposes the user-facing error in the sharing status rows.
                                }
                            }
                        } label: {
                            Label("Manage iCloud Share", systemImage: "person.2.slash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(sharedHouseholdStore.isSyncing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Members", systemImage: "person.2")

                        if taskStore.familyMembers.isEmpty {
                            Text("No members yet. Invite someone or complete your own profile to start the household list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(taskStore.familyMembers, id: \.self) { member in
                                HStack(spacing: 10) {
                                    AssigneeAvatarView(name: member)
                                        .scaleEffect(0.72)
                                        .frame(width: 28, height: 28)
                                    Text(member)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Text(memberStatusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
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
                                HStack {
                                    ProgressView()
                                    Text("Joining Household")
                                }
                            } else {
                                Label("Accept Invite Link", systemImage: "link.badge.plus")
                            }
                        }
                        .disabled(!canAcceptInviteLink || sharedHouseholdStore.isSyncing)

                        Text("Use this if the iCloud invite opens the App Store first. Install the app, copy the original invite link, paste it here, and join the shared household.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task {
                            await sharedHouseholdStore.refreshFromCloud()
                        }
                    } label: {
                        if sharedHouseholdStore.isSyncing {
                            HStack {
                                ProgressView()
                                Text("Refreshing Shared Data")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Refresh Shared Data", systemImage: "arrow.triangle.2.circlepath")
                                Text(sharedHouseholdStore.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .disabled(!sharedHouseholdStore.isSharingConfigured)

                    HStack {
                        Label("Sharing Status", systemImage: "icloud")
                        Spacer()
                        Text(sharedHouseholdStore.statusMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    if let message = sharedHouseholdStore.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                }

                Section("Shared Household Data") {
                    Label("Tasks and assignees", systemImage: "checklist")
                    Label("Recurring tasks", systemImage: "repeat")
                    Label("Shopping lists", systemImage: "cart")
                    Label("Meal ideas and planned meals", systemImage: "fork.knife")
                    Label("Profile initials and photos", systemImage: "person.crop.circle")

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Kept Local", systemImage: "lock")
                        Text("Calendar access, calendar events, notification preferences, and display settings stay on each person's device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("iCloud Settings")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .sheet(item: $preparedCloudShare) { preparedShare in
                CloudSharingView(preparedShare: preparedShare)
            }
        }
    }

    private var memberStatusDetail: String {
        if sharedHouseholdStore.isSharingConfigured {
            return "After someone accepts the iCloud invite, they appear here when their profile email syncs back to the household."
        }

        return "Members are shared after the first iCloud invite is created. Each person confirms their own profile email in this app."
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
    @State private var isRefreshingCalendar = false

    var body: some View {
        NavigationStack {
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

                    Button {
                        requestCalendarAccess()
                    } label: {
                        Label("Request Calendar Access", systemImage: "calendar.badge.checkmark")
                    }

                    Button {
                        refreshCalendar()
                    } label: {
                        if isRefreshingCalendar || calendarSync.isLoadingTodayEvents {
                            HStack {
                                ProgressView()
                                Text("Refreshing Calendar Events")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Refresh Calendar Events", systemImage: "arrow.triangle.2.circlepath")
                                Text(calendarRefreshDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .disabled(!calendarIntegrationEnabled)

                    if let message = calendarSync.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                }
            }
            .navigationTitle("Calendar Settings")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
    }

    private var calendarStatusDetail: String {
        if calendarIntegrationEnabled {
            switch calendarSync.authorizationStatus {
            case .authorized, .fullAccess:
                return "Calendar events are shown in Schedule and can be refreshed from this page."
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

        return "Turn on calendar events in View Settings to show them inside Schedule."
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

    private var calendarRefreshDetail: String {
        if let lastRefreshDate = calendarSync.lastRefreshDate {
            let eventCount = calendarSync.dayEvents.count
            let eventText = eventCount == 1 ? "1 event" : "\(eventCount) events"
            return "Last refreshed \(lastRefreshDate.formatted(date: .omitted, time: .shortened)); \(eventText) loaded for today."
        }

        return "Pulls the latest events from Calendar for Schedule."
    }

    private func refreshCalendar() {
        Task {
            isRefreshingCalendar = true
            let connected = await calendarSync.requestFullAccessForReadingIfNeeded()
            calendarIntegrationEnabled = connected
            if connected {
                await calendarSync.loadTodayEvents()
            }
            try? await Task.sleep(for: .milliseconds(350))
            isRefreshingCalendar = false
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
