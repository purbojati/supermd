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
        }
    }
}

extension Notification.Name {
    static let openFolderRequest    = Notification.Name("supermd.openFolderRequest")
    static let findInFileRequest    = Notification.Name("supermd.findInFileRequest")
    static let folderSearchRequest  = Notification.Name("supermd.folderSearchRequest")
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
    static func show() {
        let credits = NSMutableAttributedString()

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = 3
        centered.paragraphSpacing = 6

        func attrs(_ size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: centered
            ]
        }

        credits.append(NSAttributedString(
            string: "A native macOS Markdown viewer with a three-pane layout: folder browser, rendered Markdown, and a heading-based table of contents.\n\n",
            attributes: attrs(11)
        ))

        credits.append(NSAttributedString(string: "Features\n", attributes: attrs(11, weight: .semibold)))
        credits.append(NSAttributedString(
            string: """
            • Multi-folder sidebar with nested Markdown browsing
            • Mermaid diagrams with one-click PNG export
            • Light & dark themes with warm pink accents
            • Heading-synced table of contents
            • Universal binary (Apple Silicon + Intel)

            """,
            attributes: attrs(11)
        ))

        credits.append(NSAttributedString(string: "Created by ", attributes: attrs(11)))
        credits.append(NSAttributedString(
            string: "Adjie Purbojati\n",
            attributes: attrs(11, weight: .semibold)
        ))

        let linkText = "github.com/purbojati/supermd"
        let link = NSMutableAttributedString(string: linkText, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .link: URL(string: "https://github.com/purbojati/supermd")!,
            .paragraphStyle: centered
        ])
        credits.append(link)
        credits.append(NSAttributedString(string: "\n\nBuilt with SwiftUI and apple/swift-markdown.",
                                          attributes: attrs(10, color: .secondaryLabelColor)))

        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? ""
        let buildVersion = info?["CFBundleVersion"] as? String ?? ""

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "SuperMD",
            .applicationVersion: shortVersion,
            .version: buildVersion,
            .init(rawValue: "Copyright"): "© 2026 Adjie Purbojati · MIT License"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
