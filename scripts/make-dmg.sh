#!/bin/bash
# 生成 DMG（ad-hoc 签名，不分发证书）
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/HermesEnabler-Fixed.app
[ -d "$APP" ] || { echo "先运行 scripts/build.sh"; exit 1; }

STAGE=build/dmgstage
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp README.md LICENSE THIRD_PARTY_LICENSES.md "$STAGE/"
cp docs/INSTALL.zh-CN.txt "$STAGE/安装说明.txt"

mkdir -p dist
BUILD_ARCH="$(lipo -archs "$APP/Contents/MacOS/hcli")"
DMG="dist/HermesEnabler-Installer-1.0.1-macOS-${BUILD_ARCH}.dmg"
hdiutil create -volname "HermesEnabler Installer" -srcfolder "$STAGE" \
  -ov -format UDZO -fs HFS+ "$DMG"
echo "==> $DMG"
