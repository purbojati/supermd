# SuperMD

A small native macOS Markdown viewer with a three-pane layout: file browser on the left, rendered Markdown in the middle, and a heading-based table of contents on the right.

Built with SwiftUI + Swift Package Manager. **No Xcode required** — just the Command Line Tools.

## Install (end users)

1. Download `SuperMD-<version>.dmg` from [Releases](../../releases/latest).
2. Double-click the DMG, drag `SuperMD.app` onto the `Applications` shortcut.
3. Launch it from Launchpad or `/Applications`. The app is signed with a Developer ID and notarized by Apple, so Gatekeeper opens it without warnings.

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

A local build with no Developer ID identity in the keychain falls back to ad-hoc signing automatically. The bundle will launch fine, but won't pass Gatekeeper if you move it off your Mac — that's what `scripts/release.sh` is for.

## Releasing a new version

Releases are produced **locally on a Mac**. The Developer ID certificate and Sparkle private key never leave the keychain — nothing sensitive lives in a GitHub secret. `scripts/release.sh` runs the full pipeline end-to-end:

```
swift build (universal arm64 + x86_64)
    ↓
codesign each Sparkle helper with Developer ID + hardened runtime
    ↓
codesign Sparkle.framework + SuperMD.app (with entitlements)
    ↓
zip → submit to Apple notary service → wait (1–5 min)
    ↓
staple the notarization ticket onto SuperMD.app
    ↓
build the Sparkle update zip from the stapled .app
    ↓
sign the Sparkle zip with the EdDSA key (sign_update)
    ↓
create-dmg → codesign DMG → submit to notary → staple DMG
    ↓
regenerate appcast.xml with new size + EdDSA signature
```

Two notarization submissions happen per release: one for the `.app` (so the staple is embedded in the .app inside both the DMG and the Sparkle zip), and one for the `.dmg` itself (so the DMG ticket is online even before being mounted).

### One-time setup

These steps only need to be done once per Mac.

#### 1. Apple Developer Program membership

You need an active Apple Developer Program account ($99/year individual). Free Apple Developer accounts can't issue Developer ID certificates.

#### 2. Developer ID Application certificate

> ⚠️ Not "Apple Distribution" — that one is for App Store / TestFlight only. For direct downloads you specifically need **Developer ID Application**.

1. Generate a Certificate Signing Request:
   - **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**
   - Email: your Apple ID email
   - Common Name: your name (e.g. `Adjie Purbojati`)
   - CA Email: leave blank
   - Choose **Saved to disk** → save the `.certSigningRequest` somewhere.
2. Go to <https://developer.apple.com/account/resources/certificates/add>.
3. Under **Software**, pick **Developer ID Application** → Continue.
4. Upload the CSR → Continue → Download the resulting `.cer`.
5. Install it into your **login** keychain. Keychain Access's GUI may try to drop it into System Roots, which is read-only, and fail with *"The 'System Roots' keychain cannot be modified."* Use the CLI instead:
   ```sh
   security import ~/Downloads/developerID_application.cer -k ~/Library/Keychains/login.keychain-db
   ```
6. Install Apple's WWDR G3 intermediate certificate if your cert shows up as "not trusted":
   ```sh
   curl -sLo /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
   security import /tmp/AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
   ```
7. Verify the identity is now usable:
   ```sh
   security find-identity -v -p codesigning
   ```
   You should see exactly one line containing `"Developer ID Application: Your Name (TEAMID)"`.

> If `security find-identity` shows the cert but signing later fails with *"The specified item could not be found in the keychain"*, the private key isn't paired with the cert — typically because the CSR was generated on a different Mac than the one importing the cert. Revoke the cert on the Apple portal, generate a fresh CSR on this Mac, and create the cert again.

#### 3. notarytool keychain profile

Apple's notary service is reached via `xcrun notarytool`. Rather than passing credentials on every call, store them once in your keychain as a profile.

