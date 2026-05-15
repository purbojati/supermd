import SwiftUI

// A theme is a single fixed look — there's no per-theme light/dark split.
// Each palette declares whether it reads as light or dark so SwiftUI's
// `preferredColorScheme` can keep the window chrome consistent.

struct PaletteColors {
    let background:     UInt32
    let sidebar:        UInt32
    let surface:        UInt32
    let elevated:       UInt32
    let accent:         UInt32
    let text:           UInt32
    let secondaryText:  UInt32
    let tertiaryText:   UInt32
    let border:         UInt32
    let dividerSoft:    UInt32
    let hover:          UInt32
    let activeRow:      UInt32
    let codeBackground: UInt32
    let inlineCodeFill: UInt32
}

enum ThemePalette: String, CaseIterable, Identifiable {
    case rose, crimson, paper, graphite, solar, ocean, midnight, forest

    static let storageKey = "themePalette"

    var id: String { rawValue }

    /// Persisted current selection. Falls back to `.rose`.
    static var current: ThemePalette {
        ThemePalette(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .rose
    }

    var emoji: String {
        switch self {
        case .rose:     return "🌸"
        case .crimson:  return "🌹"
        case .paper:    return "📜"
        case .graphite: return "⬛"
        case .solar:    return "☀️"
        case .ocean:    return "🌊"
        case .midnight: return "🌙"
        case .forest:   return "🌲"
        }
    }

    var title: String {
        switch self {
        case .rose:     return "Rose"
        case .crimson:  return "Crimson"
        case .paper:    return "Paper"
        case .graphite: return "Graphite"
        case .solar:    return "Solar"
        case .ocean:    return "Ocean"
        case .midnight: return "Midnight"
        case .forest:   return "Forest"
        }
    }

    /// Tells SwiftUI which `preferredColorScheme` to apply so the
    /// title bar / system controls match the theme's brightness.
    var preferredColorScheme: ColorScheme {
        switch self {
        case .crimson, .graphite, .midnight: return .dark
        default: return .light
        }
    }

    var colors: PaletteColors {
        switch self {
        case .rose:
            // Warm pink, the original SuperMD palette.
            return PaletteColors(
                background:     0xFDF5F8,
                sidebar:        0xF6E6ED,
                surface:        0xF9ECF1,
                elevated:       0xFFFAFC,
                accent:         0xC2185B,
                text:           0x2A141D,
                secondaryText:  0x6F4A57,
                tertiaryText:   0x95707D,
                border:         0xE7CFD9,
                dividerSoft:    0xEAD3DD,
                hover:          0xEFD4DE,
                activeRow:      0xF1CCDB,
                codeBackground: 0xF6E2EB,
                inlineCodeFill: 0xEED3DD
            )
        case .crimson:
            // Dark rose — the original dark theme.
            return PaletteColors(
                background:     0x171015,
                sidebar:        0x1E1419,
                surface:        0x22181E,
                elevated:       0x251A21,
                accent:         0xF06AAA,
                text:           0xF1E5EB,
                secondaryText:  0xB39AA5,
                tertiaryText:   0x826D77,
                border:         0x3A2530,
                dividerSoft:    0x2E1E27,
                hover:          0x2D1F26,
                activeRow:      0x3F1F2C,
                codeBackground: 0x1D1218,
                inlineCodeFill: 0x3A2330
            )
        case .paper:
            // Clean off-white with indigo accent — minimal & readable.
            return PaletteColors(
                background:     0xFAFAFA,
                sidebar:        0xF1F2F4,
                surface:        0xF4F5F7,
                elevated:       0xFFFFFF,
                accent:         0x4F46E5,
                text:           0x111317,
                secondaryText:  0x4B5563,
                tertiaryText:   0x6B7280,
                border:         0xE0E2E6,
                dividerSoft:    0xE7E9EC,
                hover:          0xE9EBEE,
                activeRow:      0xDFE2E7,
                codeBackground: 0xEEF0F4,
                inlineCodeFill: 0xE1E5EC
            )
        case .graphite:
            // Neutral dark grays with cool violet accent.
            return PaletteColors(
                background:     0x121417,
                sidebar:        0x171A1E,
                surface:        0x1B1E23,
                elevated:       0x1F2329,
                accent:         0x8B8CF7,
                text:           0xE5E7EB,
                secondaryText:  0x9CA3AF,
                tertiaryText:   0x6B7280,
                border:         0x2A2E35,
                dividerSoft:    0x232730,
                hover:          0x252932,
                activeRow:      0x2C3140,
                codeBackground: 0x161A1F,
                inlineCodeFill: 0x282C34
            )
        case .solar:
            // Warm cream + amber, Solarized-flavored.
            return PaletteColors(
                background:     0xFDF6E3,
                sidebar:        0xF5EBD0,
                surface:        0xF8EFD8,
                elevated:       0xFFFAEC,
                accent:         0xB45309,
                text:           0x3B2A14,
                secondaryText:  0x6B5235,
                tertiaryText:   0x8F7654,
                border:         0xE6D7AE,
                dividerSoft:    0xEADEB7,
                hover:          0xEFE2B8,
                activeRow:      0xEDD89F,
                codeBackground: 0xF3E7C1,
                inlineCodeFill: 0xE9D9A1
            )
        case .ocean:
            // Cool blue light theme.
            return PaletteColors(
                background:     0xF1F6FB,
                sidebar:        0xE2ECF6,
                surface:        0xE9F1F8,
                elevated:       0xF7FAFD,
                accent:         0x0369A1,
                text:           0x0E1F2E,
                secondaryText:  0x466178,
                tertiaryText:   0x6C8298,
                border:         0xCBDAE8,
                dividerSoft:    0xD3DEEB,
                hover:          0xDAE5F0,
                activeRow:      0xC7D9EC,
                codeBackground: 0xE0EAF4,
                inlineCodeFill: 0xCFDDED
            )
        case .midnight:
            // Deep navy dark theme with sky accent.
            return PaletteColors(
                background:     0x0E141C,
                sidebar:        0x131A24,
                surface:        0x171F2A,
                elevated:       0x1B2430,
                accent:         0x60A5FA,
                text:           0xE2ECF7,
                secondaryText:  0x94AABD,
                tertiaryText:   0x607589,
                border:         0x223044,
                dividerSoft:    0x1B2531,
                hover:          0x1E2937,
                activeRow:      0x223347,
                codeBackground: 0x111722,
                inlineCodeFill: 0x223144
            )
        case .forest:
            // Mossy greens, light.
            return PaletteColors(
                background:     0xF2F7F1,
                sidebar:        0xE3EEE0,
                surface:        0xEAF2E7,
                elevated:       0xF8FBF6,
                accent:         0x166534,
                text:           0x142016,
                secondaryText:  0x4B6657,
                tertiaryText:   0x728B7A,
                border:         0xCEDDC9,
                dividerSoft:    0xD7E1D1,
                hover:          0xDDE7D7,
                activeRow:      0xCBDDC1,
                codeBackground: 0xE0EBDA,
                inlineCodeFill: 0xCDDEC4
            )
        }
    }
}

enum Theme {
    private static var palette: PaletteColors { ThemePalette.current.colors }

