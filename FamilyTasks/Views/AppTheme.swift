import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(light: 0xF6F2EC, dark: 0x171411)
    static let surface = Color(light: 0xFFFDF8, dark: 0x24201B)
    static let surfaceMuted = Color(light: 0xEFE8DF, dark: 0x332D26)
    static let primary = Color(light: 0x167C80, dark: 0x58C7C5)
    static let primarySoft = Color(light: 0xD9EEEA, dark: 0x173D3E)
    static let success = Color(light: 0x4F8A6B, dark: 0x74C69D)
    static let warning = Color(light: 0xD9912B, dark: 0xF0B85A)
    static let destructive = Color(light: 0xC85D5A, dark: 0xFF8A86)
    static let ink = Color(light: 0x242424, dark: 0xF4EFE7)

    static let avatarPalette: [Color] = [
        Color(light: 0x167C80, dark: 0x58C7C5),
        Color(light: 0x7B6BA8, dark: 0xB5A6E4),
        Color(light: 0xC66F4E, dark: 0xF3A47F),
        Color(light: 0x4F8A6B, dark: 0x74C69D),
        Color(light: 0xB45F7A, dark: 0xEA93AF),
        Color(light: 0x5E7F9A, dark: 0x9CBBD4)
    ]

    static let taskDo = Color(light: 0xC85D5A, dark: 0xFF8A86)
    static let taskSchedule = Color(light: 0x3E7C9F, dark: 0x79BFE2)
    static let taskDelegate = Color(light: 0xD9912B, dark: 0xF0B85A)
    static let taskDrop = Color(light: 0x4F8A6B, dark: 0x74C69D)
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
