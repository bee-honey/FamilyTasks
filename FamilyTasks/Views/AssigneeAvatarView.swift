import SwiftUI

struct AssigneeAvatarView: View {
    let name: String

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let displayName = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        let parts = displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(avatarColor)
            .clipShape(Circle())
            .accessibilityLabel(name.isEmpty ? "Unassigned" : "Assigned to \(name)")
    }

    private var avatarColor: Color {
        let source = name.isEmpty ? "Unassigned" : name
        let index = abs(source.hashValue) % AppTheme.avatarPalette.count
        return AppTheme.avatarPalette[index]
    }
}
