import SwiftUI

struct TableOfContentsView: View {
    let headings: [HeadingItem]
    let currentID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Group {
            if headings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Contents")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
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
            }
        }
        .navigationTitle("Contents")
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
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 2)
                Spacer().frame(width: max(0, CGFloat((heading.level - 1) * 12)))
                Text(heading.text)
                    .font(font(for: heading.level))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if isActive { return .accentColor }
        if heading.level <= 2 { return Color(nsColor: .labelColor) }
        return Color(nsColor: .secondaryLabelColor)
    }

    private var rowBackground: Color {
        if isActive { return Color.accentColor.opacity(0.08) }
        if hovering { return Color(nsColor: .quaternaryLabelColor).opacity(0.25) }
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
