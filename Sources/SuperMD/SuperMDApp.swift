import SwiftUI
import AppKit
import Sparkle

@main
struct SuperMDApp: App {
    @NSApplicationDelegateAdaptor(SuperMDAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SuperMD") {
                    AboutPanel.show()
                }
                Button("Check for Updates…") {
                    appDelegate.updaterController?.checkForUpdates(nil)
                }
                .disabled(appDelegate.updaterController == nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .openFolderRequest, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .findInFileRequest, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Button("Find in Folders…") {
                    NotificationCenter.default.post(name: .folderSearchRequest, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Quick Open…") {
                    NotificationCenter.default.post(name: .quickOpenRequest, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let openFolderRequest    = Notification.Name("supermd.openFolderRequest")
    static let findInFileRequest    = Notification.Name("supermd.findInFileRequest")
    static let folderSearchRequest  = Notification.Name("supermd.folderSearchRequest")
    static let quickOpenRequest     = Notification.Name("supermd.quickOpenRequest")
}

// macOS does not yet support per-appearance app icons via .appiconset
// without the new Icon Composer .icon bundle. So we ship both .icns files
// (AppIcon.icns + AppIcon-Dark.icns) and swap the running app's icon
// to match the macOS system appearance — the Dock and About panel update live.
// The icon always follows the system theme, independent of the in-app
// theme palette (the user's chosen palette may force its own color scheme,
// but the Dock icon shouldn't flip with it).
final class SuperMDAppDelegate: NSObject, NSApplicationDelegate {
    // Sparkle requires a valid Info.plist (CFBundleIdentifier + CFBundleVersion).
    // `swift run` launches a bare executable with neither, so skip the updater
    // there and only start it for the real .app bundle produced by build-app.sh.
    let updaterController: SPUStandardUpdaterController? = {
        let info = Bundle.main.infoDictionary
        guard info?["CFBundleIdentifier"] != nil,
              info?["CFBundleVersion"] != nil else {
            return nil
        }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    private var lightIcon: NSImage?
    private var darkIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched as a bare SPM executable (`swift run`) there's no
        // Info.plist, so AppKit defaults to a background activation policy
        // and the window never comes forward. Force a foreground app.
        if Bundle.main.infoDictionary?["CFBundleIdentifier"] == nil {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        lightIcon = loadIcon(named: "AppIcon")
        darkIcon  = loadIcon(named: "AppIcon-Dark")
        applyIcon()

        // The macOS system appearance broadcasts this distributed notification
        // when the user toggles Light/Dark in System Settings, regardless of
        // any per-app `preferredColorScheme` override.
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemAppearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.applyIcon()
        }
    }

    private func loadIcon(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    private func applyIcon() {
        // Read the *system* dark-mode state, not NSApp.effectiveAppearance —
        // the latter follows the in-app theme palette's preferred color scheme.
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        if let image = isDark ? (darkIcon ?? lightIcon) : (lightIcon ?? darkIcon) {
            NSApp.applicationIconImage = image
        }
    }
}

enum AboutPanel {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 380, height: 480))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    @AppStorage(ThemePalette.storageKey) private var themeRaw: String = ThemePalette.rose.rawValue

    private var theme: ThemePalette {
        ThemePalette(rawValue: themeRaw) ?? .rose
    }

    private var versionLine: String {
        let info = Self.versionInfo()
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?) where !s.isEmpty && !b.isEmpty && s != b:
            return "Version \(s)  ·  Build \(b)"
        case let (s?, _) where !s.isEmpty:
            return "Version \(s)"
        default:
            return "Development build"
        }
    }

    /// Tries Bundle.main first (real .app), then falls back to reading
    /// Resources/Info.plist directly from the source tree — so `swift run`
    /// builds also display the real version instead of "Development build".
    private static func versionInfo() -> [String: Any] {
        if let info = Bundle.main.infoDictionary,
           info["CFBundleShortVersionString"] != nil {
            return info
        }
        let pkgRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // .../Sources/SuperMD
            .deletingLastPathComponent()   // .../Sources
            .deletingLastPathComponent()   // package root
        let plistURL = pkgRoot.appendingPathComponent("Resources/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return plist
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
                Text("SuperMD")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.text)
                Text(versionLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Theme.accentSoft)
                    )
                Text("A native macOS Markdown viewer.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            shortcutsCard
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .frame(width: 380, height: 480)
        .background(Theme.background)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shortcuts")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            VStack(spacing: 4) {
                row("⌘O",          "Open folder")
                row("⌘P",          "Quick open")
                row("⌘F",          "Find in file")
                row("⇧⌘F",         "Find in folders")
                row("⌘G / ⇧⌘G",    "Next / previous match")
                row("Esc",          "Close overlay")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func row(_ key: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: 96, alignment: .leading)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text("Created by")
                    .foregroundStyle(Theme.secondaryText)
                Text("Adjie Purbojati")
                    .foregroundStyle(Theme.text)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))

            Link("github.com/purbojati/supermd",
                 destination: URL(string: "https://github.com/purbojati/supermd")!)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)

            Text("© 2026 Adjie Purbojati  ·  MIT License")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 2)
        }
    }
}
