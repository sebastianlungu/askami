#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="justasec"
BUNDLE_ID="com.sebastianlungu.justasec"
BUILD_DIR=".build"
ARCH="arm64-apple-macosx"
MODEL="models/ggml-base-q5_1.bin"

echo "=== justasec build ==="

echo "--- Release build ---"
swift build -c release --arch arm64

BINARY="$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT"
if [ ! -f "$BINARY" ]; then
    echo "  ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

if [ ! -f "$MODEL" ]; then
    echo "  ERROR: Model not found at $MODEL. Run bash scripts/setup.sh first."
    exit 1
fi

echo "--- Assembling app bundle ---"
APP_BUNDLE="$BUILD_DIR/$PRODUCT.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Resources/models"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp scripts/Info.plist "$APP_BUNDLE/Contents/"
cp scripts/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
cp scripts/success-chime.wav "$APP_BUNDLE/Contents/Resources/"
cp "$MODEL" "$APP_BUNDLE/Contents/Resources/models/"

# Copy entitlements
echo "  App bundle: $APP_BUNDLE"

echo "--- Code signing (ad-hoc) ---"
codesign --force --sign - \
    --entitlements justasec.entitlements \
    "$APP_BUNDLE"

echo "--- Verification ---"
echo ""
echo "  Bundle contents:"
find "$APP_BUNDLE" -type f
echo ""

codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | head -10 || true
echo ""

plutil -p "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c Print "$APP_BUNDLE/Contents/Info.plist"

echo ""
echo "=== Build complete: $APP_BUNDLE ==="
