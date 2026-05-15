import SwiftUI
import AppKit

struct ContentView: View {
    @State private var rootURL: URL?
    @State private var selectedFile: URL?
    @State private var parsed: ParsedMarkdown = ParsedMarkdown(text: "")
    @State private var scrollTargetID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FileBrowserView(rootURL: $rootURL, selectedFile: $selectedFile)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } content: {
            MarkdownPaneView(parsed: parsed, scrollTarget: $scrollTargetID)
                .navigationSplitViewColumnWidth(min: 400, ideal: 640)
        } detail: {
            TableOfContentsView(headings: parsed.headings, currentID: scrollTargetID) { id in
                scrollTargetID = id
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        }
        .navigationTitle(selectedFile?.lastPathComponent ?? "SuperMD")
        .preferredColorScheme(appearance.preferred)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .help("Open Folder (⌘O)")
            }
            ToolbarItem(placement: .primaryAction) {
                AppearanceMenu(raw: $appearanceRaw)
            }
        }
        .onChange(of: selectedFile) { _, newValue in
            loadMarkdown(from: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequest)) { _ in
            openFolder()
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder containing Markdown files"
        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            selectedFile = nil
            parsed = ParsedMarkdown(text: "")
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
}
