import SwiftUI
import AppKit

// Pink-tinted palette (light + dark) inspired by warm rose AI-chat themes.
// Each color is a single dynamic NSColor that resolves per appearance,
// so SwiftUI gets reactive light/dark switching for free.

extension NSColor {
    fileprivate convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((rgb >> 16) & 0xff) / 255.0
        let g = CGFloat((rgb >>  8) & 0xff) / 255.0
        let b = CGFloat( rgb        & 0xff) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    fileprivate static func dynamic(light: UInt32, dark: UInt32,
                                    lightAlpha: CGFloat = 1.0,
                                    darkAlpha: CGFloat = 1.0) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light,
                           alpha: isDark ? darkAlpha : lightAlpha)
        }
    }
}

enum Theme {
    // Reading surfaces
    static let background      = Color(nsColor: .dynamic(light: 0xFDF5F8, dark: 0x171015))
    static let sidebar         = Color(nsColor: .dynamic(light: 0xF6E6ED, dark: 0x1E1419))
    static let surface         = Color(nsColor: .dynamic(light: 0xF9ECF1, dark: 0x22181E))
    static let elevated        = Color(nsColor: .dynamic(light: 0xFFFAFC, dark: 0x251A21))

    // Pink accent (deep rose in light, hot pink in dark)
    static let accent          = Color(nsColor: .dynamic(light: 0xC2185B, dark: 0xF06AAA))
    static let accentSoft      = Color(nsColor: .dynamic(light: 0xC2185B, dark: 0xF06AAA,
                                                         lightAlpha: 0.10, darkAlpha: 0.16))
    static let accentBorder    = Color(nsColor: .dynamic(light: 0xC2185B, dark: 0xF06AAA,
                                                         lightAlpha: 0.55, darkAlpha: 0.6))

    // Text
    static let text            = Color(nsColor: .dynamic(light: 0x2A141D, dark: 0xF1E5EB))
    static let secondaryText   = Color(nsColor: .dynamic(light: 0x6F4A57, dark: 0xB39AA5))
    static let tertiaryText    = Color(nsColor: .dynamic(light: 0x95707D, dark: 0x826D77))

    // Lines & subtle fills
    static let border          = Color(nsColor: .dynamic(light: 0xE7CFD9, dark: 0x3A2530))
    static let dividerSoft     = Color(nsColor: .dynamic(light: 0xEAD3DD, dark: 0x2E1E27))
    static let hover           = Color(nsColor: .dynamic(light: 0xEFD4DE, dark: 0x2D1F26))
    static let activeRow       = Color(nsColor: .dynamic(light: 0xF1CCDB, dark: 0x3F1F2C))

    // Code
    static let codeBackground  = Color(nsColor: .dynamic(light: 0xF6E2EB, dark: 0x1D1218))
    static let inlineCodeFill  = Color(nsColor: .dynamic(light: 0xEED3DD, dark: 0x3A2330))

    // Hex strings for HTML (mermaid)
    static func backgroundHex(_ scheme: ColorScheme) -> String {
        scheme == .dark ? "#171015" : "#FDF5F8"
    }
    static func textHex(_ scheme: ColorScheme) -> String {
        scheme == .dark ? "#F1E5EB" : "#2A141D"
    }
}
