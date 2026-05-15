import SwiftUI

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?
    var name: String { url.lastPathComponent }
}

struct FileBrowserView: View {
    @Binding var rootURL: URL?
    @Binding var selectedFile: URL?
    @State private var rootNodes: [FileNode] = []
    @State private var selection: URL?

    var body: some View {
        Group {
            if rootURL == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Folder Open")
                        .font(.headline)
                    Text("Use ⌘O to open a folder of Markdown files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rootNodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No Markdown files found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rootNodes, children: \.children, selection: $selection) { node in
                    HStack(spacing: 7) {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundStyle(node.isDirectory ? Color.accentColor.opacity(0.85) : .secondary)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(node.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(node.url)
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: rootURL) { _, newRoot in
            rebuildTree(root: newRoot)
        }
        .onChange(of: selection) { _, newSelection in
            guard let url = newSelection else { return }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir {
                selectedFile = url
            }
        }
        .onAppear {
            rebuildTree(root: rootURL)
        }
    }

    private func rebuildTree(root: URL?) {
        guard let root else {
            rootNodes = []
            return
        }
        rootNodes = loadChildren(of: root)
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
                    nodes.append(FileNode(id: item, url: item, isDirectory: true, children: kids))
                }
            } else if Self.markdownExtensions.contains(item.pathExtension.lowercased()) {
                nodes.append(FileNode(id: item, url: item, isDirectory: false, children: nil))
            }
        }
        return nodes
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdx", "mdown", "mkd"]
}
