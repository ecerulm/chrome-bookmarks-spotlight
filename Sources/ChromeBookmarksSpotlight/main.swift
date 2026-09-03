import AppKit

// `--list` prints the bookmarks that would be indexed, then exits. Handy for
// verifying parsing without touching the Spotlight index or the menu bar.
if CommandLine.arguments.contains("--list") {
    let bookmarks = ChromeBookmarksReader.readAll()
    for bookmark in bookmarks {
        let folder = bookmark.folderPath.joined(separator: "/")
        print("[\(bookmark.profile)] \(folder)\t\(bookmark.title)\t\(bookmark.url.absoluteString)")
    }
    print("— \(bookmarks.count) bookmarks")
    exit(0)
}

// `--clear` removes every bookmark this app has indexed, then exits.
if CommandLine.arguments.contains("--clear") {
    SpotlightIndexer.clear { error in
        if let error {
            FileHandle.standardError.write(Data("clear failed: \(error)\n".utf8))
            exit(1)
        }
        print("Cleared indexed bookmarks.")
        exit(0)
    }
    RunLoop.main.run()
}

// `--search <term>` queries the Core Spotlight index directly (bypassing the
// Spotlight UI) so you can confirm the bookmarks were indexed.
if let i = CommandLine.arguments.firstIndex(of: "--search"),
   i + 1 < CommandLine.arguments.count {
    SpotlightSearchProbe.run(query: CommandLine.arguments[i + 1])
    // SpotlightSearchProbe.run spins the runloop and calls exit().
    RunLoop.main.run()
}

// Menu-bar-only agent: no Dock icon, no main window.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
