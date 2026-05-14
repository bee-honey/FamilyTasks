import SwiftUI

enum AppTheme {
    static let background = Color(hex: 0xF6F2EC)
    static let surface = Color(hex: 0xFFFDF8)
    static let surfaceMuted = Color(hex: 0xEFE8DF)
    static let primary = Color(hex: 0x167C80)
    static let primarySoft = Color(hex: 0xD9EEEA)
    static let success = Color(hex: 0x4F8A6B)
    static let warning = Color(hex: 0xD9912B)
    static let destructive = Color(hex: 0xC85D5A)
    static let ink = Color(hex: 0x242424)

    static let avatarPalette: [Color] = [
        Color(hex: 0x167C80),
        Color(hex: 0x7B6BA8),
        Color(hex: 0xC66F4E),
        Color(hex: 0x4F8A6B),
        Color(hex: 0xB45F7A),
        Color(hex: 0x5E7F9A)
    ]

    static let taskDo = Color(hex: 0xC85D5A)
    static let taskSchedule = Color(hex: 0x3E7C9F)
    static let taskDelegate = Color(hex: 0xD9912B)
    static let taskDrop = Color(hex: 0x4F8A6B)
}

extension Color {
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
