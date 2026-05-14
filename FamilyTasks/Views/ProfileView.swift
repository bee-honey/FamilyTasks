import PhotosUI
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.initials") private var initials = ""
    @AppStorage("profile.imageData") private var imageData = Data()
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
