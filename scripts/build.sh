#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/星云 · Codex.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
NODE_BIN="/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
if [ ! -x "$NODE_BIN" ]; then NODE_BIN="$(command -v node)"; fi
"$NODE_BIN" scripts/restore-assets.mjs
swiftc -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$BUILD_DIR/module-cache" Sources/App.swift -o "$APP_DIR/Contents/MacOS/LiXingyunSkin"
ditto Assets "$APP_DIR/Contents/Resources/Assets"
ditto runtime "$APP_DIR/Contents/Resources/runtime"
ditto ThirdParty "$APP_DIR/Contents/Resources/ThirdParty"
if [ -f Sources/AppIcon.icns ]; then cp Sources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LiXingyunSkin</string>
<key>CFBundleIdentifier</key><string>local.codex.lixingyun.skin</string>
<key>CFBundleName</key><string>星云 · Codex</string>
<key>CFBundleDisplayName</key><string>星云 · Codex</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
