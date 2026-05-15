import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceMenu: View {
    @Binding var raw: String

    private var current: AppearanceMode {
        AppearanceMode(rawValue: raw) ?? .system
    }

    var body: some View {
        Menu {
            Picker("Appearance", selection: $raw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: current.symbol)
        }
        .help("Appearance: \(current.title)")
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

enum ContentWidth: String, CaseIterable, Identifiable {
    case narrow, normal, wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .narrow: return "Narrow"
        case .normal: return "Normal"
        case .wide:   return "Wide"
        }
    }

    var symbol: String {
        switch self {
        case .narrow: return "rectangle.compress.vertical"
        case .normal: return "rectangle"
        case .wide:   return "rectangle.expand.vertical"
        }
    }

    /// Outer page width (text column + horizontal padding on both sides).
    var maxWidth: CGFloat {
        switch self {
        case .narrow: return 600
        case .normal: return 740
        case .wide:   return 920
        }
    }

    /// Width of the text column itself.
    var innerWidth: CGFloat {
        maxWidth - Typography.contentHorizontalPadding * 2
    }
}

struct ContentWidthMenu: View {
    @Binding var raw: String

    private var current: ContentWidth {
        ContentWidth(rawValue: raw) ?? .normal
    }

    var body: some View {
        Menu {
            Picker("Content Width", selection: $raw) {
                ForEach(ContentWidth.allCases) { width in
                    Label(width.title, systemImage: width.symbol)
                        .tag(width.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.left.and.right")
        }
        .help("Content width: \(current.title)")
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
