#!/usr/bin/env bash
# Local notarized release pipeline. Run on a Mac with:
#   1. A "Developer ID Application" cert in your login keychain.
#   2. A notarytool keychain profile (see README).
#   3. The Sparkle EdDSA private key in your keychain (auto-installed by
#      Sparkle's generate_keys; lives as "https://sparkle-project.org").
#   4. `gh` CLI authenticated.
#
# Usage:  ./scripts/release.sh
# Reads the version from Resources/Info.plist (CFBundleShortVersionString).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="SuperMD"
NOTARY_PROFILE="${NOTARY_PROFILE:-supermd-notary}"
BUILD_DIR=".build"
INFO_PLIST="Resources/Info.plist"
APPCAST="appcast.xml"
DMG_BACKGROUND="Resources/dmg-background.png"
ENTITLEMENTS="Resources/SuperMD.entitlements"

err()  { printf "\033[31merror:\033[0m %s\n" "$*" >&2; exit 1; }
note() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[33mwarning:\033[0m %s\n" "$*"; }

# ---------------------------------------------------------------- preflight --


VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
[[ -n "$VERSION" ]] || err "couldn't read version from $INFO_PLIST"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ -n "$BUILD_NUMBER" ]] || err "couldn't read CFBundleVersion from $INFO_PLIST"
TAG="v$VERSION"
note "Releasing $APP_NAME $TAG"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  err "tag $TAG already exists locally — bump CFBundleShortVersionString in $INFO_PLIST first"
fi

IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$IDENTITY" ]] || err "no Developer ID Application identity found in keychain"
note "Signing identity: $IDENTITY"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || err "notarytool profile '$NOTARY_PROFILE' not found. Set it up with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id ... --team-id ... --password ..."

command -v gh >/dev/null || err "gh CLI not installed (brew install gh)"
gh auth status >/dev/null 2>&1 || err "gh not authenticated (gh auth login)"

if ! command -v create-dmg >/dev/null; then
  note "Installing create-dmg via Homebrew"
  brew install create-dmg
fi

# Resolve Sparkle artifacts (sign_update tool lives under .build/artifacts).
note "Resolving Swift packages"
swift package resolve

SIGN_TOOL="$(find "$BUILD_DIR/artifacts" -name sign_update -type f -perm -u+x -print -quit 2>/dev/null || true)"
[[ -n "$SIGN_TOOL" ]] || err "sign_update tool not found under $BUILD_DIR/artifacts"

# ----------------------------------------------------------------- build ----

note "Building signed .app"
DEVELOPER_ID_IDENTITY="$IDENTITY" ./scripts/build-app.sh

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
[[ -d "$APP_BUNDLE" ]] || err "build-app.sh did not produce $APP_BUNDLE"

# Strip the legacy zip the build script writes; we generate our own below.
rm -f "$BUILD_DIR/$APP_NAME.zip"

# -------------------------------------------------------- notarize the .app --

NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
note "Zipping .app for notarization submission"
rm -f "$NOTARIZE_ZIP"
( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$NOTARIZE_ZIP")" )

note "Submitting .app to Apple notary service (this can take 1–15 min)"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

note "Stapling notarization ticket onto .app"
xcrun stapler staple "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || \
  err "Gatekeeper rejected the stapled .app — check the notarytool log above"

rm -f "$NOTARIZE_ZIP"

# ---------------------------------------------- build the Sparkle update zip --

SPARKLE_ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
note "Building Sparkle update zip: $(basename "$SPARKLE_ZIP")"
rm -f "$SPARKLE_ZIP"
( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$SPARKLE_ZIP")" )

note "Signing Sparkle update with EdDSA key from keychain"
SPARKLE_SIG_ATTRS="$("$SIGN_TOOL" "$SPARKLE_ZIP")"
[[ "$SPARKLE_SIG_ATTRS" == *edSignature* ]] || err "sign_update produced no signature"

# ----------------------------------------------------------------- DMG ------

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
note "Building DMG: $(basename "$DMG_PATH")"
rm -f "$DMG_PATH"

# create-dmg places assets relative to the staging dir. We feed it the .app
# directly and let it add the /Applications symlink.
create-dmg \
  --volname "$APP_NAME $VERSION" \
  --background "$DMG_BACKGROUND" \
  --window-pos 200 200 \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "$APP_NAME.app" 150 200 \
  --app-drop-link 390 200 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_BUNDLE"

note "Signing DMG with Developer ID"
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"

note "Submitting DMG to Apple notary service"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

note "Stapling notarization ticket onto DMG"
xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || \
  err "Gatekeeper rejected the stapled DMG"

# -------------------------------------------------------- appcast update ----

SIZE=$(stat -f%z "$SPARKLE_ZIP")
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
DOWNLOAD_URL="https://github.com/${REPO_SLUG}/releases/download/${TAG}/$(basename "$SPARKLE_ZIP")"

note "Regenerating $APPCAST"
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <link>https://raw.githubusercontent.com/${REPO_SLUG}/main/appcast.xml</link>
    <description>Most recent $APP_NAME updates</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/${REPO_SLUG}/releases/tag/${TAG}</sparkle:releaseNotesLink>
      <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SPARKLE_SIG_ATTRS} />
    </item>
  </channel>
</rss>
EOF

# ----------------------------------------------------------------- done -----

cat <<EOF

$(printf "\033[1;32m✓ Release artifacts ready\033[0m")
  DMG (humans):     $DMG_PATH
  Sparkle zip:      $SPARKLE_ZIP
  Updated appcast:  $APPCAST

Next steps — review the artifacts, then run:

  git add $INFO_PLIST $APPCAST
  git commit -m "Release $TAG"
  git tag $TAG
  git push origin main "$TAG"

  gh release create $TAG \\
    "$DMG_PATH" \\
    "$SPARKLE_ZIP" \\
    --title "$APP_NAME $VERSION" \\
    --generate-notes

EOF
