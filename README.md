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

## Releasing a new version

The whole flow is tag-driven. CI does all the building, signing, and appcast updating — there is **nothing to upload by hand.**

### Per-release checklist

1. Pick the new version, e.g. `0.1.2`. Bump these four strings to match:
   - `Resources/Info.plist` → `CFBundleShortVersionString` (e.g. `0.1.2`) and `CFBundleVersion` (monotonically increasing integer)
   - `Sources/SuperMD/SuperMDApp.swift` → the `.applicationVersion` and `.version` values inside `AboutPanel.show()` (these power the About window)
2. Commit the version bump (plus any other changes going out).
3. Tag and push:
   ```sh
   git tag v0.1.2
   git push origin main
   git push origin v0.1.2
   ```
4. Watch the run:
   ```sh
   gh run watch --workflow=release.yml --exit-status
   ```
5. Verify:
   - Release page: <https://github.com/purbojati/supermd/releases/latest>
   - Appcast: <https://raw.githubusercontent.com/purbojati/supermd/main/appcast.xml> — should list the new `<sparkle:version>` and a valid `sparkle:edSignature`

Within 24 h (or immediately via **SuperMD → Check for Updates…**), every running copy of SuperMD will be offered the update.

### What the CI workflow does

`.github/workflows/release.yml`, on `push` of a `v*` tag:

1. `swift package resolve` (fetches Sparkle's XCFramework + tools).
2. `./scripts/build-app.sh` — builds universal `SuperMD.app`, embeds `Sparkle.framework`, ad-hoc codesigns, zips to `.build/SuperMD.zip`.
3. Signs the zip with EdDSA using the `SPARKLE_PRIVATE_KEY` repo secret → emits `sparkle:edSignature="…"`.
4. Generates `appcast.xml` with a single `<item>` for this version (download URL points at the GitHub Release asset).
5. Commits `appcast.xml` back to `main` as `github-actions[bot]`.
6. Creates the GitHub Release with `SuperMD.zip` attached and auto-generated release notes.

If any step fails the release won't go out, so just re-run the failed job (`gh run rerun <id> --failed`) after fixing.

### Sparkle setup (already done — kept here as a reference)

You only need to do this **once per project.** It's already done for SuperMD, but if you ever rotate the key or fork the repo:

1. `swift package resolve`
2. Generate the keypair (private key lands in your login Keychain):
   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   Copy the printed public key into `Resources/Info.plist` as `SUPublicEDKey`.
3. Export the private key and load it into the `SPARKLE_PRIVATE_KEY` GitHub Actions secret:
   ```sh
   KEY="$(mktemp -u)"
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x "$KEY"
   gh secret set SPARKLE_PRIVATE_KEY --body "$(cat "$KEY")"
   rm -f "$KEY"
   ```
   **Never commit the private key.** If you rotate it, every released app pinned to the old public key will stop accepting updates until users reinstall, so this is rare.

### Where things live

| What                    | Where                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------- |
| EdDSA private key       | Local macOS Keychain (account: `ed25519`) + `SPARKLE_PRIVATE_KEY` GitHub Actions secret    |
| EdDSA public key        | `Resources/Info.plist` → `SUPublicEDKey`                                                  |
| Update feed URL         | `Resources/Info.plist` → `SUFeedURL` (currently raw.githubusercontent.com on `main`)      |
| Released `.zip`         | GitHub Releases, attached to each `v*` tag                                                |
| Live appcast            | `appcast.xml` on `main`, served via raw.githubusercontent.com                             |
| In-app update entry     | `SuperMD → Check for Updates…` (also auto-checks every 24 h)                              |

## Project layout

```
Package.swift                   Swift Package manifest
Sources/SuperMD/
  SuperMDApp.swift              @main entry point + commands + updater
  ContentView.swift             3-column NavigationSplitView
  FileBrowser.swift             Left pane (folder tree)
  MarkdownView.swift            Center pane + swift-markdown rendering
  TableOfContents.swift         Right pane (heading list)
Resources/Info.plist            .app bundle metadata + Sparkle keys
scripts/build-app.sh            Builds a universal .app + .zip, embeds Sparkle
appcast.xml                     Sparkle update feed (served via raw.githubusercontent.com)
.github/workflows/release.yml   CI build + GitHub Release + appcast sign/commit
```

## Notes on "native look"

Rendering uses SwiftUI primitives (`Text` with `AttributedString`, `List`, `NavigationSplitView`), so the app inherits the system look-and-feel automatically: vibrancy, dark mode, accent color, native scroll bars, the standard open-folder panel, and Mac keyboard shortcuts. Body text is set in the system serif (New York) for comfortable reading; code uses SF Mono. Mermaid diagrams render inside an embedded `WKWebView` per block, sized to fit the diagram. The bundle is ad-hoc codesigned, which is enough to launch locally but won't pass Gatekeeper without quarantine removal — see Install above.
