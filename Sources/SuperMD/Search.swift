import SwiftUI
import AppKit
import Markdown

// MARK: - Search state

@MainActor
final class SearchState: ObservableObject {
    @Published var findBarVisible = false
    @Published var findQuery = ""
    @Published var matchBlockIDs: [String] = []
    @Published var currentMatchIndex: Int = 0

    @Published var folderSearchVisible = false
    @Published var folderSearchQuery = ""
    @Published var folderSearchResults: [FolderSearchResult] = []
    @Published var folderSearchInProgress = false

    private var folderSearchTask: Task<Void, Never>?

    var currentMatchBlockID: String? {
        guard matchBlockIDs.indices.contains(currentMatchIndex) else { return nil }
        return matchBlockIDs[currentMatchIndex]
    }

    func openFindBar() {
        findBarVisible = true
    }

    func closeFindBar() {
        findBarVisible = false
        findQuery = ""
        matchBlockIDs = []
        currentMatchIndex = 0
    }

    func updateMatches(in parsed: ParsedMarkdown) {
        let q = findQuery
        guard !q.isEmpty else {
            matchBlockIDs = []
            currentMatchIndex = 0
            return
        }
        let needle = q.lowercased()
        var ids: [String] = []
        for block in parsed.blocks {
            if searchableText(of: block.markup).lowercased().contains(needle) {
                ids.append(block.id)
            }
        }
        matchBlockIDs = ids
        if ids.isEmpty {
            currentMatchIndex = 0
        } else if currentMatchIndex >= ids.count {
            currentMatchIndex = 0
        }
    }

    func nextMatch() {
        guard !matchBlockIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchBlockIDs.count
    }

    func previousMatch() {
        guard !matchBlockIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchBlockIDs.count) % matchBlockIDs.count
    }

    // MARK: Folder search

    func openFolderSearch() {
        folderSearchVisible = true
    }

    func closeFolderSearch() {
        folderSearchVisible = false
    }

    func runFolderSearch(in roots: [URL]) {
        folderSearchTask?.cancel()
        let q = folderSearchQuery
        guard !q.isEmpty else {
            folderSearchResults = []
            folderSearchInProgress = false
            return
        }
        folderSearchInProgress = true
        let snapshot = roots
        folderSearchTask = Task { [weak self] in
            let results = await Self.searchFolders(roots: snapshot, query: q)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.folderSearchQuery == q {
                    self.folderSearchResults = results
                    self.folderSearchInProgress = false
                }
            }
        }
    }

    private static let mdExts: Set<String> = ["md", "markdown", "mdx", "mdown", "mkd"]

    private static func searchFolders(roots: [URL], query: String) async -> [FolderSearchResult] {
        let needle = query.lowercased()
        var results: [FolderSearchResult] = []
        let fm = FileManager.default
        for root in roots {
            if Task.isCancelled { return results }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let next = enumerator.nextObject() {
                if Task.isCancelled { return results }
                guard let url = next as? URL else { continue }
                guard mdExts.contains(url.pathExtension.lowercased()) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let matches = matchesInFile(text: text, needle: needle)
                if !matches.isEmpty {
                    results.append(FolderSearchResult(url: url, root: root, matches: matches))
                }
            }
        }
        results.sort {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
        return results
    }

    private static func matchesInFile(text: String, needle: String) -> [FolderSearchMatch] {
        var out: [FolderSearchMatch] = []
        var lineNum = 0
        text.enumerateLines { line, _ in
            lineNum += 1
            if line.lowercased().contains(needle) {
                out.append(FolderSearchMatch(lineNumber: lineNum, line: line))
            }
        }
        return out
    }
}

struct FolderSearchResult: Identifiable {
    let id = UUID()
    let url: URL
    let root: URL
    let matches: [FolderSearchMatch]
}

struct FolderSearchMatch: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let line: String
}

// MARK: - Searchable plain text (covers code blocks too)

