import SwiftUI
import AppKit

struct ContentView: View {
    private static let openFoldersKey = "openFolders"

    @EnvironmentObject private var appDelegate: SuperMDAppDelegate
    @State private var rootURLs: [URL] = ContentView.loadStoredFolders()
    @State private var selectedFile: URL?
    @State private var rawText: String = ""
    @State private var parsed: ParsedMarkdown = ParsedMarkdown(text: "")
    @State private var scrollTargetID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Edit-mode state
    @State private var isEditing: Bool = false
    @State private var isDirty: Bool = false
    @State private var saveTask: Task<Void, Never>? = nil
    /// Brief window during which we ignore file-watcher events, so our own
    /// atomic save doesn't trip a reload that clobbers in-flight edits.
    @State private var ignoreWatcherUntil: Date = .distantPast

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

    /// Binding handed to the editor — every keystroke re-parses, marks dirty,
    /// schedules an autosave, and refreshes find matches. Loading from disk
    /// writes `rawText` directly (not through this setter) so it doesn't
    /// flip the dirty bit.
    private var editorBinding: Binding<String> {
        Binding(
            get: { rawText },
            set: { newValue in
                guard newValue != rawText else { return }
                rawText = newValue
                parsed = ParsedMarkdown(text: newValue)
                isDirty = true
                search.updateMatches(in: parsed)
                scheduleAutoSave()
            }
        )
    }

    private var titleText: String {
        let base = selectedFile?.lastPathComponent ?? "SuperMD"
        return isDirty ? "\(base) — Edited" : base
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
                if isEditing {
                    EditorSplitPane(
                        text: editorBinding,
                        scrollTarget: $scrollTargetID,
                        parsed: parsed,
                        contentWidth: contentWidth,
                        currentMatchBlockID: search.currentMatchBlockID,
                        findQuery: search.findQuery
                    )
                } else {
                    MarkdownPaneView(
                        parsed: parsed,
                        scrollTarget: $scrollTargetID,
                        contentWidth: contentWidth,
                        currentMatchBlockID: search.currentMatchBlockID,
                        findQuery: search.findQuery
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 640)
        } detail: {
            TableOfContentsView(headings: parsed.headings, currentID: scrollTargetID) { id in
                scrollTargetID = id
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        }
        .navigationTitle(titleText)
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
                    toggleEditing()
                } label: {
                    Label(
                        isEditing ? "Editing" : "Edit",
                        systemImage: isEditing ? "pencil.circle.fill" : "pencil"
                    )
                    .foregroundStyle(isEditing ? Theme.accent : Color.primary)
                }
                .disabled(selectedFile == nil)
                .help(isEditing ? "Stop editing (⌘E)" : "Edit (⌘E)")
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
        .animation(.easeOut(duration: 0.15), value: isEditing)
        .onChange(of: selectedFile) { oldValue, newValue in
            // Flush any pending autosave on the file we're leaving.
            if isDirty, oldValue != nil {
                performSaveNow(to: oldValue)
            }
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
            // Our own atomic save fires the watcher — ignore that brief echo.
            if Date() < ignoreWatcherUntil { return }
            // While editing, the editor buffer is the source of truth.
            // Reloading from disk would discard the user's in-progress edits.
            if isEditing { return }
            reloadCurrent()
            search.updateMatches(in: parsed)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            if isDirty { performSaveNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if isDirty { performSaveNow() }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditModeRequest)) { _ in
            toggleEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFileRequest)) { _ in
            performSaveNow()
        }
        .onChange(of: appDelegate.pendingFileURL) { _, url in
            if let url {
                openFile(url)
                appDelegate.pendingFileURL = nil
            }
        }
    }

    // MARK: - File opening

    private func openFile(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        if !rootURLs.contains(parent) {
            rootURLs.append(parent)
        }
        selectedFile = url
    }

    // MARK: - Edit mode

    private func toggleEditing() {
        if isEditing {
            if isDirty { performSaveNow() }
            isEditing = false
        } else {
            guard selectedFile != nil else { return }
            isEditing = true
        }
    }

    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            if Task.isCancelled { return }
            performSaveNow()
        }
    }

    private func performSaveNow(to overrideURL: URL? = nil) {
        saveTask?.cancel()
        saveTask = nil
        guard let url = overrideURL ?? selectedFile else { return }
        guard isDirty else { return }
        do {
            try rawText.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            // Atomic writes use rename, which the watcher reports as
            // .rename → reopen → changed. Skip it for a moment.
            ignoreWatcherUntil = Date().addingTimeInterval(0.6)
        } catch {
            // Lightweight mode: surface failures via the dirty flag (stays on)
            // rather than a modal. The next autosave or ⌘S will retry.
        }
    }

    private func reloadCurrent() {
        guard let url = selectedFile else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        rawText = text
        parsed = ParsedMarkdown(text: text)
        isDirty = false
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
            rawText = ""
            parsed = ParsedMarkdown(text: "")
            isDirty = false
            return
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        rawText = text
        parsed = ParsedMarkdown(text: text)
        isDirty = false
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
