import PhotosUI
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarSync: CalendarSyncService
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.initials") private var initials = ""
    @AppStorage("profile.imageData") private var imageData = Data()
    @AppStorage("calendar.integration.enabled") private var calendarIntegrationEnabled = false
    @AppStorage("schedule.showTaskTime") private var showTaskTime = false
    @AppStorage("schedule.showTaskBucket") private var showTaskBucket = false
    @AppStorage("schedule.defaultDisplayMode") private var defaultScheduleView = "week"
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("notifications.todayDigest") private var todayDigestEnabled = true
    @AppStorage("notifications.dueSoon") private var dueSoonEnabled = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var preparedCloudShare: PreparedCloudShare?

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
                        } label: {
                            Label("Remove Profile Image", systemImage: "trash")
                        }
                    }
                }

                Section("Identity") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Initials", text: $initials)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: initials) { _, newValue in
                            initials = String(newValue.prefix(3)).uppercased()
                        }
                }

                Section("Household Sharing") {
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

                        Text("Members come from accepted iCloud share users who have completed their profile in this app. Apple does not expose the Apple Account email directly, so each person confirms their own email once.")
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

                Section("Calendar") {
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
                        Task {
                            let connected = await calendarSync.requestFullAccessForReadingIfNeeded()
                            calendarIntegrationEnabled = connected
                            if connected {
                                await calendarSync.loadTodayEvents()
                            }
                        }
                    } label: {
                        if calendarSync.isLoadingTodayEvents {
                            HStack {
                                ProgressView()
                                Text("Refreshing Calendar Events")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Refresh Calendar Events", systemImage: "arrow.clockwise")
                                Text(calendarRefreshDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .disabled(!calendarIntegrationEnabled && calendarSync.authorizationStatus == .denied)

                    if let message = calendarSync.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                }

                Section("Schedule") {
                    Picker("Default View", selection: $defaultScheduleView) {
                        Text("Today").tag("today")
                        Text("Week").tag("week")
                        Text("Month").tag("month")
                    }

                    Toggle("Show Time On Tasks", isOn: $showTaskTime)
                    Toggle("Show Bucket On Tasks", isOn: $showTaskBucket)
                }

                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                requestNotificationPermission()
                            }
                        }

                    Toggle("Today Digest", isOn: $todayDigestEnabled)
                        .disabled(!notificationsEnabled)

                    Toggle("Due Soon Alerts", isOn: $dueSoonEnabled)
                        .disabled(!notificationsEnabled)
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(appVersionDisplay)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .sheet(item: $preparedCloudShare) { preparedShare in
                CloudSharingView(preparedShare: preparedShare)
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
        }
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(version?.isEmpty == false ? version! : "1.0") (\(build?.isEmpty == false ? build! : "1"))"
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

        return "Turn this on to show calendar events inside Schedule."
    }

    private var calendarRefreshDetail: String {
        if let lastRefreshDate = calendarSync.lastRefreshDate {
            let eventCount = calendarSync.dayEvents.count
            let eventText = eventCount == 1 ? "1 event" : "\(eventCount) events"
            return "Last refreshed \(lastRefreshDate.formatted(date: .omitted, time: .shortened)); \(eventText) loaded for today."
        }

        return "Pulls the latest events from Calendar for Schedule."
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    notificationsEnabled = false
                }
            }
        }
    }
}


struct ProfileSetupView: View {
    @EnvironmentObject private var taskStore: TaskStore
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
