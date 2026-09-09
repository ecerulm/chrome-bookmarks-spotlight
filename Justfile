app_name := "ChromeBookmarksSpotlight"
bundle_id := "com.rlm.ChromeBookmarksSpotlight"
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

    actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "{{contents}}/Info.plist")"
    if [ "$actual_bundle_id" != "{{bundle_id}}" ]; then
        echo "error: expected bundle identifier {{bundle_id}}, got $actual_bundle_id" >&2
        exit 1
    fi

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
    # Keep the bundle icon name and icon resource in sync for Launch Services
    # and Core Spotlight on older and newer macOS releases.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile {{app_name}}" "{{contents}}/Info.plist"
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

# Remove old app copies, Spotlight preferences, and registrations created by pre-stable builds.
cleanup-legacy:
    #!/usr/bin/env bash
    set -euo pipefail

    lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    echo "==> Stopping any running legacy instance and System Settings"
    pkill -x "chrome-bookmarks-spotlight" 2>/dev/null || true
    pkill -x "System Settings" 2>/dev/null || true

    echo "==> Purging legacy Core Spotlight index entries"
    swift - <<'EOF'
    import Foundation
    import CoreSpotlight

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyCleaner.app")
    let macosDir = tmpDir.appendingPathComponent("Contents/MacOS")
    try? FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleIdentifier</key>
        <string>com.example.ChromeBookmarksSpotlight</string>
        <key>CFBundleExecutable</key>
        <string>cleaner</string>
    </dict>
    </plist>
    """
    try? infoPlist.write(to: tmpDir.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

    let cleanerSwift = """
    import Foundation
    import CoreSpotlight
    CSSearchableIndex.default().deleteAllSearchableItems { _ in exit(0) }
    RunLoop.main.run()
    """
    let swiftSrc = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner.swift")
    try? cleanerSwift.write(to: swiftSrc, atomically: true, encoding: .utf8)

    let binPath = macosDir.appendingPathComponent("cleaner").path
    let buildProc = Process()
    buildProc.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    buildProc.arguments = [swiftSrc.path, "-o", binPath]
    try? buildProc.run()
    buildProc.waitUntilExit()

    let signProc = Process()
    signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    signProc.arguments = ["--force", "--sign", "-", tmpDir.path]
    try? signProc.run()
    signProc.waitUntilExit()

    let runProc = Process()
    runProc.executableURL = URL(fileURLWithPath: binPath)
    try? runProc.run()
    runProc.waitUntilExit()

    try? FileManager.default.removeItem(at: tmpDir)
    try? FileManager.default.removeItem(at: swiftSrc)
    EOF

    echo "==> Cleaning Spotlight preference plists"
    /usr/bin/python3 - <<'EOF'
    import subprocess, plistlib

    for domain in ["com.apple.corespotlightui", "com.apple.Spotlight"]:
        try:
            raw = subprocess.check_output(["defaults", "export", domain, "-"], stderr=subprocess.DEVNULL)
            plist = plistlib.loads(raw)
        except Exception:
            continue

        modified = False
        if "CSReceiverBundleIdentifierState" in plist:
            state = plist["CSReceiverBundleIdentifierState"]
            to_delete = [
                k for k in state
                if k.startswith("chrome-bookmarks-spotlight-")
                or k.startswith("ChromeBookmarksSpotlight-")
                or k in ["ChromeBookmarksSpotlight", "com.example.ChromeBookmarksSpotlight"]
            ]
            for k in to_delete:
                del state[k]
                modified = True
            plist["CSReceiverBundleIdentifierState"] = state

        if "EnabledPreferenceRules" in plist:
            rules = plist["EnabledPreferenceRules"]
            new_rules = [
                r for r in rules
                if not r.startswith("chrome-bookmarks-spotlight-")
                and not r.startswith("ChromeBookmarksSpotlight-")
                and r not in ["ChromeBookmarksSpotlight", "com.example.ChromeBookmarksSpotlight"]
            ]
            if len(new_rules) != len(rules):
                plist["EnabledPreferenceRules"] = new_rules
                modified = True

        if modified:
            new_raw = plistlib.dumps(plist, fmt=plistlib.FMT_XML)
            p = subprocess.Popen(["defaults", "import", domain, "-"], stdin=subprocess.PIPE)
            p.communicate(input=new_raw)
    EOF

    echo "==> Removing stale Spotlight redonation records"
    # Stop the daemon before editing its state so an in-memory copy of the
    # stale pipeline cannot overwrite the cleaned plist during the import.
    pkill -x "spotlightknowledged" 2>/dev/null || true
    launchctl kill SIGTERM "gui/$(id -u)/com.apple.spotlightknowledged" 2>/dev/null || true
    /usr/bin/python3 - <<'EOF'
    import plistlib
    import subprocess

    prefixes = (
        "chrome-bookmarks-spotlight-",
        "ChromeBookmarksSpotlight-",
    )

    def is_legacy(value):
        if not isinstance(value, str):
            return False
        return value.startswith(prefixes) or any(
            value.startswith("itemsAwaitingRedonation_" + prefix)
            for prefix in prefixes
        )

    def clean(value):
        if isinstance(value, dict):
            return {
                key: clean(item)
                for key, item in value.items()
                if not is_legacy(key)
            }
        if isinstance(value, list):
            return [clean(item) for item in value if not is_legacy(item)]
        return value

    try:
        raw = subprocess.check_output([
            "defaults", "export", "com.apple.spotlightknowledged.pipeline", "-"
        ], stderr=subprocess.DEVNULL)
        pipeline = clean(plistlib.loads(raw))
        subprocess.run(
            ["defaults", "import", "com.apple.spotlightknowledged.pipeline", "-"],
            input=plistlib.dumps(pipeline, fmt=plistlib.FMT_BINARY),
            check=True,
        )
        verification = subprocess.check_output([
            "defaults", "export", "com.apple.spotlightknowledged.pipeline", "-"
        ], stderr=subprocess.DEVNULL)
        if any(prefix.encode() in verification for prefix in prefixes):
            raise RuntimeError("legacy redonation state remains after cleanup")
    except Exception:
        # The preference domain is private and can be unavailable while its
        # launchd service is restarting. Do not make the app cleanup fail for
        # that race; the explicit verification below reports the result.
        pass
    EOF

    if defaults export com.apple.spotlightknowledged.pipeline - 2>/dev/null | \
        /usr/bin/plutil -convert xml1 -o - -- 2>/dev/null | \
        /usr/bin/grep -qE 'chrome-bookmarks-spotlight-|ChromeBookmarksSpotlight-'; then
        echo "warning: stale Spotlight redonation records remain" >&2
    fi

    # Force preference clients, including the Settings extension, to reload
    # their state. These processes are supervised and will be relaunched.
    killall cfprefsd 2>/dev/null || true

    echo "==> Removing obsolete app copies"
    legacy_paths=(
        "$HOME/Applications/ChromeBookmarksSpotlight.app"
        "$HOME/git/personal/spotlight-chrome-bookmarks/build/ChromeBookmarksSpotlight.app"
        "$HOME/git/personal/spotlight-chrome-bookmarks-to-remove/build/ChromeBookmarksSpotlight.app"
        "{{app_dir}}"
    )

    # Old development builds used a lowercase, hyphenated bundle name. Find
    # those copies as well, otherwise Launch Services keeps listing them.
    while IFS= read -r -d '' path; do
        legacy_paths+=("$path")
    done < <(
        find "$HOME" /Applications \
            -type d -name 'chrome-bookmarks-spotlight-*.app' -print0 \
            2>/dev/null || true
    )

    for path in "${legacy_paths[@]}"; do
        if [ -d "$path" ]; then
            "$lsregister" -u "$path" || true
            rm -rf "$path"
        fi
    done

    # Remove records for legacy bundles that were deleted before this cleanup.
    "$lsregister" -gc || true

    echo "==> Registering canonical installation"
    "$lsregister" -f "{{dest}}"

    echo "Legacy app copies, preferences, and index entries removed. Canonical app re-registered."
