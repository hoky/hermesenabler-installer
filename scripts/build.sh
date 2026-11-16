#!/bin/bash
# 构建 hcli（CLI）与 HermesGUI（界面）
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
BUILD_ARCH="$(uname -m)"

echo "==> 构建 hcli"
cargo build --release --locked

echo "==> 构建 GUI"
mkdir -p build
xcrun swiftc -O -target "${BUILD_ARCH}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}" \
  -framework Cocoa -framework SwiftUI gui/main.swift -o build/HermesGUI

echo "==> 组装 .app"
APP=build/HermesEnabler-Fixed.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/HermesGUI "$APP/Contents/MacOS/HermesGUI"
cp target/release/hcli "$APP/Contents/MacOS/hcli"
cp LICENSE THIRD_PARTY_LICENSES.md "$APP/Contents/Resources/"
cp docs/INSTALL.zh-CN.txt "$APP/Contents/Resources/"
if [ -f assets/AppIcon.icns ]; then cp assets/AppIcon.icns "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>HermesEnabler 安装器</string>
    <key>CFBundleDisplayName</key><string>HermesEnabler 修复版</string>
    <key>CFBundleIdentifier</key><string>io.github.hermesenabler.installer.localfix</string>
    <key>CFBundleVersion</key><string>1.0.1</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>CFBundleExecutable</key><string>HermesGUI</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP" || true
codesign --force --deep --sign - "$APP"
echo "==> 完成: $APP"
