import SwiftUI
import Markdown

struct HeadingItem: Identifiable, Hashable {
    let id: String
    let level: Int
    let text: String
}

struct ParsedMarkdown {
    let blocks: [BlockEntry]
    let headings: [HeadingItem]

    init(text: String) {
        let document = Document(parsing: text)
        var blocks: [BlockEntry] = []
        var headings: [HeadingItem] = []
        var headingCounter = 0

        for (index, child) in document.children.enumerated() {
            if let heading = child as? Heading {
                headingCounter += 1
                let hid = "h-\(headingCounter)"
                let plain = plainText(of: heading)
                headings.append(HeadingItem(id: hid, level: heading.level, text: plain))
                blocks.append(BlockEntry(id: hid, markup: heading))
            } else {
                blocks.append(BlockEntry(id: "b-\(index)", markup: child))
            }
        }
        self.blocks = blocks
        self.headings = headings
    }
}

struct BlockEntry: Identifiable {
    let id: String
    let markup: Markup
}

private func isMermaidBlock(_ markup: Markup) -> Bool {
    if let cb = markup as? CodeBlock, (cb.language ?? "").lowercased() == "mermaid" {
        return true
    }
    return false
}

struct MarkdownPaneView: View {
    let parsed: ParsedMarkdown
    @Binding var scrollTarget: String?
    let contentWidth: ContentWidth
    // Observed so changing the palette re-evaluates this view (and all
    // `BlockView`s it produces) with fresh `Theme.*` colors.
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        let textColumnWidth = contentWidth.innerWidth
        ScrollViewReader { proxy in
            ScrollView {
                if parsed.blocks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("Select a Markdown file")
                            .font(.system(size: 15, weight: .medium, design: Typography.bodyDesign))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(60)
                } else {
                    LazyVStack(spacing: Typography.blockSpacing) {
                        ForEach(parsed.blocks) { entry in
                            if isMermaidBlock(entry.markup) {
                                // Mermaid manages its own width (follows the text column
                                // by default, expands to full pane when toggled).
                                BlockView(markup: entry.markup, textColumnWidth: textColumnWidth)
                                    .id(entry.id)
                            } else {
                                BlockView(markup: entry.markup, textColumnWidth: textColumnWidth)
                                    .id(entry.id)
                                    .frame(maxWidth: textColumnWidth, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, Typography.gutterPadding)
                    .padding(.vertical, Typography.contentVerticalPadding)
                    .frame(maxWidth: .infinity)
                    // Force LazyVStack to rebuild its mounted rows when the
                    // theme changes — without this, already-visible rows keep
                    // their previously-baked AttributedString colors until
                    // they scroll off-screen and back.
                    .id(_palette)
                }
            }
            .background(Theme.background)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }
}

// MARK: - Block rendering

struct BlockView: View {
    let markup: Markup
    let textColumnWidth: CGFloat
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        switch markup {
        case let heading as Heading:
            HeadingBlockView(heading: heading)
        case let paragraph as Paragraph:
            Text(inlineAttributedString(from: paragraph))
                .font(Typography.body)
                .lineSpacing(Typography.bodyLineSpacing)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case let code as CodeBlock:
            if (code.language ?? "").lowercased() == "mermaid" {
                MermaidBlockView(code: code.code, textColumnWidth: textColumnWidth)
            } else {
                CodeBlockView(codeBlock: code)
            }
        case let quote as BlockQuote:
            BlockQuoteView(quote: quote)
        case let list as UnorderedList:
            ListBlockView(items: Array(list.children.compactMap { $0 as? ListItem }), ordered: false)
        case let list as OrderedList:
            ListBlockView(items: Array(list.children.compactMap { $0 as? ListItem }), ordered: true)
        case is ThematicBreak:
            Divider()
                .padding(.vertical, 12)
        case let html as HTMLBlock:
            Text(html.rawHTML)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled)
        default:
            EmptyView()
        }
    }
}

