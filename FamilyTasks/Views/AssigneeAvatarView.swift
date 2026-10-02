import SwiftUI
import UIKit

struct AssigneeAvatarView: View {
    let name: String
    var size: CGFloat = 38
    /// Colored initials only, even when the member has a profile photo.
    var showsPhoto = true
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.initials") private var profileInitials = ""
    @AppStorage("profile.imageData") private var profileImageData = Data()
    @AppStorage(SharedMemberProfile.storageKey) private var sharedProfilesData = Data()

    private var isCurrentUser: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Assignee.isEveryone(trimmed) else { return false }
        let trimmedProfileEmail = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare(trimmedProfileEmail) == .orderedSame
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        if Assignee.isEveryone(trimmed) {
            return "ALL"
        }

        let trimmedProfileEmail = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProfileInitials = profileInitials.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedProfileInitials.isEmpty && trimmed.caseInsensitiveCompare(trimmedProfileEmail) == .orderedSame {
            return String(trimmedProfileInitials.prefix(3)).uppercased()
        }

        if let sharedInitials = sharedProfile?.initials.trimmingCharacters(in: .whitespacesAndNewlines),
           !sharedInitials.isEmpty {
            return String(sharedInitials.prefix(3)).uppercased()
        }

        let displayName = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        let parts = displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Group {
            if showsPhoto, let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * (initials.count > 2 ? 0.3 : 0.36), weight: .bold))
                    .foregroundStyle(AppTheme.onAvatar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(avatarColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name.isEmpty ? "Unassigned" : "Assigned to \(Assignee.displayName(for: name))")
    }

    /// Family members get colors in family-list order, so each one differs (for up to six)
    /// and matches on every phone; anyone else gets a stable color from their name
    /// (`hashValue` would change on every launch).
    private var avatarColor: Color {
        let source = (name.isEmpty ? "Unassigned" : name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let palette = AppTheme.avatarPalette
        if let index = TaskStore.shared.familyMembers.firstIndex(of: source) {
            return palette[index % palette.count]
        }
        let hash = source.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }

    private var avatarImage: UIImage? {
        if isCurrentUser, let image = UIImage(data: profileImageData) {
            return image
        }

        guard let imageData = sharedProfile?.imageData else { return nil }
        return UIImage(data: imageData)
    }

    private var sharedProfile: SharedMemberProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Assignee.isEveryone(trimmed) else { return nil }
        guard let profiles = try? JSONDecoder().decode([SharedMemberProfile].self, from: sharedProfilesData) else { return nil }
        return SharedMemberProfile.profile(for: trimmed, in: profiles)
    }
}
