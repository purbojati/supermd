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
    @State private var selection: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.dividerSoft)
            content
        }
        .background(Theme.sidebar)
        .onAppear { rebuildTree() }
        .onChange(of: rootURLs) { _, _ in rebuildTree() }
        .onChange(of: selection) { _, newSelection in
            guard let url = newSelection else { return }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir { selectedFile = url }
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
            List(rootNodes, children: \.children, selection: $selection) { node in
                row(for: node)
                    .tag(node.url)
                    .contextMenu { contextMenu(for: node) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func row(for node: FileNode) -> some View {
        HStack(spacing: 7) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
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
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
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
