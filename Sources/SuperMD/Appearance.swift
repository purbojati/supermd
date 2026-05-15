import SwiftUI

struct ThemeMenu: View {
    @Binding var raw: String

    private var current: ThemePalette {
        ThemePalette(rawValue: raw) ?? .rose
    }

    var body: some View {
        Menu {
            Picker("Theme", selection: $raw) {
                ForEach(ThemePalette.allCases) { palette in
                    Text("\(palette.emoji)  \(palette.title)")
                        .tag(palette.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(current.emoji)
                .font(.system(size: 14))
        }
        .help("Theme: \(current.title)")
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
