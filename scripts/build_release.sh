#!/usr/bin/env bash
set -e

# ==============================================================================
# 🚀 OtterKeep Release Packaging Script
# Entry point for local and CI/CD release packaging.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-}"
CONFIGURATION="${2:-release}"
BUILD_NUMBER="${3:-}"

if [ -z "$VERSION" ]; then
    echo "❌ Error: Version parameter is required (e.g., 1.3.1)"
    echo "Usage: $0 <version> [configuration] [build_number]"
    exit 1
fi

# Calculate build number if not provided (e.g. 1.3.1 -> 1310, 1.4.0 -> 1400)
if [ -z "$BUILD_NUMBER" ]; then
    CLEAN_VER="${VERSION//./}"
    if [ ${#CLEAN_VER} -eq 3 ]; then
        BUILD_NUMBER="${CLEAN_VER}0"
    elif [ ${#CLEAN_VER} -eq 2 ]; then
        BUILD_NUMBER="${CLEAN_VER}00"
    else
        BUILD_NUMBER="1000"
    fi
fi

echo "======================================================="
echo "📦 Building OtterKeep Release v${VERSION} (Build: ${BUILD_NUMBER})"
echo "   Configuration: ${CONFIGURATION}"
echo "======================================================="

# Execute DMG and bundle builder
"$SCRIPT_DIR/build_dmg.sh" "$VERSION" "$CONFIGURATION" "$BUILD_NUMBER"

OUTPUT_DIR="$PROJECT_ROOT/.build/dist"
DMG_PATH="$OUTPUT_DIR/OtterKeep-${VERSION}.dmg"
ZIP_PATH="$OUTPUT_DIR/OtterKeep-${VERSION}.zip"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ Error: Expected DMG artifact not found at $DMG_PATH"
    exit 1
fi

echo "✅ Release build completed successfully!"
echo "   DMG: $DMG_PATH ($(shasum -a 256 "$DMG_PATH" | awk '{print $1}'))"
if [ -f "$ZIP_PATH" ]; then
    echo "   ZIP: $ZIP_PATH ($(shasum -a 256 "$ZIP_PATH" | awk '{print $1}'))"
fi
