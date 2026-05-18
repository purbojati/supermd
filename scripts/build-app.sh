#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SuperMD"
BUNDLE_ID="com.github.supermd"
BUILD_DIR=".build"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

# Sparkle.framework lives at @rpath/Sparkle.framework at runtime; we add
# @executable_path/../Frameworks to the rpath so the embedded copy resolves.
RPATH_FLAGS=(-Xlinker -rpath -Xlinker "@executable_path/../Frameworks")

echo "==> Building $APP_NAME for arm64 + x86_64 (release)"
swift build -c release --arch arm64  "${RPATH_FLAGS[@]}"
swift build -c release --arch x86_64 "${RPATH_FLAGS[@]}"

ARM_BIN="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
X86_BIN="$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME"

if [[ ! -f "$ARM_BIN" || ! -f "$X86_BIN" ]]; then
  echo "error: missing built binaries" >&2
  exit 1
fi

UNIVERSAL_DIR="$BUILD_DIR/universal"
mkdir -p "$UNIVERSAL_DIR"
echo "==> Creating universal binary"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNIVERSAL_DIR/$APP_NAME"

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp "$UNIVERSAL_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Embedding Sparkle.framework"
SPARKLE_XCFW="$(find "$BUILD_DIR/artifacts" -type d -name Sparkle.xcframework -print -quit 2>/dev/null || true)"
if [[ -z "${SPARKLE_XCFW:-}" ]]; then
  echo "error: Sparkle.xcframework not found under $BUILD_DIR/artifacts" >&2
  echo "       run 'swift package resolve' first" >&2
  exit 1
fi
SPARKLE_SLICE="$SPARKLE_XCFW/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_SLICE" ]]; then
  # Some Sparkle builds use a different slice directory name; pick the only macOS one.
  SPARKLE_SLICE="$(find "$SPARKLE_XCFW" -maxdepth 2 -type d -name Sparkle.framework -path '*macos*' -print -quit)"
fi
if [[ ! -d "$SPARKLE_SLICE" ]]; then
  echo "error: no macOS slice of Sparkle.framework inside $SPARKLE_XCFW" >&2
  exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
cp -R "$SPARKLE_SLICE" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Build the .icns variants from their iconsets if present so a fresh checkout works.
for variant in "" "-Dark"; do
  ICONSET="Resources/AppIcon${variant}.iconset"
  ICNS="Resources/AppIcon${variant}.icns"
  if [[ -d "$ICONSET" && ( ! -f "$ICNS" || "$ICONSET" -nt "$ICNS" ) ]]; then
    echo "==> Compiling $ICNS from $ICONSET"
    iconutil -c icns "$ICONSET" -o "$ICNS"
  fi
done

# Copy whichever .icns files exist. The runtime app delegate picks light or
# dark to assign to NSApp.applicationIconImage based on system appearance.
for variant in "" "-Dark"; do
  ICNS="Resources/AppIcon${variant}.icns"
  if [[ -f "$ICNS" ]]; then
    cp "$ICNS" "$APP_BUNDLE/Contents/Resources/"
  fi
done

# Identity selection:
#   - If DEVELOPER_ID_IDENTITY is set, use it (e.g. "Developer ID Application: Name (TEAMID)").
#   - Otherwise auto-detect a Developer ID Application identity in the keychain.
#   - If none is found, fall back to ad-hoc (local dev builds).
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ {print $2; exit}')"
fi

ENTITLEMENTS="Resources/SuperMD.entitlements"
if [[ -n "$IDENTITY" ]]; then
  echo "==> Codesigning with: $IDENTITY (hardened runtime, timestamped)"
  # --runtime-version pins the hardened runtime version to 14.0.0 (matching
  # LSMinimumSystemVersion) instead of letting codesign derive it from the
  # active SDK. Without this, building on a beta SDK (e.g. macOS 26) embeds
  # a future runtime version that macOS Sequoia doesn't recognise, causing a
  # "malware" Gatekeeper warning for recipients on macOS 14/15.
  SIGN_ARGS=(--force --options runtime --runtime-version 14.0.0 --timestamp --sign "$IDENTITY")
else
  echo "==> No Developer ID identity found — ad-hoc signing (local dev build)"
  SIGN_ARGS=(--force --sign -)
fi

# Sparkle ships its helpers ad-hoc signed with empty entitlements. We must
# re-sign them with Developer ID + hardened runtime + timestamp. Don't use
# --preserve-metadata: Sparkle's pre-shipped Designated Requirement references
# the adhoc signature, and preserving it drags the adhoc flag back in.
SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  # Sign deepest first: XPC helpers, then Updater.app, then Autoupdate, then
  # the framework wrapper itself.
  # `Versions/Current` is a symlink — use -L so find follows it. Without -L
  # the loop silently iterates zero helpers and they keep Sparkle's original
  # ad-hoc signatures, which notarization rejects.
  while IFS= read -r -d '' helper; do
    codesign "${SIGN_ARGS[@]}" "$helper"
  done < <(find -L "$SPARKLE_FW/Versions/Current" \
              \( -name "*.xpc" -o -name "Autoupdate" -o -name "Updater.app" \) \
              -print0 2>/dev/null)
  codesign "${SIGN_ARGS[@]}" "$SPARKLE_FW"
fi

# Sign the main bundle last with entitlements (only meaningful when we have a real identity).
if [[ -n "$IDENTITY" ]]; then
  codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

if [[ -n "$IDENTITY" ]]; then
  echo "==> Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

echo "==> Zipping for distribution"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip" )

echo ""
echo "✓ Built: $APP_BUNDLE"
echo "✓ Zip:   $ZIP_PATH"
echo ""
echo "Run locally:  open '$APP_BUNDLE'"
