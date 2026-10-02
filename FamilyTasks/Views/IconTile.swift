import SwiftUI

/// A colored symbol on a soft square of the same color, as in the Family and Settings lists.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Shows a label's icon as an `IconTile`. Set it on a whole settings form for that
/// screen's color, and on single rows that deserve a color of their own.
struct TileLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

extension LabelStyle where Self == TileLabelStyle {
    static func tile(_ tint: Color) -> TileLabelStyle {
        TileLabelStyle(tint: tint)
    }
}

/// Each settings screen's color, shared by its row in Settings and the icons on the screen.
enum SettingsTint {
    static var profile: Color { AppTheme.primary }
    static var iCloud: Color { AppTheme.coolAccent }
    static var notifications: Color { AppTheme.goldAccent }
    static var calendar: Color { AppTheme.warmAccent }
    static var health: Color { AppTheme.brightAccent }
    static var appearance: Color { AppTheme.softAccent }
    static var ideas: Color { AppTheme.goldAccent }
}
