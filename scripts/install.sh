#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="justasec"
BUNDLE_ID="com.sebastianlungu.justasec"
SIGN_IDENTITY="${SIGN_IDENTITY:-JustASec Dev}"
BUILD_APP="$PWD/.build/$PRODUCT.app"
APP="/Applications/$PRODUCT.app"

expected_leaf_hash() {
    security find-identity -v -p codesigning |
        sed -n "s/^[[:space:]]*[0-9][0-9]*) \([0-9A-Fa-f]*\) \"$SIGN_IDENTITY\"$/\1/p" |
        sed -n '1p' |
        tr '[:upper:]' '[:lower:]'
}

app_uses_expected_identity() {
    [ -d "$APP" ] || return 1
    local authority requirement leaf_hash
    authority="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | sed -n '1p')"
    requirement="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p' | tr '[:upper:]' '[:lower:]')"
    leaf_hash="$(expected_leaf_hash)"
    [ "$authority" = "$SIGN_IDENTITY" ] &&
        [ -n "$leaf_hash" ] &&
        printf '%s' "$requirement" | grep -Fq "certificate leaf = h\"$leaf_hash\""
}

stop_running_app() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        if ! pgrep -f "^$APP/Contents/MacOS/$PRODUCT$" >/dev/null; then
            break
        fi
        sleep 0.25
    done
    pkill -KILL -f "^$APP/Contents/MacOS/$PRODUCT$" 2>/dev/null || true
    pkill -KILL -f "^/opt/homebrew/bin/whisper-server .*--model $APP/Contents/Resources/models/" 2>/dev/null || true
}

reset_tcc_permissions() {
    echo "--- Signing identity changed; resetting stale TCC permissions ---"
    tccutil reset Microphone "$BUNDLE_ID" || true
    tccutil reset AudioCapture "$BUNDLE_ID" || true
    tccutil reset ScreenCapture "$BUNDLE_ID" || true
    echo "  Re-approve Microphone and Screen & System Audio Recording once after launch."
}

install_app() {
    local staged backup
    staged="/Applications/.$PRODUCT.app.new"
    backup="${TMPDIR:-/tmp}/$PRODUCT.app.backup.$$"
    rm -rf "$staged" "$backup"
    ditto "$BUILD_APP" "$staged"
    codesign --verify --strict --verbose=2 "$staged"

    if [ -d "$APP" ]; then
        mv "$APP" "$backup"
    fi
    if ! mv "$staged" "$APP"; then
        [ ! -d "$backup" ] || mv "$backup" "$APP"
        exit 1
    fi
    if ! codesign --verify --strict --verbose=2 "$APP"; then
        rm -rf "$APP"
        [ ! -d "$backup" ] || mv "$backup" "$APP"
        exit 1
    fi
    rm -rf "$backup"
}

bash scripts/build.sh

identity_changed=false
if ! app_uses_expected_identity; then
    identity_changed=true
fi

stop_running_app
if [ "$identity_changed" = true ]; then
    reset_tcc_permissions
fi

echo "--- Installing $APP ---"
install_app

echo "--- Installed signature ---"
codesign -dv --verbose=4 "$APP" 2>&1 | sed -n '1,12p'
echo ""
echo "=== Install complete. Run: open $APP ==="
