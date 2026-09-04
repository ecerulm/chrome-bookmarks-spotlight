#!/bin/bash
# Installs the built app into /Applications, registers it with Launch Services,
# and starts it. Run ./build_app.sh first.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ChromeBookmarksSpotlight"
SRC="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

if [ ! -d "$SRC" ]; then
    echo "error: $SRC not found. Run ./build_app.sh first." >&2
    exit 1
fi

echo "==> Stopping any running instance"
pkill -x "$APP_NAME" 2>/dev/null || true

if [ -x "$DEST/Contents/MacOS/$APP_NAME" ]; then
    echo "==> Clearing existing Spotlight bookmarks"
    "$DEST/Contents/MacOS/$APP_NAME" --clear
fi

echo "==> Copying to $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$DEST"

echo "==> Launching"
open "$DEST"

echo
echo "Done. Look for the bookmark icon in the menu bar."
echo "Then search for a bookmark title in Spotlight (Cmd-Space)."