struct HeadingBlockView: View {
    let heading: Heading
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        Text(inlineAttributedString(from: heading))
            .font(Typography.heading(level: heading.level))
            .foregroundStyle(Theme.text)
            .padding(.top, Typography.headingTopPadding(level: heading.level))
            .padding(.bottom, Typography.headingBottomPadding(level: heading.level))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CodeBlockView: View {
    let codeBlock: CodeBlock
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = codeBlock.language, !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .tracking(0.4)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.inlineCodeFill)
                .overlay(
                    Rectangle()
                        .fill(Theme.border.opacity(0.7))
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code.trimmingCharacters(in: .newlines))
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct BlockQuoteView: View {
    let quote: BlockQuote
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accentBorder)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    BlockView(markup: child, textColumnWidth: textColumnWidth)
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.secondaryText)
            .italic()
        }
    }

    private var textColumnWidth: CGFloat { ContentWidth.normal.innerWidth }
}

struct ListBlockView: View {
    let items: [ListItem]
    let ordered: Bool
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(bullet(for: index))
                        .font(ordered
                              ? .system(size: Typography.bodySize, design: Typography.bodyDesign)
                              : .system(size: Typography.bodySize))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(markup: child, textColumnWidth: textColumnWidth)
                        }
                    }
                }
            }
        }
    }

    private var textColumnWidth: CGFloat { ContentWidth.normal.innerWidth }

    private func bullet(for index: Int) -> String {
        ordered ? "\(index + 1)." : "•"
    }
}

// MARK: - Inline rendering

func inlineAttributedString(from markup: Markup) -> AttributedString {
    var result = AttributedString("")
    for child in markup.children {
        result.append(attributedString(forInline: child))
    }
    return result
}

private func attributedString(forInline inline: Markup) -> AttributedString {
    switch inline {
    case let text as Markdown.Text:
        var s = AttributedString(text.string)
        s.foregroundColor = Theme.text
        return s
    case let emphasis as Emphasis:
        var s = inlineAttributedString(from: emphasis)
        s.inlinePresentationIntent = (s.inlinePresentationIntent ?? []).union(.emphasized)
        return s
    case let strong as Strong:
        var s = inlineAttributedString(from: strong)
        s.inlinePresentationIntent = (s.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
        return s
    case let strike as Strikethrough:
        var s = inlineAttributedString(from: strike)
        s.strikethroughStyle = Text.LineStyle.single
        return s
    case let code as InlineCode:
        var s = AttributedString(code.code)
        s.font = .system(size: Typography.bodySize - 1, design: .monospaced)
        s.backgroundColor = Theme.inlineCodeFill
        s.foregroundColor = Theme.accent
        return s
    case let link as Markdown.Link:
        var s = inlineAttributedString(from: link)
        if let dest = link.destination, let url = URL(string: dest) {
            s.link = url
            s.foregroundColor = Theme.accent
            s.underlineStyle = Text.LineStyle.single
        }
        return s
    case let image as Markdown.Image:
        let label = plainText(of: image)
        let display = label.isEmpty ? (image.source ?? "image") : label
        var s = AttributedString("🖼 \(display)")
        s.foregroundColor = Theme.secondaryText
        return s
    case is LineBreak:
        var s = AttributedString("\n")
        s.foregroundColor = Theme.text
        return s
    case is SoftBreak:
        var s = AttributedString(" ")
        s.foregroundColor = Theme.text
        return s
    case let html as InlineHTML:
        var s = AttributedString(html.rawHTML)
        s.foregroundColor = Theme.text
        return s
    default:
        var s = AttributedString(plainText(of: inline))
        s.foregroundColor = Theme.text
        return s
    }
}

func plainText(of markup: Markup) -> String {
    if let text = markup as? Markdown.Text {
        return text.string
    }
    if let code = markup as? InlineCode {
        return code.code
    }
    var result = ""
    for child in markup.children {
        result += plainText(of: child)
    }
    return result
}
