#!/bin/bash
# Builds ChromeBookmarksSpotlight.app from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ChromeBookmarksSpotlight"
CONFIG="release"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo
echo "Built: $APP_DIR"
echo "Install with:  ./install.sh   (copies it to /Applications and launches it)"
