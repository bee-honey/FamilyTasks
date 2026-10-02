import SwiftUI
import UIKit

/// A color for light and dark mode: the hex values (for contrast checks) and the color,
/// built once so views always get the same instance.
struct Swatch: Sendable {
    let light: UInt
    let dark: UInt
    let color: Color

    init(_ light: UInt, _ dark: UInt) {
        self.light = light
        self.dark = dark
        color = Color(light: light, dark: dark)
    }
}

/// One color theme. Every theme fills the same roles, so a role means the same thing in
/// all of them: the warm accent is "Do now" and overdue, the cool accent "Schedule", and so on.
struct ThemePalette: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let background: Swatch
    let surface: Swatch
    let surfaceMuted: Swatch
    let primary: Swatch
    /// Text and icons drawn on a `primary` fill.
    let onPrimary: Swatch
    /// Initials on an avatar color.
    let onAvatar: Swatch
    let primarySoft: Swatch
    let ink: Swatch
    let warmAccent: Swatch
    let coolAccent: Swatch
    let goldAccent: Swatch
    let softAccent: Swatch
    let brightAccent: Swatch
    let success: Swatch
    /// Only for deleting and errors.
    let destructive: Swatch

    static let sageLinen = ThemePalette(
        id: "sageLinen",
        name: "Sage & Linen",
        summary: "Calm and homey: linen, sage and terracotta.",
        background: Swatch(0xF5F2EA, 0x151714),
        surface: Swatch(0xFFFDF8, 0x20231F),
        surfaceMuted: Swatch(0xE7E2D7, 0x2D312C),
        primary: Swatch(0x4E7B5A, 0x8DC09B),
        onPrimary: Swatch(0xFFFFFF, 0x142519),
        onAvatar: Swatch(0xFFFFFF, 0x151714),
        primarySoft: Swatch(0xE1ECDF, 0x23332A),
        ink: Swatch(0x22251F, 0xF1EEE6),
        warmAccent: Swatch(0xB0553A, 0xE9906F),
        coolAccent: Swatch(0x3C6A92, 0x8FB3D9),
        goldAccent: Swatch(0x8F6A1E, 0xE5C07B),
        softAccent: Swatch(0x6E5BA6, 0xBBA9E0),
        brightAccent: Swatch(0xA85F35, 0xEFB07F),
        success: Swatch(0x4E7B5A, 0x8DC09B),
        destructive: Swatch(0xB83A32, 0xF27A6E)
    )

    static let sundayMorning = ThemePalette(
        id: "sundayMorning",
        name: "Sunday Morning",
        summary: "Cheerful: coral, butter yellow and sky blue.",
        background: Swatch(0xFFF8F1, 0x1A1612),
        surface: Swatch(0xFFFFFF, 0x27211B),
        surfaceMuted: Swatch(0xF3E7DA, 0x352D25),
        primary: Swatch(0xB4502F, 0xF2906E),
        onPrimary: Swatch(0xFFFFFF, 0x2B130A),
        onAvatar: Swatch(0xFFFFFF, 0x1A1612),
        primarySoft: Swatch(0xFBE3D8, 0x3A2620),
        ink: Swatch(0x2A1E16, 0xFAF3EA),
        warmAccent: Swatch(0xB03A52, 0xF07A8A),
        coolAccent: Swatch(0x2F6AA0, 0x86BFEA),
        goldAccent: Swatch(0x86600C, 0xF4CF6A),
        softAccent: Swatch(0x6B4EB0, 0xC2A9F0),
        brightAccent: Swatch(0x2C7D5A, 0x86D1A4),
        success: Swatch(0x2C7D5A, 0x86D1A4),
        destructive: Swatch(0xC0302F, 0xFF7676)
    )

    static let eveningHarbor = ThemePalette(
        id: "eveningHarbor",
        name: "Evening Harbor",
        summary: "Cool and quiet: navy, seafoam and peach.",
        background: Swatch(0xF2F5F9, 0x11161F),
        surface: Swatch(0xFFFFFF, 0x1A2230),
        surfaceMuted: Swatch(0xE4E9F0, 0x263042),
        primary: Swatch(0x15766B, 0x6CD3C3),
        onPrimary: Swatch(0xFFFFFF, 0x0C2724),
        onAvatar: Swatch(0xFFFFFF, 0x11161F),
        primarySoft: Swatch(0xD8EFEB, 0x17363A),
        ink: Swatch(0x182233, 0xEEF2F6),
        warmAccent: Swatch(0xB55A3A, 0xF5A88C),
        coolAccent: Swatch(0x3A5FB0, 0x9DB7F5),
        goldAccent: Swatch(0x8F6410, 0xF5C26B),
        softAccent: Swatch(0x6650B8, 0xBBA8F5),
        brightAccent: Swatch(0x2E8256, 0x7FD3A0),
        success: Swatch(0x2E8256, 0x7FD3A0),
        destructive: Swatch(0xC23B3B, 0xFF7B7B)
    )

    static let honeyOak = ThemePalette(
        id: "honeyOak",
        name: "Honey & Oak",
        summary: "Warm and cozy: amber, oak and clay.",
        background: Swatch(0xF8F3EA, 0x18140F),
        surface: Swatch(0xFFFDF7, 0x241D16),
        surfaceMuted: Swatch(0xEDE3D3, 0x33291F),
        primary: Swatch(0x80550F, 0xE8B04F),
        onPrimary: Swatch(0xFFFFFF, 0x2A1C05),
        onAvatar: Swatch(0xFFFFFF, 0x18140F),
        primarySoft: Swatch(0xF4E6C8, 0x3A2C14),
        ink: Swatch(0x2A2117, 0xF6EFE4),
        warmAccent: Swatch(0xA34B2C, 0xE08A68),
        coolAccent: Swatch(0x3F6683, 0x8DB0C8),
        goldAccent: Swatch(0x5C6A2C, 0xB5C27F),
        softAccent: Swatch(0x934A68, 0xD9A0B5),
        brightAccent: Swatch(0x2B7266, 0x7FC4B8),
        success: Swatch(0x467536, 0x9CCB86),
        destructive: Swatch(0xB5362E, 0xF07167)
    )

    static let lavenderDusk = ThemePalette(
        id: "lavenderDusk",
        name: "Lavender Dusk",
        summary: "Soft and dreamy: violet, pink and peach.",
        background: Swatch(0xF6F4FA, 0x15131C),
        surface: Swatch(0xFFFFFF, 0x211E2B),
        surfaceMuted: Swatch(0xE9E5F2, 0x2E2A3B),
        primary: Swatch(0x5E4BA8, 0xB7A4F0),
        onPrimary: Swatch(0xFFFFFF, 0x221A3D),
        onAvatar: Swatch(0xFFFFFF, 0x15131C),
        primarySoft: Swatch(0xE6E0F7, 0x2D2645),
        ink: Swatch(0x1F1A2E, 0xF1EEF7),
        warmAccent: Swatch(0xA9513A, 0xF0A08C),
        coolAccent: Swatch(0x2C6890, 0x8FC1E3),
        goldAccent: Swatch(0x7F5D10, 0xEDC77A),
        softAccent: Swatch(0x9C3D66, 0xF2A3C4),
        brightAccent: Swatch(0x2A7A58, 0x8FD3B5),
        success: Swatch(0x2A7A58, 0x8FD3B5),
        destructive: Swatch(0xBE3434, 0xF57A7A)
    )

    static let classic = ThemePalette(
        id: "classic",
        name: "Classic",
        summary: "The original look: teal on warm brown.",
        background: Swatch(0xF6F2EC, 0x171411),
        surface: Swatch(0xFFFDF8, 0x24201B),
        surfaceMuted: Swatch(0xEFE8DF, 0x332D26),
        primary: Swatch(0x167C80, 0x58C7C5),
        onPrimary: Swatch(0xFFFFFF, 0x102A2A),
        onAvatar: Swatch(0xFFFFFF, 0x171411),
        primarySoft: Swatch(0xD9EEEA, 0x173D3E),
        ink: Swatch(0x242424, 0xF4EFE7),
        warmAccent: Swatch(0xB4504D, 0xFF8A86),
        coolAccent: Swatch(0x356F90, 0x79BFE2),
        goldAccent: Swatch(0x8A5C14, 0xF0B85A),
        softAccent: Swatch(0x6B5B99, 0xB5A6E4),
        brightAccent: Swatch(0xA4506B, 0xEA93AF),
        success: Swatch(0x45795E, 0x74C69D),
        destructive: Swatch(0xB4504D, 0xFF8A86)
    )

    /// The default first.
    static let all: [ThemePalette] = [sundayMorning, sageLinen, eveningHarbor, honeyOak, lavenderDusk, classic]
    static let defaultTheme = sundayMorning
    static let storageKey = "view.theme"

    static func named(_ id: String?) -> ThemePalette {
        all.first { $0.id == id } ?? defaultTheme
    }
}

