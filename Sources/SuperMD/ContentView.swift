import SwiftUI
import AppKit

struct ContentView: View {
    private static let openFoldersKey = "openFolders"

    @EnvironmentObject private var appDelegate: SuperMDAppDelegate
    @State private var rootURLs: [URL] = ContentView.loadStoredFolders()
    @State private var selectedFile: URL?
    @State private var parsed: ParsedMarkdown = ParsedMarkdown(text: "")
    @State private var scrollTargetID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var search = SearchState()
    @StateObject private var quickOpen = QuickOpenState()
    @StateObject private var watcher = FileWatcher()
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
            VStack(spacing: 0) {
                if search.findBarVisible {
                    FindBar(state: search) {
                        search.closeFindBar()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                MarkdownPaneView(
                    parsed: parsed,
                    scrollTarget: $scrollTargetID,
                    contentWidth: contentWidth,
                    currentMatchBlockID: search.currentMatchBlockID,
                    findQuery: search.findQuery
                )
            }
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
                Button {
                    search.openFolderSearch()
                } label: {
                    Label("Search in Folders", systemImage: "magnifyingglass")
                }
                .help("Search in Folders (⇧⌘F)")
                .disabled(rootURLs.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                ContentWidthMenu(raw: $contentWidthRaw)
            }
            ToolbarItem(placement: .primaryAction) {
                ThemeMenu(raw: $themeRaw)
            }
        }
        .sheet(isPresented: $search.folderSearchVisible) {
            FolderSearchView(
                state: search,
                rootURLs: rootURLs,
                onSelect: { url, query in
                    selectedFile = url
                    search.closeFolderSearch()
                    // Carry the query into the in-file find bar so the user
                    // lands on the file with highlights already applied.
                    search.findQuery = query
                    search.openFindBar()
                },
                onClose: { search.closeFolderSearch() }
            )
        }
        .sheet(isPresented: $quickOpen.visible) {
            QuickOpenView(
                state: quickOpen,
                onSelect: { entry in
                    selectedFile = entry.url
                    quickOpen.close()
                },
                onClose: { quickOpen.close() }
            )
        }
        .animation(.easeOut(duration: 0.15), value: search.findBarVisible)
        .onChange(of: selectedFile) { _, newValue in
            loadMarkdown(from: newValue)
            search.updateMatches(in: parsed)
            watcher.watch(newValue)
        }
        .onChange(of: search.findQuery) { _, _ in
            search.updateMatches(in: parsed)
        }
        .onChange(of: rootURLs) { _, urls in
            UserDefaults.standard.set(urls.map { $0.path }, forKey: Self.openFoldersKey)
        }
        .onAppear {
            watcher.watch(selectedFile)
            if let url = appDelegate.pendingFileURL {
                openFile(url)
                appDelegate.pendingFileURL = nil
            }
        }
        .onReceive(watcher.changed) { _ in
            reloadCurrent()
            search.updateMatches(in: parsed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequest)) { _ in
            openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInFileRequest)) { _ in
            search.openFindBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .folderSearchRequest)) { _ in
            if !rootURLs.isEmpty {
                search.openFolderSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickOpenRequest)) { _ in
            if !rootURLs.isEmpty {
                quickOpen.open(roots: rootURLs)
            }
        }
        .onChange(of: appDelegate.pendingFileURL) { _, url in
            if let url {
                openFile(url)
                appDelegate.pendingFileURL = nil
            }
        }
    }

    private func openFile(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        if !rootURLs.contains(parent) {
            rootURLs.append(parent)
        }
        selectedFile = url
    }

    private func reloadCurrent() {
        guard let url = selectedFile else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        parsed = ParsedMarkdown(text: text)
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
