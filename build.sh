#!/bin/bash
set -euo pipefail

BUNDLE_NAME="TrickleBar"
APP="${BUNDLE_NAME}.app"
MACOS_DIR="${APP}/Contents/MacOS"
RESOURCES_DIR="${APP}/Contents/Resources"
BINARY="${MACOS_DIR}/${BUNDLE_NAME}"
ARCH="${ARCH:-$(uname -m)}"
TARGET="${ARCH}-apple-macos13.0"
SDK="$(xcrun --show-sdk-path)"
ICON_SOURCE="Assets/AppIcon.png"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"

echo "→ Cleaning…"
rm -rf "${APP}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "→ Building app icon…"
mkdir -p "${ICONSET_DIR}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "$(dirname "${ICONSET_DIR}")"

echo "→ Compiling (${TARGET})…"
swiftc Sources/*.swift \
    -sdk "${SDK}" \
    -target "${TARGET}" \
    -O \
    -o "${BINARY}"

echo "→ Writing Info.plist…"
cat > "${APP}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.abdus.tricklebar</string>
    <key>CFBundleName</key>
    <string>TrickleBar</string>
    <key>CFBundleDisplayName</key>
    <string>TrickleBar</string>
    <key>CFBundleExecutable</key>
    <string>TrickleBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>dev.abdus.tricklebar</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>tricklebar</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "→ Ad-hoc codesigning…"
codesign --force --deep --sign - "${APP}"

echo ""
echo "✓ Built ${APP}"
echo ""
echo "  Open app:   open ${APP}"
echo "  CLI usage:  ${BINARY} https://example.com/file.zip"
echo "  Add to PATH: sudo ln -sf \"\$(pwd)/${BINARY}\" /usr/local/bin/tricklebar"
