import SwiftUI

// MARK: - State

@MainActor
final class QuickOpenState: ObservableObject {
    @Published var visible = false
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published var entries: [FileIndexEntry] = []
    @Published var filtered: [FileIndexEntry] = []
    @Published var selectedIndex: Int = 0

    func open(roots: [URL]) {
        rebuildIndex(roots: roots)
        query = ""
        selectedIndex = 0
        visible = true
    }

    func close() {
        visible = false
        query = ""
    }

    func selectNext() {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % filtered.count
    }

    func selectPrevious() {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + filtered.count) % filtered.count
    }

    var selectedEntry: FileIndexEntry? {
        guard filtered.indices.contains(selectedIndex) else { return nil }
        return filtered[selectedIndex]
    }

    // MARK: Indexing

    private static let mdExts: Set<String> = ["md", "markdown", "mdx", "mdown", "mkd"]

    private func rebuildIndex(roots: [URL]) {
        let fm = FileManager.default
        var out: [FileIndexEntry] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let next = enumerator.nextObject() {
                guard let url = next as? URL else { continue }
                guard Self.mdExts.contains(url.pathExtension.lowercased()) else { continue }
                let rel = relativePath(of: url, in: root)
                out.append(FileIndexEntry(
                    url: url,
                    root: root,
                    relativePath: rel,
                    displayPath: "\(root.lastPathComponent)/\(rel)"
                ))
            }
        }
        out.sort {
            $0.displayPath.localizedCaseInsensitiveCompare($1.displayPath) == .orderedAscending
        }
        entries = out
        refilter()
    }

    private func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.path
        let p = url.path
        if p.hasPrefix(rootPath) {
            return String(p.dropFirst(rootPath.count).drop { $0 == "/" })
        }
        return url.lastPathComponent
    }

    private func refilter() {
        let q = query
        if q.isEmpty {
            filtered = entries
            selectedIndex = 0
            return
        }
        var scored: [(entry: FileIndexEntry, score: Int)] = []
        scored.reserveCapacity(entries.count)
        for entry in entries {
            let nameScore = fuzzyScore(query: q, in: entry.url.lastPathComponent) ?? Int.min
            let pathScore = fuzzyScore(query: q, in: entry.displayPath) ?? Int.min
            let best = max(nameScore, pathScore)
            if best > Int.min {
                scored.append((entry, best))
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.entry.displayPath.localizedCaseInsensitiveCompare($1.entry.displayPath) == .orderedAscending
        }
        filtered = scored.map(\.entry)
        selectedIndex = 0
    }
}

struct FileIndexEntry: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let root: URL
    let relativePath: String
    let displayPath: String
}

// MARK: - Fuzzy scoring

func fuzzyScore(query: String, in candidate: String) -> Int? {
    guard !query.isEmpty else { return 0 }
    let q = query.lowercased()
    let c = candidate.lowercased()
    let cChars = Array(c)

    // Direct substring — strongly preferred. Boost when the match begins
    // at a word boundary.
    if let range = c.range(of: q) {
        let startOffset = c.distance(from: c.startIndex, to: range.lowerBound)
        let boundary: Bool
        if startOffset == 0 {
            boundary = true
        } else {
            let prev = cChars[startOffset - 1]
            boundary = prev == "/" || prev == "-" || prev == "_" || prev == " " || prev == "."
        }
        return 10_000 + (boundary ? 1_000 : 0) - c.count
    }

    // Subsequence fallback.
    var qi = q.startIndex
    var prevMatchedIdx = -2
    var score = 0
    for (i, ch) in cChars.enumerated() {
        guard qi < q.endIndex else { break }
        if ch == q[qi] {
            score += 10
            if i == prevMatchedIdx + 1 { score += 12 }
            if i == 0 {
                score += 8
            } else {
                let prev = cChars[i - 1]
                if prev == "/" || prev == "-" || prev == "_" || prev == " " || prev == "." {
                    score += 8
                }
            }
            prevMatchedIdx = i
            qi = q.index(after: qi)
        }
    }
    guard qi == q.endIndex else { return nil }
    return 1_000 + score - c.count
}

// MARK: - View

struct QuickOpenView: View {
    @ObservedObject var state: QuickOpenState
    let onSelect: (FileIndexEntry) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            results
        }
        .frame(width: 560, height: 460)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)

            TextField("Jump to file", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit {
                    if let entry = state.selectedEntry { onSelect(entry) }
                }
                .onKeyPress(.downArrow) {
                    state.selectNext()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    state.selectPrevious()
                    return .handled
                }

            Text("\(state.filtered.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .monospacedDigit()

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
        if state.entries.isEmpty {
            placeholder("No Markdown files in open folders.")
        } else if state.filtered.isEmpty {
            placeholder("No matches.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(state.filtered.enumerated()), id: \.element.id) { idx, entry in
                            row(entry, isSelected: idx == state.selectedIndex)
                                .id(entry.id)
                                .onTapGesture { onSelect(entry) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: state.selectedIndex) { _, newValue in
                    guard state.filtered.indices.contains(newValue) else { return }
                    let id = state.filtered[newValue].id
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ entry: FileIndexEntry, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Theme.accentSoft : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
