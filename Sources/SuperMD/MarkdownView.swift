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

struct MarkdownPaneView: View {
    let parsed: ParsedMarkdown
    @Binding var scrollTarget: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if parsed.blocks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Select a Markdown file")
                            .font(.system(size: 15, weight: .medium, design: Typography.bodyDesign))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(60)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: Typography.blockSpacing) {
                            ForEach(parsed.blocks) { entry in
                                BlockView(markup: entry.markup)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Typography.contentHorizontalPadding)
                        .padding(.vertical, Typography.contentVerticalPadding)
                        .frame(maxWidth: Typography.contentMaxWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
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

    var body: some View {
        switch markup {
        case let heading as Heading:
            HeadingBlockView(heading: heading)
        case let paragraph as Paragraph:
            Text(inlineAttributedString(from: paragraph))
                .font(Typography.body)
                .lineSpacing(Typography.bodyLineSpacing)
                .foregroundStyle(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case let code as CodeBlock:
            if (code.language ?? "").lowercased() == "mermaid" {
                MermaidBlockView(code: code.code)
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
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        default:
            EmptyView()
        }
    }
}

struct HeadingBlockView: View {
    let heading: Heading

    var body: some View {
        Text(inlineAttributedString(from: heading))
            .font(Typography.heading(level: heading.level))
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.top, Typography.headingTopPadding(level: heading.level))
            .padding(.bottom, Typography.headingBottomPadding(level: heading.level))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CodeBlockView: View {
    let codeBlock: CodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = codeBlock.language, !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                .overlay(
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.6))
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code.trimmingCharacters(in: .newlines))
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}

struct BlockQuoteView: View {
    let quote: BlockQuote

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    BlockView(markup: child)
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 4)
            .foregroundStyle(.secondary)
            .italic()
        }
    }
}

struct ListBlockView: View {
    let items: [ListItem]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(bullet(for: index))
                        .font(ordered
                              ? .system(size: Typography.bodySize, design: Typography.bodyDesign)
                              : .system(size: Typography.bodySize))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(markup: child)
                        }
                    }
                }
            }
        }
    }

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
        return AttributedString(text.string)
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
        s.backgroundColor = Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        return s
    case let link as Markdown.Link:
        var s = inlineAttributedString(from: link)
        if let dest = link.destination, let url = URL(string: dest) {
            s.link = url
            s.foregroundColor = Color.accentColor
            s.underlineStyle = Text.LineStyle.single
        }
        return s
    case let image as Markdown.Image:
        let label = plainText(of: image)
        let display = label.isEmpty ? (image.source ?? "image") : label
        var s = AttributedString("🖼 \(display)")
        s.foregroundColor = Color.secondary
        return s
    case is LineBreak:
        return AttributedString("\n")
    case is SoftBreak:
        return AttributedString(" ")
    case let html as InlineHTML:
        return AttributedString(html.rawHTML)
    default:
        return AttributedString(plainText(of: inline))
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
