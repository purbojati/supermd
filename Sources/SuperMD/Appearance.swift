import SwiftUI

/// Borderless ghost icon button used throughout the chrome (sidebar +,
/// find bar close, toolbar, etc.). Defaults to muted neutral, brightens
/// on hover, and switches to a soft theme-tinted background for `isActive`
/// — no system bezel. Honors `.disabled()`.
struct GhostIconButton: View {
    let systemName: String
    var fontSize: CGFloat = 12
    var weight: Font.Weight = .medium
    var size: CGFloat = 22
    var isActive: Bool = false
    var help: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = isEnabled && $0 }
        .help(help ?? "")
    }

    private var foreground: Color {
        if !isEnabled { return Theme.tertiaryText.opacity(0.5) }
        if isActive { return Theme.accent }
        return hovering ? Theme.text : Theme.secondaryText
    }

    private var background: Color {
        if isActive { return Theme.accentSoft }
        if hovering { return Theme.hover }
        return .clear
    }
}

/// Soft tinted pill used for counts, status chips, and small badges.
struct StatusPill: View {
    let text: String
    var emphasized: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(emphasized ? Theme.accent : Theme.pillText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(emphasized ? Theme.accentSoft : Theme.pillFill)
            )
    }
}

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
        .menuStyle(.button)
        .menuIndicator(.hidden)
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
        .menuStyle(.button)
        .menuIndicator(.hidden)
    }
}
