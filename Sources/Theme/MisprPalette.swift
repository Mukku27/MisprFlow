import Foundation

/// Fixed light/dark RGB hex pair. Alpha stays in the theme layer.
struct MFHexPair {
    let light: UInt32
    let dark: UInt32
}

enum MFThemeKind: String {
    case boneOnObsidian
    case warmAmber
    case multiHue
}

enum MFAccentPolicy {
    static let kind: MFThemeKind = .multiHue
}

/// Single source of truth for theme hexes. Shared page/ink/waveform/overlay
/// hexes live once; accent-driven tables switch on `MFAccentPolicy.kind`.
/// Each theme worktree changes only `MFAccentPolicy.kind`.
enum MFPalette {
    // MARK: Shared (all trees)

    static let background = MFHexPair(light: 0xFAF7EF, dark: 0x161513)
    static let ink = MFHexPair(light: 0x1C1B18, dark: 0xF5F1E3)
    static let secondary = MFHexPair(light: 0x6B675E, dark: 0xB8B2A5)
    static let tertiary = MFHexPair(light: 0xA8A29A, dark: 0x8A8478)
    static let waveform = MFHexPair(light: 0xF5F1E3, dark: 0xF5F1E3)
    static let overlayField = MFHexPair(light: 0x161513, dark: 0x161513)
    static let warning = MFHexPair(light: 0xE8930C, dark: 0xE8930C)

    // MARK: Kind-switched tables

    /// Heat levels 0 (empty) … 4 (darkest), 5 steps.
    static var heat: [MFHexPair] {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return [
                MFHexPair(light: 0xE8E2D6, dark: 0x2A2824),
                MFHexPair(light: 0xF0E2C0, dark: 0x4A3E28),
                MFHexPair(light: 0xE0C27A, dark: 0x8A6A32),
                MFHexPair(light: 0xC99A3A, dark: 0xE9C46A),
                MFHexPair(light: 0x1C1B18, dark: 0xF5F1E3),
            ]
        case .multiHue:
            return [
                MFHexPair(light: 0xE7F0EE, dark: 0x1E2A28),
                MFHexPair(light: 0xB7D9D4, dark: 0x234844),
                MFHexPair(light: 0x6FB5AD, dark: 0x2F6E68),
                MFHexPair(light: 0x2F8A83, dark: 0x4EA39B),
                MFHexPair(light: 0x1A4F4B, dark: 0x8ED4CC),
            ]
        }
    }

    /// Second chart hue. Bone/amber reuse heat step 3; multi-hue is indigo.
    static var speedLine: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0xE0C27A, dark: 0x8A6A32)
        case .multiHue:
            return MFHexPair(light: 0x4C5FE0, dark: 0x9AABFF)
        }
    }

    /// Focus ring, setup step dots, pipeline step-number circle.
    static var accent: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0xC99A3A, dark: 0xE9C46A)
        case .multiHue:
            return MFHexPair(light: 0x6D5EF5, dark: 0xA99BFF)
        }
    }

    static var star: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0xC99A3A, dark: 0xE9C46A)
        case .multiHue:
            return MFHexPair(light: 0xE2B340, dark: 0xF0C85A)
        }
    }

    /// Menu-bar "Recording..." label, stop circle, live recording mark.
    static var recording: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian:
            return MFHexPair(light: 0xFF5A52, dark: 0xFF5A52)
        case .warmAmber:
            return MFHexPair(light: 0xC99A3A, dark: 0xE9C46A)
        case .multiHue:
            return MFHexPair(light: 0xFF4D6A, dark: 0xFF7A8F)
        }
    }

    /// Failure X and other errors. Always distinct from recording in amber/multi-hue.
    static var error: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0xFF5A52, dark: 0xFF5A52)
        case .multiHue:
            return MFHexPair(light: 0xC6362C, dark: 0xFF6B63)
        }
    }

    /// Update-pill fill. Bone/amber use charcoal/bone; multi-hue stays info blue.
    static var infoFill: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0x1C1B18, dark: 0xF5F1E3)
        case .multiHue:
            return MFHexPair(light: 0x3D6BF5, dark: 0x8EABFF)
        }
    }

    /// Update-pill label. Bone/amber mirror the fill; multi-hue is white.
    static var infoText: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return MFHexPair(light: 0xF5F1E3, dark: 0x1C1B18)
        case .multiHue:
            return MFHexPair(light: 0xFFFFFF, dark: 0xFFFFFF)
        }
    }

    static var primaryFill: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian:
            return MFHexPair(light: 0x1C1B18, dark: 0xF5F1E3)
        case .warmAmber:
            return MFHexPair(light: 0xC99A3A, dark: 0xE9C46A)
        case .multiHue:
            return MFHexPair(light: 0x6D5EF5, dark: 0xA99BFF)
        }
    }

    static var primaryText: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian:
            return MFHexPair(light: 0xF5F1E3, dark: 0x1C1B18)
        case .warmAmber:
            return MFHexPair(light: 0x1C1B18, dark: 0x1C1B18)
        case .multiHue:
            return MFHexPair(light: 0xF7F4EC, dark: 0x1C1B18)
        }
    }

    /// Selected-row label. Bone keeps bone text on the ink fill;
    /// amber/multi-hue keep ink in light and bone in dark.
    static var selectionText: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian:
            return MFHexPair(light: 0xF5F1E3, dark: 0xF5F1E3)
        case .warmAmber, .multiHue:
            return ink
        }
    }

    /// Selected-row stroke. Matches the selection wash hue per tree.
    static var selectionStroke: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian:
            return ink
        case .warmAmber, .multiHue:
            return accent
        }
    }

    /// Sidebar surface. Only the multi-hue tree paints the sidebar with this;
    /// bone/amber keep `.ultraThinMaterial`.
    static var sidebar: MFHexPair {
        switch MFAccentPolicy.kind {
        case .boneOnObsidian, .warmAmber:
            return background
        case .multiHue:
            return MFHexPair(light: 0xE3EEF3, dark: 0x1A262C)
        }
    }
}
