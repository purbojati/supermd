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
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .openFolderRequest, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let openFolderRequest = Notification.Name("supermd.openFolderRequest")
}

// macOS does not yet support per-appearance app icons via .appiconset
// without the new Icon Composer .icon bundle. So we ship both .icns files
// (AppIcon.icns + AppIcon-Dark.icns) and swap the running app's icon
// to match the system appearance — the Dock and About panel update live.
final class SuperMDAppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var appearanceObservation: NSKeyValueObservation?
    private var lightIcon: NSImage?
    private var darkIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lightIcon = loadIcon(named: "AppIcon")
        darkIcon  = loadIcon(named: "AppIcon-Dark")
        applyIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
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
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "SuperMD",
            .applicationVersion: "0.1.1",
            .version: "2",
            .init(rawValue: "Copyright"): "© 2026 Adjie Purbojati · MIT License"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