    private static func color(_ rgb: UInt32, alpha: Double = 1.0) -> Color {
        let r = Double((rgb >> 16) & 0xff) / 255.0
        let g = Double((rgb >>  8) & 0xff) / 255.0
        let b = Double( rgb        & 0xff) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    // Reading surfaces
    static var background: Color { color(palette.background) }
    static var sidebar:    Color { color(palette.sidebar) }
    static var surface:    Color { color(palette.surface) }
    static var elevated:   Color { color(palette.elevated) }

    // Accent (soft / border variants are alpha tints of accent)
    static var accent:       Color { color(palette.accent) }
    static var accentSoft:   Color {
        color(palette.accent, alpha: ThemePalette.current.preferredColorScheme == .dark ? 0.16 : 0.10)
    }
    static var accentBorder: Color {
        color(palette.accent, alpha: ThemePalette.current.preferredColorScheme == .dark ? 0.60 : 0.55)
    }

    // Text
    static var text:          Color { color(palette.text) }
    static var secondaryText: Color { color(palette.secondaryText) }
    static var tertiaryText:  Color { color(palette.tertiaryText) }

    // Lines & subtle fills
    static var border:      Color { color(palette.border) }
    static var dividerSoft: Color { color(palette.dividerSoft) }
    static var hover:       Color { color(palette.hover) }
    static var activeRow:   Color { color(palette.activeRow) }

    // Code
    static var codeBackground: Color { color(palette.codeBackground) }
    static var inlineCodeFill: Color { color(palette.inlineCodeFill) }

    // Hex strings for HTML (mermaid). Bound to current palette.
    static var backgroundHex:     String { hex(palette.background) }
    static var textHex:           String { hex(palette.text) }
    static var codeBackgroundHex: String { hex(palette.codeBackground) }
    static var accentHex:         String { hex(palette.accent) }
    static var borderHex:         String { hex(palette.border) }
    static var surfaceHex:        String { hex(palette.surface) }
    static var elevatedHex:       String { hex(palette.elevated) }
    static var inlineCodeFillHex: String { hex(palette.inlineCodeFill) }
    static var secondaryTextHex:  String { hex(palette.secondaryText) }

    /// Mermaid theme variables derived from the current palette.
    /// Keeps diagram fills, borders, text, and edge labels in sync with the
    /// selected theme rather than hard-coding the original rose colors.
    static var mermaidThemeVarsJSON: String {
        let bg          = codeBackgroundHex
        let surface     = surfaceHex
        let elevated    = elevatedHex
        let nodeFill    = inlineCodeFillHex
        let accent      = accentHex
        let txt         = textHex
        let mutedTxt    = secondaryTextHex
        let border      = borderHex
        return """
        {
          "background": "\(bg)",
          "primaryColor": "\(nodeFill)",
          "primaryTextColor": "\(txt)",
          "primaryBorderColor": "\(accent)",
          "secondaryColor": "\(surface)",
          "secondaryTextColor": "\(txt)",
          "secondaryBorderColor": "\(accent)",
          "tertiaryColor": "\(elevated)",
          "tertiaryTextColor": "\(txt)",
          "tertiaryBorderColor": "\(border)",
          "lineColor": "\(accent)",
          "textColor": "\(txt)",
          "mainBkg": "\(nodeFill)",
          "nodeBorder": "\(accent)",
          "clusterBkg": "\(surface)",
          "clusterBorder": "\(border)",
          "edgeLabelBackground": "\(elevated)",
          "titleColor": "\(accent)",
          "labelTextColor": "\(txt)",
          "actorBkg": "\(nodeFill)",
          "actorBorder": "\(accent)",
          "actorTextColor": "\(txt)",
          "actorLineColor": "\(accent)",
          "signalColor": "\(txt)",
          "signalTextColor": "\(txt)",
          "labelBoxBkgColor": "\(elevated)",
          "labelBoxBorderColor": "\(accent)",
          "noteBkgColor": "\(elevated)",
          "noteTextColor": "\(txt)",
          "noteBorderColor": "\(border)",
          "activationBkgColor": "\(nodeFill)",
          "activationBorderColor": "\(accent)"
        }
        """
    }

    private static func hex(_ rgb: UInt32) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }
}
