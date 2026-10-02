import SwiftUI
import UIKit

/// "Sage & Linen": linen and warm off-white (soft charcoal in dark mode) with sage as the
/// main color, and terracotta, dusty blue, honey, lavender and apricot accents at matching
/// lightness. Light mode is its own palette, not dimmed dark colors.
enum AppTheme {
    static let background = Color(light: 0xF5F2EA, dark: 0x151714)
    static let surface = Color(light: 0xFFFDF8, dark: 0x20231F)
    static let surfaceMuted = Color(light: 0xE7E2D7, dark: 0x2D312C)
    static let primary = Color(light: 0x4E7B5A, dark: 0x8DC09B)
    /// Text and icons drawn on a `primary` fill.
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x142519)
    /// Initials on an `avatarPalette` fill: the dark-mode palette is light, so it needs dark text.
    static let onAvatar = Color(light: 0xFFFFFF, dark: 0x151714)
    static let primarySoft = Color(light: 0xE1ECDF, dark: 0x23332A)
    static let ink = Color(light: 0x22251F, dark: 0xF1EEE6)

    static let sage = primary
    static let terracotta = Color(light: 0xB0553A, dark: 0xE9906F)
    static let dustyBlue = Color(light: 0x3C6A92, dark: 0x8FB3D9)
    static let honey = Color(light: 0x8F6A1E, dark: 0xE5C07B)
    static let lavender = Color(light: 0x6E5BA6, dark: 0xBBA9E0)
    static let apricot = Color(light: 0xA85F35, dark: 0xEFB07F)

    /// Done and healthy: the main sage.
    static let success = sage
    static let warning = honey
    /// Only for deleting and errors; things running late use `overdue`.
    static let destructive = Color(light: 0xB83A32, dark: 0xF27A6E)
    /// Late but not alarming.
    static let overdue = terracotta

    /// Family members take these in family-list order.
    static let avatarPalette: [Color] = [sage, lavender, apricot, dustyBlue, honey, terracotta]

    static let taskDo = terracotta
    static let taskSchedule = dustyBlue
    static let taskDelegate = honey
    static let taskDrop = lavender
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ScheduleTaskSortOrder: String, CaseIterable, Identifiable {
    case priority
    case deadline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority: "Priority"
        case .deadline: "Deadline"
        }
    }
}

extension TaskBucket {
    var accentColor: Color {
        switch self {
        case .doNow: AppTheme.taskDo
        case .schedule: AppTheme.taskSchedule
        case .delegate: AppTheme.taskDelegate
        case .delete: AppTheme.taskDrop
        }
    }

    var taskBackgroundColor: Color {
        accentColor.opacity(0.11)
    }
}

struct TaskPriorityMarkerGroup: View {
    let task: FamilyTask

    var body: some View {
        HStack(spacing: 4) {
            ForEach(task.priorityMarkers, id: \.self) { marker in
                TaskPriorityMarkerBadge(marker: marker, color: markerColor(for: marker))
            }
        }
    }

    private func markerColor(for marker: String) -> Color {
        marker == "U" ? AppTheme.warning : task.bucket.accentColor
    }
}

struct TaskPriorityMarkerBadge: View {
    let marker: String
    let color: Color

    var body: some View {
        Text(marker)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(color, in: Circle())
            .accessibilityLabel(marker == "U" ? "Urgent" : "Important")
    }
}

extension Color {
    init(light: UInt, dark: UInt, opacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, opacity: opacity)
        })
    }

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt, opacity: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
