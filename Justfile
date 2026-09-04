app_name := "ChromeBookmarksSpotlight"
config := "release"
app_dir := "build" / app_name + ".app"
contents := app_dir / "Contents"
dest := "/Applications" / app_name + ".app"

# Remove build artifacts.
clean:
    rm -rf .build build

# SwiftPM release build -> build/ChromeBookmarksSpotlight.app (ad-hoc signed).
build:
    #!/usr/bin/env bash
    set -euo pipefail

    bin_dir="$(swift build -c {{config}} --show-bin-path)"

    echo "==> swift build -c {{config}}"
    swift build -c {{config}}

    echo "==> Assembling {{app_dir}}"
    rm -rf "{{app_dir}}"
    mkdir -p "{{contents}}/MacOS" "{{contents}}/Resources"

    cp "$bin_dir/{{app_name}}" "{{contents}}/MacOS/{{app_name}}"
    cp "Resources/Info.plist" "{{contents}}/Info.plist"

    echo "==> Generating application icon"
    iconset_dir="{{contents}}/Resources/{{app_name}}.iconset"
    mkdir -p "$iconset_dir"
    icon_renderer_base="$(mktemp -t "{{app_name}}-icon")"
    icon_renderer="${icon_renderer_base}.swift"
    mv "$icon_renderer_base" "$icon_renderer"
    cat > "$icon_renderer" <<'EOF'
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
    icon_renderer_bin="${icon_renderer}.bin"
    swiftc -framework AppKit "$icon_renderer" -o "$icon_renderer_bin"
    "$icon_renderer_bin" "$iconset_dir"
    rm -f "$icon_renderer" "$icon_renderer_bin"
    iconutil -c icns "$iconset_dir" -o "{{contents}}/Resources/{{app_name}}.icns"
    rm -rf "$iconset_dir"
    printf 'APPL????' > "{{contents}}/PkgInfo"

    echo "==> Ad-hoc code signing"
    codesign --force --sign - --timestamp=none "{{app_dir}}"

    echo
    echo "Built: {{app_dir}}"
    echo "Install with:  just install   (copies it to /Applications and launches it)"

# Copy the built app into /Applications, register it, and launch it.
install:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -d "{{app_dir}}" ]; then
        echo "error: {{app_dir}} not found. Run 'just build' first." >&2
        exit 1
    fi

    echo "==> Stopping any running instance"
    pkill -x "{{app_name}}" 2>/dev/null || true

    if [ -x "{{dest}}/Contents/MacOS/{{app_name}}" ]; then
        echo "==> Clearing existing Spotlight bookmarks"
        "{{dest}}/Contents/MacOS/{{app_name}}" --clear
    fi

    echo "==> Copying to {{dest}}"
    rm -rf "{{dest}}"
    cp -R "{{app_dir}}" "{{dest}}"

    echo "==> Registering with Launch Services"
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
        -f "{{dest}}"

    echo "==> Launching"
    open "{{dest}}"

    echo
    echo "Done. Look for the bookmark icon in the menu bar."
    echo "Then search for a bookmark title in Spotlight (Cmd-Space)."
