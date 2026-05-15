import SwiftUI
import AppKit

struct ContentView: View {
    private static let openFoldersKey = "openFolders"

    @State private var rootURLs: [URL] = ContentView.loadStoredFolders()
    @State private var selectedFile: URL?
    @State private var parsed: ParsedMarkdown = ParsedMarkdown(text: "")
    @State private var scrollTargetID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("contentWidth") private var contentWidthRaw: String = ContentWidth.normal.rawValue
    @AppStorage(ThemePalette.storageKey) private var themeRaw: String = ThemePalette.rose.rawValue

    private var theme: ThemePalette {
        ThemePalette(rawValue: themeRaw) ?? .rose
    }

    private var contentWidth: ContentWidth {
        ContentWidth(rawValue: contentWidthRaw) ?? .normal
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FileBrowserView(
                rootURLs: $rootURLs,
                selectedFile: $selectedFile,
                onAddFolder: openFolder
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } content: {
            MarkdownPaneView(parsed: parsed, scrollTarget: $scrollTargetID, contentWidth: contentWidth)
                .navigationSplitViewColumnWidth(min: 400, ideal: 640)
        } detail: {
            TableOfContentsView(headings: parsed.headings, currentID: scrollTargetID) { id in
                scrollTargetID = id
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        }
        .navigationTitle(selectedFile?.lastPathComponent ?? "SuperMD")
        .preferredColorScheme(theme.preferredColorScheme)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                .help("Open Folder (⌘O)")
            }
            ToolbarItem(placement: .primaryAction) {
                ContentWidthMenu(raw: $contentWidthRaw)
            }
            ToolbarItem(placement: .primaryAction) {
                ThemeMenu(raw: $themeRaw)
            }
        }
        .onChange(of: selectedFile) { _, newValue in
            loadMarkdown(from: newValue)
        }
        .onChange(of: rootURLs) { _, urls in
            UserDefaults.standard.set(urls.map { $0.path }, forKey: Self.openFoldersKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequest)) { _ in
            openFolder()
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more folders containing Markdown files"
        if panel.runModal() == .OK {
            for url in panel.urls where !rootURLs.contains(url) {
                rootURLs.append(url)
            }
        }
    }

    private func loadMarkdown(from url: URL?) {
        guard let url else {
            parsed = ParsedMarkdown(text: "")
            return
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        parsed = ParsedMarkdown(text: text)
        scrollTargetID = nil
    }

    private static func loadStoredFolders() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: openFoldersKey) ?? []
        let fm = FileManager.default
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }
}
