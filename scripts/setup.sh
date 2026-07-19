#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL_DIR="models"
MODEL_FILE="$MODEL_DIR/ggml-base-q5_1.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"
EXPECTED_SIZE=59707625
EXPECTED_SHA256="422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"

echo "=== askami setup ==="

echo "--- Validating system dependencies ---"

check_tool() {
    local name="$1" default="$2" arg="$3"
    local path="${!name:-$default}"
    if ! command -v "$path" >/dev/null 2>&1; then
        path="$(command -v "$name" 2>/dev/null || echo "$default")"
    fi
    if "$path" "$arg" >/dev/null 2>&1; then
        echo "  [OK] $name: $path"
    else
        echo "  [FAIL] $name: not found at $path (set env var or install)"
        return 1
    fi
}

check_tool "swift" "/usr/bin/swift" "--version"
check_tool "xcodebuild" "/usr/bin/xcodebuild" "-version"
check_tool "opencode" "/opt/homebrew/bin/opencode" "--version"
check_tool "whisper-server" "/opt/homebrew/bin/whisper-server" "--help"
check_tool "espeak-ng" "/opt/homebrew/bin/espeak-ng" "--version"

echo ""
echo "--- Model setup ---"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_FILE" ]; then
    echo "  Model file exists: $MODEL_FILE"
    actual_size=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE" 2>/dev/null)
    if [ "$actual_size" -eq "$EXPECTED_SIZE" ]; then
        echo "  Size matches: $actual_size bytes"
        if command -v shasum >/dev/null 2>&1; then
            actual_sha=$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)
        else
            actual_sha=$(sha256sum "$MODEL_FILE" | cut -d' ' -f1)
        fi
        if [ "$actual_sha" = "$EXPECTED_SHA256" ]; then
            echo "  SHA-256 verified: $actual_sha"
            echo ""
            echo "=== Setup complete ==="
            exit 0
        else
            echo "  SHA-256 mismatch (expected $EXPECTED_SHA256, got $actual_sha)"
            echo "  Re-downloading..."
        fi
    else
        echo "  Size mismatch (expected $EXPECTED_SIZE, got $actual_size)"
        echo "  Re-downloading..."
    fi
fi

echo "  Downloading model from $MODEL_URL ..."
curl -fL "$MODEL_URL" -o "$MODEL_FILE"

actual_size=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE" 2>/dev/null)
if [ "$actual_size" -ne "$EXPECTED_SIZE" ]; then
    echo "  ERROR: Downloaded size $actual_size does not match expected $EXPECTED_SIZE"
    rm -f "$MODEL_FILE"
    exit 1
fi
echo "  Size verified: $actual_size bytes"

if command -v shasum >/dev/null 2>&1; then
    actual_sha=$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)
else
    actual_sha=$(sha256sum "$MODEL_FILE" | cut -d' ' -f1)
fi
if [ "$actual_sha" != "$EXPECTED_SHA256" ]; then
    echo "  ERROR: SHA-256 mismatch (expected $EXPECTED_SHA256, got $actual_sha)"
    rm -f "$MODEL_FILE"
    exit 1
fi
echo "  SHA-256 verified: $actual_sha"

echo ""
echo "=== Setup complete ==="
