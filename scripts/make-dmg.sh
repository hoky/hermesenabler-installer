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

mkdir -p dist
hdiutil create -volname "HermesEnabler Installer" -srcfolder "$STAGE" \
  -ov -format UDZO -fs HFS+ "dist/HermesEnabler-Installer-1.0.1-Fixed.dmg"
echo "==> dist/HermesEnabler-Installer-1.0.1-Fixed.dmg"
