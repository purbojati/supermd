# SuperMD

A small native macOS Markdown viewer with a three-pane layout: file browser on the left, rendered Markdown in the middle, and a heading-based table of contents on the right.

Built with SwiftUI + Swift Package Manager. **No Xcode required** — just the Command Line Tools.

## Install (end users)

1. Download `SuperMD.zip` from [Releases](../../releases/latest), unzip, and drag `SuperMD.app` to `/Applications`.
2. First launch — because the app isn't signed with a paid Apple Developer ID, macOS Gatekeeper will block it. Either:
   - Right-click `SuperMD.app` → **Open** → **Open**, or
   - Run once in Terminal: `xattr -dr com.apple.quarantine /Applications/SuperMD.app`

## Use

- **⌘O** — open a folder. The sidebar shows every `.md` / `.markdown` / `.mdx` file inside.
- Click a file to render it in the center pane.
- Click a heading in the right pane to scroll to it.
- Code blocks tagged ```` ```mermaid ```` render as diagrams (loads `mermaid.min.js` from the jsdelivr CDN on first render — needs an internet connection for the diagrams; everything else works offline).

## Build from source

Requires macOS 13+ and the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/<you>/supermd.git
cd supermd
./scripts/build-app.sh
open .build/SuperMD.app
```

Or just run it directly without bundling:

```sh
swift run -c release
```

## Releasing

Push a tag like `v0.1.0` and the GitHub Actions workflow at `.github/workflows/release.yml` will build a universal `.app`, zip it, and attach it to a new GitHub Release.

```sh
git tag v0.1.0
git push origin v0.1.0
```

## Project layout

```
Package.swift                   Swift Package manifest
Sources/SuperMD/
  SuperMDApp.swift              @main entry point + commands
  ContentView.swift             3-column NavigationSplitView
  FileBrowser.swift             Left pane (folder tree)
  MarkdownView.swift            Center pane + swift-markdown rendering
  TableOfContents.swift         Right pane (heading list)
Resources/Info.plist            .app bundle metadata
scripts/build-app.sh            Builds a universal .app + .zip
.github/workflows/release.yml   CI build + GitHub Release
```

## Notes on "native look"

Rendering uses SwiftUI primitives (`Text` with `AttributedString`, `List`, `NavigationSplitView`), so the app inherits the system look-and-feel automatically: vibrancy, dark mode, accent color, native scroll bars, the standard open-folder panel, and Mac keyboard shortcuts. Body text is set in the system serif (New York) for comfortable reading; code uses SF Mono. Mermaid diagrams render inside an embedded `WKWebView` per block, sized to fit the diagram. The bundle is ad-hoc codesigned, which is enough to launch locally but won't pass Gatekeeper without quarantine removal — see Install above.
