#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/desk-toys-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p dist
swift Sources/Artwork.swift "$scratch/artwork"

build_app() {
    local executable="$1" name="$2" bundle_id="$3"
    local app="$scratch/$name.app"
    local iconset="$scratch/$executable.iconset"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"

    for dimension in 16 32 128 256 512; do
        sips -z "$dimension" "$dimension" "$scratch/artwork/$executable.png" \
            --out "$iconset/icon_${dimension}x${dimension}.png" >/dev/null
        sips -z "$((dimension * 2))" "$((dimension * 2))" "$scratch/artwork/$executable.png" \
            --out "$iconset/icon_${dimension}x${dimension}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>$name</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleExecutable</key><string>$executable</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright 2026 muddgrrrl. MIT license.</string>
</dict>
</plist>
PLIST

    for architecture in arm64 x86_64; do
        swiftc -parse-as-library -O -whole-module-optimization -target "$architecture-apple-macos13.0" \
            Sources/DeskKit.swift "Sources/$executable.swift" -o "$scratch/$executable-$architecture"
    done
    lipo -create "$scratch/$executable-arm64" "$scratch/$executable-x86_64" -output "$app/Contents/MacOS/$executable"
    codesign --force --sign - "$app"
    codesign --verify --strict "$app"
    "$app/Contents/MacOS/$executable" --self-test
    ditto -c -k --keepParent "$app" "$scratch/$executable-macOS.zip"
    mv -f "$scratch/$executable-macOS.zip" "dist/$executable-macOS.zip"
}

build_app DeskBell "Desk Bell" io.github.muddgrrrl.deskbell
build_app FocusFuse "Focus Fuse" io.github.muddgrrrl.focusfuse
build_app PromptPocket "Prompt Pocket" io.github.muddgrrrl.promptpocket
( cd dist && shasum -a 256 DeskBell-macOS.zip FocusFuse-macOS.zip PromptPocket-macOS.zip > SHA256SUMS.txt )
