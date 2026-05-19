import PhotosUI
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var calendarSync: CalendarSyncService
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

                Section("Family") {
                    NavigationLink {
                        FamilyMembersView()
                    } label: {
                        Label("Family Members", systemImage: "person.2")
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

                    HStack {
                        Label("Status", systemImage: "calendar")
                        Spacer()
                        Text(calendarSync.authorizationStatus.displayTitle)
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
                            ProgressView()
                        } else {
                            Label("Refresh Calendar Events", systemImage: "arrow.clockwise")
                        }
                    }
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
            }
            .navigationTitle("Profile")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
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