func searchableText(of markup: Markup) -> String {
    if let cb = markup as? CodeBlock { return cb.code }
    if let html = markup as? HTMLBlock { return html.rawHTML }
    if let text = markup as? Markdown.Text { return text.string }
    if let code = markup as? InlineCode { return code.code }
    if let html = markup as? InlineHTML { return html.rawHTML }
    var s = ""
    for child in markup.children {
        s += searchableText(of: child)
        s += " "
    }
    return s
}

// MARK: - Highlight helpers

func applyFindHighlights(_ s: AttributedString, query: String) -> AttributedString {
    guard !query.isEmpty else { return s }
    var result = s
    var cursor = result.startIndex
    while cursor < result.endIndex {
        guard let range = result[cursor..<result.endIndex]
                .range(of: query, options: .caseInsensitive) else { break }
        result[range].backgroundColor = Theme.findHighlight
        result[range].foregroundColor = Theme.text
        cursor = range.upperBound
    }
    return result
}

// MARK: - Environment

private struct FindQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    var findQuery: String {
        get { self[FindQueryKey.self] }
        set { self[FindQueryKey.self] = newValue }
    }
}

// MARK: - Find bar (in-file)

struct FindBar: View {
    @ObservedObject var state: SearchState
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)

            TextField("Find in file", text: $state.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { state.nextMatch() }

            countLabel

            HStack(spacing: 2) {
                Button(action: state.previousMatch) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(state.matchBlockIDs.isEmpty)
                .help("Previous match (⇧⌘G)")
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button(action: state.nextMatch) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(state.matchBlockIDs.isEmpty)
                .help("Next match (⌘G)")
                .keyboardShortcut("g", modifiers: [.command])
            }
            .foregroundStyle(Theme.secondaryText)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.sidebar)
        .overlay(
            Rectangle().fill(Theme.border).frame(height: 1),
            alignment: .bottom
        )
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var countLabel: some View {
        if state.findQuery.isEmpty {
            EmptyView()
        } else if state.matchBlockIDs.isEmpty {
            Text("No results")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
        } else {
            Text("\(state.currentMatchIndex + 1) of \(state.matchBlockIDs.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
    }
}

// MARK: - Folder search panel

struct FolderSearchView: View {
    @ObservedObject var state: SearchState
    let rootURLs: [URL]
    let onSelect: (URL, String) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            results
        }
        .frame(width: 520, height: 560)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search in folders", text: $state.folderSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onChange(of: state.folderSearchQuery) { _, _ in
                    state.runFolderSearch(in: rootURLs)
                }
                .onSubmit { state.runFolderSearch(in: rootURLs) }

            if state.folderSearchInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var results: some View {
        if state.folderSearchQuery.isEmpty {
            placeholder("Type to search Markdown files in open folders.")
        } else if state.folderSearchResults.isEmpty && !state.folderSearchInProgress {
            placeholder("No matches.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(state.folderSearchResults) { result in
                        resultGroup(result)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultGroup(_ result: FolderSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text(displayPath(result))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(result.matches.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Theme.hover)
                    )
            }
            VStack(spacing: 1) {
                ForEach(result.matches.prefix(10)) { match in
                    Button {
                        onSelect(result.url, state.folderSearchQuery)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(match.lineNumber)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(width: 36, alignment: .trailing)
                            Text(highlightedLine(match.line))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.surface)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if result.matches.count > 10 {
                    Text("+ \(result.matches.count - 10) more")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.leading, 50)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func displayPath(_ result: FolderSearchResult) -> String {
        let rootPath = result.root.path
        let urlPath = result.url.path
        if urlPath.hasPrefix(rootPath) {
            let rel = String(urlPath.dropFirst(rootPath.count).drop { $0 == "/" })
            if rel.isEmpty {
                return result.root.lastPathComponent
            }
            return "\(result.root.lastPathComponent)/\(rel)"
        }
        return result.url.lastPathComponent
    }

    private func highlightedLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let attr = AttributedString(trimmed)
        return applyFindHighlights(attr, query: state.folderSearchQuery)
    }
}
