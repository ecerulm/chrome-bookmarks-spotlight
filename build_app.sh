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

echo "==> Generating application icon"
ICONSET_DIR="${CONTENTS}/Resources/${APP_NAME}.iconset"
mkdir -p "$ICONSET_DIR"
ICON_RENDERER_BASE="$(mktemp -t "${APP_NAME}-icon")"
ICON_RENDERER="${ICON_RENDERER_BASE}.swift"
mv "$ICON_RENDERER_BASE" "$ICON_RENDERER"
cat > "$ICON_RENDERER" <<'EOF'
import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [16, 32, 128, 256, 512]

for size in sizes {
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { exit(1) }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // Draw a colored app icon directly instead of rasterizing a template SF Symbol.
        let bounds = NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
        NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: CGFloat(pixels) * 0.08, dy: CGFloat(pixels) * 0.08), xRadius: CGFloat(pixels) * 0.2, yRadius: CGFloat(pixels) * 0.2).fill()

        NSColor.white.setFill()
        let bookmark = NSBezierPath()
        bookmark.move(to: NSPoint(x: CGFloat(pixels) * 0.32, y: CGFloat(pixels) * 0.75))
        bookmark.line(to: NSPoint(x: CGFloat(pixels) * 0.68, y: CGFloat(pixels) * 0.75))
        bookmark.line(to: NSPoint(x: CGFloat(pixels) * 0.68, y: CGFloat(pixels) * 0.25))
        bookmark.line(to: NSPoint(x: CGFloat(pixels) * 0.50, y: CGFloat(pixels) * 0.37))
        bookmark.line(to: NSPoint(x: CGFloat(pixels) * 0.32, y: CGFloat(pixels) * 0.25))
        bookmark.close()
        bookmark.fill()

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try! data.write(to: outputDirectory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
EOF
ICON_RENDERER_BIN="${ICON_RENDERER}.bin"
swiftc -framework AppKit "$ICON_RENDERER" -o "$ICON_RENDERER_BIN"
"$ICON_RENDERER_BIN" "$ICONSET_DIR"
rm -f "$ICON_RENDERER" "$ICON_RENDERER_BIN"
iconutil -c icns "$ICONSET_DIR" -o "${CONTENTS}/Resources/${APP_NAME}.icns"
rm -rf "$ICONSET_DIR"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo
echo "Built: $APP_DIR"
echo "Install with:  ./install.sh   (copies it to /Applications and launches it)"