/// The current theme's colors by role. The theme is read when a view draws, so changing it
/// takes effect once views redraw (the app rebuilds its screens when the theme changes).
enum AppTheme {
    static var palette: ThemePalette {
        ThemePalette.named(UserDefaults.standard.string(forKey: ThemePalette.storageKey))
    }

    static var background: Color { palette.background.color }
    static var surface: Color { palette.surface.color }
    static var surfaceMuted: Color { palette.surfaceMuted.color }
    static var primary: Color { palette.primary.color }
    /// Text and icons drawn on a `primary` fill.
    static var onPrimary: Color { palette.onPrimary.color }
    /// Initials on an `avatarPalette` fill.
    static var onAvatar: Color { palette.onAvatar.color }
    static var primarySoft: Color { palette.primarySoft.color }
    static var ink: Color { palette.ink.color }

    static var warmAccent: Color { palette.warmAccent.color }
    static var coolAccent: Color { palette.coolAccent.color }
    static var goldAccent: Color { palette.goldAccent.color }
    static var softAccent: Color { palette.softAccent.color }
    static var brightAccent: Color { palette.brightAccent.color }

    static var success: Color { palette.success.color }
    static var warning: Color { goldAccent }
    /// Only for deleting and errors; things running late use `overdue`.
    static var destructive: Color { palette.destructive.color }
    /// Late but not alarming.
    static var overdue: Color { warmAccent }

    /// Family members take these in family-list order.
    static var avatarPalette: [Color] { [primary, softAccent, brightAccent, coolAccent, goldAccent, warmAccent] }

    static var taskDo: Color { warmAccent }
    static var taskSchedule: Color { coolAccent }
    static var taskDelegate: Color { goldAccent }
    static var taskDrop: Color { softAccent }
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
