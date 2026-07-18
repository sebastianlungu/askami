#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "--- Generating AppIcon ---"

swift generate_icon.swift

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

generate_sizes() {
    sips -z 16 16 AppIcon.png --out "$ICONSET/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32 AppIcon.png --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32 AppIcon.png --out "$ICONSET/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64 AppIcon.png --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128 AppIcon.png --out "$ICONSET/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256 AppIcon.png --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256 AppIcon.png --out "$ICONSET/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512 AppIcon.png --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512 AppIcon.png --out "$ICONSET/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 AppIcon.png --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1
}

generate_sizes

iconutil -c icns "$ICONSET" -o AppIcon.icns

rm -rf "$ICONSET" AppIcon.png

echo "  AppIcon.icns generated ($(stat -f%z AppIcon.icns) bytes)"
