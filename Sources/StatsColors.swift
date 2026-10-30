import SwiftUI

/// Stats palette (spec §1–3). Fixed hex pairs per appearance; this project
/// has no asset catalog (swiftc-built, no Xcode project), so dynamic colors
/// are built in code. Tweak values here — every consumer follows.
enum StatsColors {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        return Color(nsColor: NSColor(
            name: nil,
            dynamicProvider: { $0.name == .darkAqua ? ns(dark) : ns(light) }
        ))
    }

    /// Heat levels 0 (empty) … 4 (darkest). Index with
    /// `StatsHeatmapCore.bucket(words:maxWords:)`, which guarantees 0…4.
    /// Sourced from `MFPalette` so stats follow the active theme.
    static let heat: [Color] = MFPalette.heat.map { MFColors.color($0) }

    static let streakStroke = MFColors.color(MFPalette.heat[3])
    static let speedLine = MFColors.color(MFPalette.speedLine)
}
