#!/usr/bin/env bash
set -e

# ==============================================================================
# 💽 OtterKeep DMG Creator
# Builds OtterKeep.app and packages it into a distributable, compressed .dmg file.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-1.1.0}"
CONFIGURATION="${2:-release}"
OUTPUT_DIR="$PROJECT_ROOT/.build/dist/"
DMG_NAME="OtterKeep-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "======================================================="
echo "💽 Creating OtterKeep DMG installer (v$VERSION - $CONFIGURATION)"
echo "   Output: $DMG_PATH"
echo "======================================================="

# 1. Staging directory setup inside .build
STAGING_DIR="$PROJECT_ROOT/.build/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

APP_TARGET_DIR="$STAGING_DIR/app"
mkdir -p "$APP_TARGET_DIR"
mkdir -p "$OUTPUT_DIR"

# 2. Package the .app bundle into staging
echo "📦 1. Building and packaging OtterKeep.app..."
SKIP_REGISTER=1 "$SCRIPT_DIR/package_app.sh" "$CONFIGURATION" "$APP_TARGET_DIR" "$VERSION" "1100"

SOURCE_APP="$APP_TARGET_DIR/OtterKeep.app"
if [ ! -d "$SOURCE_APP" ]; then
    if [ -d "$HOME/Applications/OtterKeep.app" ]; then
        echo "   ℹ️ Using existing build from $HOME/Applications/OtterKeep.app"
        SOURCE_APP="$HOME/Applications/OtterKeep.app"
    else
        echo "❌ Error: OtterKeep.app was not found."
        exit 1
    fi
fi

# 3. Prepare DMG root contents
echo "📂 2. Preparing DMG image contents..."
DMG_ROOT="$STAGING_DIR/dmg_root"
mkdir -p "$DMG_ROOT"

cp -R "$SOURCE_APP" "$DMG_ROOT/OtterKeep.app"
ln -s /Applications "$DMG_ROOT/Applications"

# Optional: Copy README or documentation if desired
if [ -f "$PROJECT_ROOT/LICENSE" ]; then
    cp "$PROJECT_ROOT/LICENSE" "$DMG_ROOT/LICENSE.txt"
fi

# 4. Generate the DMG using macOS native hdiutil
echo "🚀 3. Creating compressed UDZO disk image with hdiutil..."
rm -f "$DMG_PATH"

hdiutil create \
    -volname "OtterKeep" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# 5. Generate SHA256 checksum for DMG
echo "🔒 4. Generating SHA256 checksum for DMG..."
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

# 6. Generate ZIP archive (for Homebrew Cask & Sparkle updates)
echo "📦 5. Creating ZIP archive for Homebrew Cask & Sparkle..."
ZIP_NAME="OtterKeep-${VERSION}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
(cd "$APP_TARGET_DIR" && zip -r -y -q "$ZIP_PATH" "OtterKeep.app")
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "======================================================="
echo "🎉 Distribution artifacts successfully created!"
echo "   DMG:      $DMG_PATH"
echo "   Size:     $(du -h "$DMG_PATH" | cut -f1)"
echo "   SHA256:   $(cat "$DMG_PATH.sha256")"
echo "   ---"
echo "   ZIP:      $ZIP_PATH"
echo "   Size:     $(du -h "$ZIP_PATH" | cut -f1)"
echo "   SHA256:   $(cat "$ZIP_PATH.sha256")"
echo "======================================================="
