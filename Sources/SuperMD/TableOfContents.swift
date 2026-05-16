import SwiftUI

struct TableOfContentsView: View {
    let headings: [HeadingItem]
    let currentID: String?
    let onSelect: (String) -> Void
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        Group {
            if headings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Outline")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.chromeHeader)
                            .textCase(.uppercase)
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        ForEach(headings) { heading in
                            TOCRow(
                                heading: heading,
                                isActive: heading.id == currentID,
                                onTap: { onSelect(heading.id) }
                            )
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.sidebar)
        .fontDesign(.rounded)
        .navigationTitle("Outline")
    }
}

private struct TOCRow: View {
    let heading: HeadingItem
    let isActive: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Spacer().frame(width: CGFloat(max(0, heading.level - 1)) * 12)
                Text(heading.text)
                    .font(font(for: heading.level))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if isActive { return Theme.text }
        if heading.level <= 2 { return Theme.text }
        return Theme.secondaryText
    }

    private var rowBackground: Color {
        if isActive { return Theme.accentSoft }
        if hovering { return Theme.hover }
        return .clear
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 12.5, weight: .semibold)
        case 2: return .system(size: 12, weight: .medium)
        case 3: return .system(size: 11.5, weight: .regular)
        default: return .system(size: 11, weight: .regular)
        }
    }
}