1. Generate an **app-specific password** at <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords. Name it something like `SuperMD notary`.
2. Store the credentials as the keychain profile the release script expects:
   ```sh
   xcrun notarytool store-credentials "supermd-notary" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```
   Replace the placeholders with your Apple ID email, your 10-character Team ID (visible at <https://developer.apple.com/account> → Membership), and the app-specific password.
3. Confirm:
   ```sh
   xcrun notarytool history --keychain-profile supermd-notary | head
   ```
   Should print "Successfully received submission history" (empty list on a new account).

To use a different profile name, set `NOTARY_PROFILE=other-name ./scripts/release.sh`.

#### 4. Sparkle EdDSA signing key

Sparkle signs each update zip with an Ed25519 key; clients verify against the embedded `SUPublicEDKey` in `Info.plist`. The private key already lives in your login keychain as a generic password item with service name `https://sparkle-project.org` (it was created by Sparkle's `generate_keys` tool when this project was first set up).

- Verify it's there:
  ```sh
  security find-generic-password -s 'https://sparkle-project.org' >/dev/null && echo "present" || echo "missing"
  ```
- If missing, regenerate. ⚠️ Rotating this key means **every existing installed copy of SuperMD will reject future updates** until users reinstall a build that bundles the new public key, so avoid unless absolutely necessary:
  ```sh
  swift package resolve
  .build/artifacts/sparkle/Sparkle/bin/generate_keys
  # Copy the printed public key into Resources/Info.plist → SUPublicEDKey
  ```

`sign_update` (from Sparkle's tooling, available under `.build/artifacts` after `swift package resolve`) is invoked by `release.sh` automatically and finds the key in the keychain without any extra flags.

#### 5. CLI tooling

```sh
brew install gh                              # for creating the GitHub release
gh auth login                                # authenticate gh once
```

`create-dmg` is auto-installed by `release.sh` the first time it runs.

### Per-release checklist

1. Bump these places to the new version (e.g. `0.1.3`):
   - `Resources/Info.plist` → `CFBundleShortVersionString` (e.g. `0.1.3`) and `CFBundleVersion` (monotonically increasing integer; we use the same value as the short version).
   - `Sources/SuperMD/SuperMDApp.swift` → the `.applicationVersion` and `.version` values inside `AboutPanel.show()` (powers the About window).
2. Run the release script. It reads the version from `Info.plist` automatically:
   ```sh
   ./scripts/release.sh
   ```
   Expected runtime: 5–20 minutes (most of it waiting on Apple's notary service). The script refuses to start if the git tag for that version already exists locally — bump the version if so.
3. The script ends with a "✓ Release artifacts ready" banner and prints the exact publish commands. Review the artifacts under `.build/`, then:
   ```sh
   git add Resources/Info.plist Sources/SuperMD/SuperMDApp.swift appcast.xml
   git commit -m "Release v0.1.3"
   git tag v0.1.3
   git push origin main v0.1.3

   gh release create v0.1.3 \
     .build/SuperMD-0.1.3.dmg \
     .build/SuperMD-0.1.3.zip \
     --title "SuperMD 0.1.3" \
     --generate-notes
   ```
4. Verify after publishing:
   - The GitHub release page lists both the `.dmg` (for human downloads) and the `.zip` (Sparkle's update payload).
   - The appcast on `main` resolves: <https://raw.githubusercontent.com/purbojati/supermd/main/appcast.xml> — should show the new `<sparkle:version>` and a valid `sparkle:edSignature`.
   - Spot-check Gatekeeper acceptance locally:
     ```sh
     spctl --assess --type open --context context:primary-signature -v .build/SuperMD-0.1.3.dmg
     spctl --assess --type execute -v .build/SuperMD.app
     ```
     Both should print `accepted` and `source=Notarized Developer ID`.

Within 24h (or immediately if the user picks **SuperMD → Check for Updates…**), every running copy of SuperMD will be offered the update via the Sparkle zip.

### Troubleshooting notarization

The notary service returns `status: Accepted` or `status: Invalid`. On `Invalid`, the release script aborts and the submission ID is printed in the script output (and stored in `.build/release.log`). To get the detailed reason:

```sh
xcrun notarytool log <submission-id> --keychain-profile supermd-notary
```

Submission IDs are persistent on Apple's side — you can re-fetch the log any time. List recent submissions with:

```sh
xcrun notarytool history --keychain-profile supermd-notary
```

The most common failure modes when re-signing Sparkle-bundled apps are:

| Error in the notary log | Likely cause |
| ------------------------ | ------------ |
| `The binary is not signed with a valid Developer ID certificate` on a Sparkle helper (Updater, Autoupdate, Downloader, Installer) | The signing loop in `build-app.sh` didn't reach that helper. Most likely the `find -L` (capital L) flag got dropped — `Versions/Current` is a symlink, and without `-L` the loop silently iterates zero files. Helpers keep Sparkle's ad-hoc signature, which notarization rejects. |
| `The signature does not include a secure timestamp` | Sparkle helpers were re-signed with `--preserve-metadata=...,flags,...` or `--preserve-metadata=...,requirements,...`. Sparkle's pre-shipped Designated Requirement references the ad-hoc signature; preserving it keeps the `adhoc` CodeDirectory flag, which forces the new signature to skip the secure timestamp. Solution: don't use `--preserve-metadata` when re-signing Sparkle helpers — they ship with empty entitlements anyway. |
| `The executable does not have the hardened runtime enabled` | `--options runtime` was missing from a codesign call, or `--preserve-metadata=runtime` is preserving the original (non-hardened) flags. Every helper plus the framework plus the app must have it. |
| `The specified item could not be found in the keychain` when codesigning starts | The Developer ID cert is in the keychain but the private key isn't paired with it — see the CSR caveat in step 2 of the setup. |
| Notarization succeeds but `stapler` fails with "Record not found" / "CloudKit query failed" | You ran `stapler` before the ticket was published. The release script's `notarytool submit --wait` flag prevents this — only relevant if you're running the steps by hand. Wait a minute and retry. |

You can quickly inspect any single signature with:

```sh
codesign -dv --verbose=4 path/to/binary 2>&1 | grep -E "Signature|TeamIdentifier|flags|Authority"
```

A healthy signature looks like:

```
flags=0x10000(runtime)
Signature size=8980
Authority=Developer ID Application: <Your Name> (TEAMID)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
TeamIdentifier=TEAMID
```

If you see `flags=0x10002(adhoc,runtime)`, `Signature=adhoc`, or `TeamIdentifier=not set`, that file is still ad-hoc and will be rejected by notarization.

### Why `scripts/build-app.sh` looks the way it does

A few non-obvious choices in `build-app.sh` came directly from notarization failures during initial setup. If you change this file, preserve these:

1. **`find -L "$SPARKLE_FW/Versions/Current"`** — capital `-L`. The framework uses the conventional macOS layout where `Versions/Current` is a symlink to `Versions/B`. Without `-L`, `find` won't traverse into the symlink and the helper-signing loop silently iterates zero files. The four helpers (`Updater.app`, `Autoupdate`, `Downloader.xpc`, `Installer.xpc`) then keep Sparkle's pre-shipped ad-hoc signatures, and the bundle fails notarization.
2. **No `--preserve-metadata` when re-signing Sparkle helpers.** Sparkle ships its xcframework ad-hoc signed with empty entitlements and a Designated Requirement that references the ad-hoc signature. `--preserve-metadata=requirements` drags that DR back in, which leaves the `adhoc` CodeDirectory flag set on the new signature, which strips the secure timestamp, which fails notarization. The helpers have no entitlements worth preserving.
3. **Sign helpers first, then the framework wrapper, then the app.** codesign needs each nested signature to already exist before it can seal the wrapping bundle. The order in the script: `*.xpc` and `Updater.app` and `Autoupdate` → `Sparkle.framework` → `SuperMD.app`.
4. **`--options runtime --timestamp` on every codesign call** — hardened runtime + secure timestamp are both mandatory for notarization. We pass them explicitly so they don't depend on environment defaults.
5. **Ad-hoc fallback when no Developer ID identity is in the keychain.** `swift run` and local dev builds don't need a certificate.

### Where things live

| What | Where |
| ---- | ----- |
| Developer ID Application certificate | login keychain (`security find-identity -v -p codesigning`) |
| Apple WWDR G3 intermediate | login keychain (installed via `security import`) |
| notarytool keychain profile | login keychain, profile name `supermd-notary` |
| Sparkle EdDSA private key | login keychain, service `https://sparkle-project.org` |
| Sparkle EdDSA public key | `Resources/Info.plist` → `SUPublicEDKey` |
| Sparkle update feed URL | `Resources/Info.plist` → `SUFeedURL` (raw.githubusercontent.com on `main`) |
| Hardened-runtime entitlements | `Resources/SuperMD.entitlements` |
| Released `.dmg` + `.zip` | GitHub Releases, attached to each `v*` tag |
| Live appcast | `appcast.xml` on `main`, served via raw.githubusercontent.com |
| In-app update entry | menu bar → **SuperMD → Check for Updates…** (also auto-checks every 24h) |

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
Resources/SuperMD.entitlements  Hardened-runtime entitlements (for notarization)
Resources/dmg-background.png    DMG installer background (1x + @2x)
scripts/build-app.sh            Builds a universal .app, signs with Developer ID
scripts/release.sh              Notarized release pipeline (DMG + Sparkle zip)
scripts/make-dmg-background.swift  Regenerates the DMG background art
appcast.xml                     Sparkle update feed (served via raw.githubusercontent.com)
```

## Notes on "native look"

Rendering uses SwiftUI primitives (`Text` with `AttributedString`, `List`, `NavigationSplitView`), so the app inherits the system look-and-feel automatically: vibrancy, dark mode, accent color, native scroll bars, the standard open-folder panel, and Mac keyboard shortcuts. Body text is set in the system serif (New York) for comfortable reading; code uses SF Mono. Mermaid diagrams render inside an embedded `WKWebView` per block, sized to fit the diagram. Release builds are signed with a Developer ID and notarized by Apple, so Gatekeeper opens them without any quarantine workaround. Local dev builds (run via `swift run` or `./scripts/build-app.sh` without a Developer ID identity in the keychain) fall back to ad-hoc signing.
