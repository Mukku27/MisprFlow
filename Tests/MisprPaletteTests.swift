import Foundation

enum MisprPaletteTests {
    static func run() {
        TestSupport.expectEqual(MFAccentPolicy.kind.rawValue, "multiHue")
        TestSupport.expectEqual(MFPalette.background.light, 0xFAF7EF)
        TestSupport.expectEqual(MFPalette.background.dark, 0x161513)
        TestSupport.expectEqual(MFPalette.ink.light, 0x1C1B18)
        TestSupport.expectEqual(MFPalette.ink.dark, 0xF5F1E3)
        TestSupport.expectEqual(MFPalette.waveform.light, 0xF5F1E3)
        TestSupport.expectEqual(MFPalette.waveform.dark, 0xF5F1E3)
        TestSupport.expectEqual(MFPalette.heat.count, 5)
        TestSupport.expectEqual(MFPalette.heat[3].light, 0x2F8A83)
        TestSupport.expect(
            !MFPalette.heat.contains(where: { $0.light == 0xC99A3A || $0.dark == 0xC99A3A }),
            "Multi-hue heat must not contain amber 0xC99A3A"
        )
        TestSupport.expectEqual(MFPalette.speedLine.light, 0x4C5FE0)
        TestSupport.expectEqual(MFPalette.accent.light, 0x6D5EF5)
        TestSupport.expectEqual(MFPalette.star.light, 0xE2B340)
        TestSupport.expectEqual(MFPalette.recording.light, 0xFF4D6A)
        TestSupport.expectEqual(MFPalette.error.light, 0xC6362C)
        TestSupport.expectEqual(MFPalette.infoFill.light, 0x3D6BF5)
        TestSupport.expectEqual(MFPalette.sidebar.light, 0xE3EEF3)
    }
}
