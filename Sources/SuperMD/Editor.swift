import SwiftUI
import AppKit

/// Plain-text Markdown source editor — monospaced, themed, no syntax
/// highlighting. The companion preview lives next to it in `EditorSplitPane`.
struct MarkdownSourceEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .lineSpacing(3)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .scrollContentBackground(.hidden)
            .background(Theme.elevated)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }
}

/// Edit mode for the center pane: source editor on the left, live preview on
/// the right, separated by a draggable divider.
struct EditorSplitPane: View {
    @Binding var text: String
    @Binding var scrollTarget: String?
    let parsed: ParsedMarkdown
    let contentWidth: ContentWidth
    let currentMatchBlockID: String?
    let findQuery: String

    var body: some View {
        HSplitView {
            MarkdownSourceEditor(text: $text)
                .frame(minWidth: 280, idealWidth: 460)
                .background(Theme.elevated)
            MarkdownPaneView(
                parsed: parsed,
                scrollTarget: $scrollTarget,
                contentWidth: contentWidth,
                currentMatchBlockID: currentMatchBlockID,
                findQuery: findQuery
            )
            .frame(minWidth: 320, idealWidth: 520)
        }
    }
}
