import SwiftUI
import AppKit

/// Semantic colors built from `MFPalette`, same dynamic-provider pattern as
/// StatsColors. Views use these roles, never raw hex, and never switch on
/// `MFThemeKind`.
enum MFColors {
    static func ns(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func nsColor(_ pair: MFHexPair) -> NSColor {
        NSColor(
            name: nil,
            dynamicProvider: { $0.name == .darkAqua ? ns(pair.dark) : ns(pair.light) }
        )
    }

    static func color(_ pair: MFHexPair) -> Color {
        Color(nsColor: nsColor(pair))
    }

    // MARK: Surfaces and text

    static let background: Color = color(MFPalette.background)
    static var backgroundNSColor: NSColor { nsColor(MFPalette.background) }
    static let ink: Color = color(MFPalette.ink)
    static let secondary: Color = color(MFPalette.secondary)
    static let tertiary: Color = color(MFPalette.tertiary)

    /// Shared card: white at 72% in light, #21201C in dark.
    static let card: Color = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: {
            $0.name == .darkAqua ? ns(0x21201C) : NSColor(white: 1, alpha: 0.72)
        }
    ))

    /// Card border: ink at 8% in light, white at 8% in dark.
    static let border: Color = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: {
            $0.name == .darkAqua ? NSColor(white: 1, alpha: 0.08) : ns(0x1C1B18, alpha: 0.08)
        }
    ))

    /// Waveform bars and overlay glyphs. Fixed bone in both appearances.
    static let waveform: Color = color(MFPalette.waveform)
    /// Overlay pill field. Fixed #161513 in both appearances.
    static let overlayField: Color = color(MFPalette.overlayField)

    // MARK: Accent and states

    static let accent: Color = color(MFPalette.accent)
    static let star: Color = color(MFPalette.star)
    static let focus: Color = color(MFPalette.accent)
    static let warning: Color = color(MFPalette.warning)
    static let error: Color = color(MFPalette.error)
    static let recording: Color = color(MFPalette.recording)
    static let infoFill: Color = color(MFPalette.infoFill)
    static let infoText: Color = color(MFPalette.infoText)

    static let primaryFill: Color = color(MFPalette.primaryFill)
    static let primaryText: Color = color(MFPalette.primaryText)

    /// Selection wash: accent at 16% in light, 22% in dark.
    static let selectionFill: Color = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            let dark = appearance.name == .darkAqua
            let hex = dark ? MFPalette.accent.dark : MFPalette.accent.light
            return ns(hex, alpha: dark ? 0.22 : 0.16)
        }
    ))
    static let selectionText: Color = color(MFPalette.selectionText)
    static let selectionStroke: Color = color(MFPalette.selectionStroke)

    /// Cool sidebar surface. Only the multi-hue tree paints with this.
    static let sidebar: Color = color(MFPalette.sidebar)
}

/// Sidebar background. Multi-hue fills the cool sidebar surface.
struct MFSidebarBackground: View {
    var body: some View {
        MFColors.sidebar
    }
}

/// Native fonts. Display is SF Pro Rounded Bold for the two titles that are
/// already rounded; mono keeps the existing text style and weight.
enum MFFont {
    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func mono(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let base = Font.system(style, design: .monospaced)
        if let weight {
            return base.weight(weight)
        }
        return base
    }
}

extension View {
    /// Shared card: radius 12 continuous rounded rect, card fill, 1px border.
    /// No padding inside; callers keep their existing padding.
    func wfCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MFColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MFColors.border, lineWidth: 1)
            )
    }

    /// Filled primary action: primary fill, primary label, radius 8.
    /// Apply only to filled actions (setup continue / primary next, and any
    /// button whose fill is currently Color.blue or Color.accentColor).
    func wfPrimaryButton() -> some View {
        self
            .buttonStyle(.plain)
            .foregroundStyle(MFColors.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MFColors.primaryFill)
            )
    }
}
