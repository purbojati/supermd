import SwiftUI
import AppKit

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let isDirectory: Bool
    let isRoot: Bool
    var children: [FileNode]?
    var name: String { url.lastPathComponent }
}

struct FileBrowserView: View {
    @Binding var rootURLs: [URL]
    @Binding var selectedFile: URL?
    let onAddFolder: () -> Void

    @State private var rootNodes: [FileNode] = []
    @AppStorage("expandedFolders") private var expandedRaw: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.dividerSoft)
            content
        }
        .background(Theme.sidebar)
        .onAppear { rebuildTree() }
        .onChange(of: rootURLs) { old, new in
            // New roots haven't been seen before: expand them by default so
            // users see their contents immediately. Persisted state for any
            // folder already in the set is left untouched.
            let oldPaths = Set(old.map(\.path))
            let newlyAdded = new.map(\.path).filter { !oldPaths.contains($0) }
            if !newlyAdded.isEmpty {
                var current = Self.decode(expandedRaw)
                current.formUnion(newlyAdded)
                expandedRaw = Self.encode(current)
            }
            rebuildTree()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Folders")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            Spacer()
            Button(action: onAddFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Add Folder (⌘O)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if rootURLs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                Text("No folders open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text("Click + or press ⌘O to add a folder.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rootNodes.allSatisfy({ ($0.children ?? []).isEmpty }) {
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Theme.tertiaryText)
                Text("No Markdown files inside.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rootNodes) { node in
                        FileTreeRow(
                            node: node,
                            depth: 0,
                            selectedFile: $selectedFile,
                            expandedPaths: expandedBinding,
                            rootURLs: $rootURLs
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Expansion persistence

    private var expandedBinding: Binding<Set<String>> {
        Binding(
            get: { Self.decode(expandedRaw) },
            set: { expandedRaw = Self.encode($0) }
        )
    }

    private static func encode(_ paths: Set<String>) -> String {
        // Tab is safe — file URLs cannot contain it.
        paths.sorted().joined(separator: "\t")
    }

    private static func decode(_ raw: String) -> Set<String> {
        guard !raw.isEmpty else { return [] }
        return Set(raw.split(separator: "\t").map(String.init))
    }

    // MARK: - Tree

    private func rebuildTree() {
        rootNodes = rootURLs.map { url in
            FileNode(
                id: url,
                url: url,
                isDirectory: true,
                isRoot: true,
                children: loadChildren(of: url)
            )
        }
    }

    private func loadChildren(of url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = contents.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir && !bDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        var nodes: [FileNode] = []
        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let kids = loadChildren(of: item)
                if !kids.isEmpty {
                    nodes.append(FileNode(id: item, url: item, isDirectory: true, isRoot: false, children: kids))
                }
            } else if Self.markdownExtensions.contains(item.pathExtension.lowercased()) {
                nodes.append(FileNode(id: item, url: item, isDirectory: false, isRoot: false, children: nil))
            }
        }
        return nodes
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdx", "mdown", "mkd"]
}

// MARK: - Tree row

private struct FileTreeRow: View {
    let node: FileNode
    let depth: Int
    @Binding var selectedFile: URL?
    @Binding var expandedPaths: Set<String>
    @Binding var rootURLs: [URL]
    @AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue

    @State private var hovering = false

    private var isExpanded: Bool { expandedPaths.contains(node.url.path) }
    private var isSelected: Bool { !node.isDirectory && selectedFile == node.url }
    private var indent: CGFloat { CGFloat(depth) * 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            rowButton
            if node.isDirectory, isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        depth: depth + 1,
                        selectedFile: $selectedFile,
                        expandedPaths: $expandedPaths,
                        rootURLs: $rootURLs
                    )
                }
            }
        }
    }

    private var rowButton: some View {
        Button {
            if node.isDirectory {
                toggleExpanded()
            } else {
                selectedFile = node.url
            }
        } label: {
            HStack(spacing: 6) {
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 10)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: node.isDirectory ? (isExpanded ? "folder.fill" : "folder") : "doc.text")
                    .foregroundStyle(node.isDirectory ? Theme.accent : Theme.secondaryText)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(node.name)
                    .font(.system(size: 13, weight: node.isRoot ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8 + indent)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Theme.activeRow
        } else if hovering {
            Theme.hover
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        if node.isRoot {
            Divider()
            Button("Close Folder") {
                rootURLs.removeAll { $0 == node.url }
                if let selected = selectedFile,
                   selected.path.hasPrefix(node.url.path + "/") {
                    selectedFile = nil
                }
            }
        }
    }

    private func toggleExpanded() {
        let key = node.url.path
        if expandedPaths.contains(key) {
            expandedPaths.remove(key)
        } else {
            expandedPaths.insert(key)
        }
    }
}
