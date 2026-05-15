#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SuperMD"
BUNDLE_ID="com.github.supermd"
BUILD_DIR=".build"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

echo "==> Building $APP_NAME for arm64 + x86_64 (release)"
swift build -c release --arch arm64
swift build -c release --arch x86_64

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

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" \
      "$APP_BUNDLE/Contents/Info.plist"
fi

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Zipping for distribution"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip" )

echo ""
echo "✓ Built: $APP_BUNDLE"
echo "✓ Zip:   $ZIP_PATH"
echo ""
echo "Run locally:  open '$APP_BUNDLE'"
