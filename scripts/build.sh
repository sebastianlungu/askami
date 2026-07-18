#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="justasec"
BUNDLE_ID="com.sebastianlungu.justasec"
BUILD_DIR=".build"
ARCH="arm64-apple-macosx"
RELEASE_DIR="$BUILD_DIR/$ARCH/release"
MODEL="models/ggml-base-q5_1.bin"
SIGN_IDENTITY="${SIGN_IDENTITY:-JustASec Dev}"
LOGIN_KEYCHAIN="${LOGIN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

ensure_signing_identity() {
    if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
        return
    fi

    echo "--- Provisioning stable signing identity: $SIGN_IDENTITY ---"
    local signing_dir key cert archive password
    signing_dir="$(mktemp -d "${TMPDIR:-/tmp}/justasec-signing.XXXXXX")"
    key="$signing_dir/key.pem"
    cert="$signing_dir/cert.pem"
    archive="$signing_dir/identity.p12"
    password="$(openssl rand -hex 16)"
    trap "rm -rf '$signing_dir'" EXIT

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$key" -out "$cert" -days 7300 -nodes \
        -subj "/CN=$SIGN_IDENTITY" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE"
    openssl pkcs12 -export -legacy \
        -out "$archive" -inkey "$key" -in "$cert" \
        -passout "pass:$password" >/dev/null 2>&1
    security import "$archive" -k "$LOGIN_KEYCHAIN" -P "$password" \
        -T /usr/bin/codesign >/dev/null
    security add-trusted-cert -r trustRoot -k "$LOGIN_KEYCHAIN" "$cert" >/dev/null 2>&1 || true

    if ! security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
        echo "  ERROR: Failed to provision signing identity: $SIGN_IDENTITY"
        exit 1
    fi
}

echo "=== justasec build ==="

ensure_signing_identity

echo "--- Release build ---"
swift build -c release --arch arm64

BINARY="$RELEASE_DIR/$PRODUCT"
if [ ! -f "$BINARY" ]; then
    echo "  ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

if [ ! -f "$MODEL" ]; then
    echo "  ERROR: Model not found at $MODEL. Run bash scripts/setup.sh first."
    exit 1
fi

KOKORO_BUNDLE="$RELEASE_DIR/KokoroCoreML_KokoroCoreML.bundle"
BARTG2P_BUNDLE="$RELEASE_DIR/swift-bart-g2p_BARTG2P.bundle"
if [ ! -d "$KOKORO_BUNDLE" ]; then
    echo "  ERROR: KokoroCoreML resource bundle not found at $KOKORO_BUNDLE"
    exit 1
fi
if [ ! -d "$BARTG2P_BUNDLE" ]; then
    echo "  ERROR: BARTG2P resource bundle not found at $BARTG2P_BUNDLE"
    exit 1
fi
echo "  Resource bundles: KokoroCoreML + BARTG2P"

echo "--- Assembling app bundle ---"
APP_BUNDLE="$BUILD_DIR/$PRODUCT.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Resources/models"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp scripts/Info.plist "$APP_BUNDLE/Contents/"
cp scripts/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
echo "--- Validating ready-chime ---"
CHIME_SRC="scripts/ready-chime.mp3"
CHIME_HASH_EXPECTED="3244c21a0ff72ab70cc2438a22f5e5655f0b11586063e7dded14cae51a6c6ac8"
CHIME_HASH_ACTUAL="$(shasum -a 256 "$CHIME_SRC" | cut -d' ' -f1)"
if [ "$CHIME_HASH_EXPECTED" != "$CHIME_HASH_ACTUAL" ]; then
    echo "  ERROR: ready-chime hash mismatch"
    echo "    expected: $CHIME_HASH_EXPECTED"
    echo "    actual:   $CHIME_HASH_ACTUAL"
    exit 1
fi
echo "  ready-chime hash verified"

cp "$CHIME_SRC" "$APP_BUNDLE/Contents/Resources/"
cp "$MODEL" "$APP_BUNDLE/Contents/Resources/models/"
cp -R "$KOKORO_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
cp -R "$BARTG2P_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

echo "  App bundle: $APP_BUNDLE"

echo "--- Code signing ($SIGN_IDENTITY) ---"
codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --options runtime \
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
