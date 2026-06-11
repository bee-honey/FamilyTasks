import SwiftUI
import UIKit

struct AssigneeAvatarView: View {
    let name: String
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
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(avatarColor)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .accessibilityLabel(name.isEmpty ? "Unassigned" : "Assigned to \(Assignee.displayName(for: name))")
    }

    private var avatarColor: Color {
        let source = name.isEmpty ? "Unassigned" : name
        let index = abs(source.hashValue) % AppTheme.avatarPalette.count
        return AppTheme.avatarPalette[index]
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
