import SwiftUI

/// A colored symbol on a soft square of the same color, as in the Family and More lists.
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

/// Each settings screen's color, shared by its row in More and the icons on the screen.
enum SettingsTint {
    static let profile = AppTheme.sage
    static let iCloud = AppTheme.dustyBlue
    static let notifications = AppTheme.honey
    static let calendar = AppTheme.terracotta
    static let health = AppTheme.apricot
    static let appearance = AppTheme.lavender
    static let ideas = AppTheme.honey
}
