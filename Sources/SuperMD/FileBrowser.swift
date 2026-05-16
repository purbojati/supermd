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
    @StateObject private var folderWatcher = FolderWatcher()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.dividerSoft)
            content
        }
        .background(Theme.sidebar)
        .fontDesign(.rounded)
        .onAppear {
            rebuildTree()
            folderWatcher.watch(rootURLs)
        }
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
            folderWatcher.watch(new)
        }
        .onReceive(folderWatcher.changed) { _ in
            rebuildTree()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Folders")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.chromeHeader)
            Spacer()
            GhostIconButton(systemName: "plus", help: "Add Folder (⌘O)", action: onAddFolder)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if rootURLs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.tertiaryText)
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
                LazyVStack(alignment: .leading, spacing: 2) {
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

private enum FileTreeLayout {
    /// Distance from FileTreeRow's leading edge to the start of row content.
    /// Mirrors Tolaria: 6px row inset + 12px content inset.
    static let rowInset: CGFloat = 6
    static let contentInset: CGFloat = 12
    /// Icon size matches Tolaria's 17px folder glyph.
    static let iconSize: CGFloat = 17
    static let iconTextGap: CGFloat = 8
    /// Per-depth indent: icon width + gap, so a child's icon column lines up
    /// where the parent's text used to start.
    static let indentPerDepth: CGFloat = iconSize + iconTextGap // 25

    /// X-offset of the vertical connector line for children of a parent at
    /// `parentDepth`, measured from the FileTreeRow leading edge. Centers
    /// through the parent's folder icon.
    static func connectorOffset(forParentDepth parentDepth: Int) -> CGFloat {
        rowInset + contentInset + CGFloat(parentDepth) * indentPerDepth + iconSize / 2 - 0.5
    }
}

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
    private var indent: CGFloat { CGFloat(depth) * FileTreeLayout.indentPerDepth }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            rowButton
            if node.isDirectory, isExpanded, let children = node.children, !children.isEmpty {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Theme.dividerSoft)
                        .frame(width: 1)
                        .padding(.leading, FileTreeLayout.connectorOffset(forParentDepth: depth))

                    VStack(alignment: .leading, spacing: 2) {
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
            HStack(spacing: FileTreeLayout.iconTextGap) {
                Image(systemName: rowIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: FileTreeLayout.iconSize, height: FileTreeLayout.iconSize)
                Text(node.name)
                    .font(.system(size: 13, weight: node.isRoot ? .semibold : .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, FileTreeLayout.contentInset + indent)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, FileTreeLayout.rowInset)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
    }

    private var rowIcon: String {
        if node.isDirectory {
            return (isExpanded || isSelected) ? "folder.fill" : "folder"
        }
        return "doc.text"
    }

    /// Folders use a slightly stronger secondary tone so the swap between
    /// `folder` and `folder.fill` reads clearly; files stay muted.
    private var iconColor: Color {
        if node.isDirectory { return Theme.secondaryText }
        return Theme.tertiaryText
    }

    private var rowBackground: Color {
        if isSelected { return Theme.accentSoft }
        if hovering { return Theme.hover }
        return .clear
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
