import Foundation

/// A single Chrome bookmark of `type == "url"`.
struct ChromeBookmark {
    let title: String
    let url: URL
    let guid: String
    let dateAdded: Date?
    let dateLastUsed: Date?
    /// Folder names from the root down to the bookmark's parent, e.g. `["Bookmarks bar", "Work"]`.
    let folderPath: [String]
    /// The Chrome profile directory name, e.g. `Default` or `Profile 1`.
    let profile: String
}

/// Reads Google Chrome's `Bookmarks` JSON files across every local profile.
enum ChromeBookmarksReader {

    /// `~/Library/Application Support/Google/Chrome`
    static var chromeUserDataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    /// Every existing `Bookmarks` file, one per profile that has bookmarks.
    static func bookmarkFiles() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: chromeUserDataDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let candidate = entry.appendingPathComponent("Bookmarks", isDirectory: false)
            if fm.fileExists(atPath: candidate.path) {
                files.append(candidate)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// All bookmarks across all profiles.
    static func readAll() -> [ChromeBookmark] {
        bookmarkFiles().flatMap { read(file: $0) }
    }

    /// All `url` bookmarks contained in a single `Bookmarks` file.
    static func read(file: URL) -> [ChromeBookmark] {
        let profile = file.deletingLastPathComponent().lastPathComponent
        guard
            let data = try? Data(contentsOf: file),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let roots = root["roots"] as? [String: Any]
        else {
            return []
        }

        var bookmarks: [ChromeBookmark] = []
        // Iterate the well-known roots in a stable order.
        for key in ["bookmark_bar", "other", "synced"] {
            guard let node = roots[key] as? [String: Any] else { continue }
            walk(node: node, parentPath: [], profile: profile, into: &bookmarks)
        }
        return bookmarks
    }

    private static func walk(
        node: [String: Any],
        parentPath: [String],
        profile: String,
        into bookmarks: inout [ChromeBookmark]
    ) {
        switch node["type"] as? String {
        case "url":
            guard
                let urlString = node["url"] as? String,
                let url = URL(string: urlString),
                let scheme = url.scheme, !scheme.isEmpty
            else { return }
            let name = (node["name"] as? String) ?? ""
            bookmarks.append(ChromeBookmark(
                title: name.isEmpty ? urlString : name,
                url: url,
                guid: (node["guid"] as? String) ?? urlString,
                dateAdded: chromeTimestamp(node["date_added"]),
                dateLastUsed: chromeTimestamp(node["date_last_used"]),
                folderPath: parentPath,
                profile: profile
            ))

        case "folder":
            let name = (node["name"] as? String) ?? ""
            let path = name.isEmpty ? parentPath : parentPath + [name]
            for child in (node["children"] as? [[String: Any]]) ?? [] {
                walk(node: child, parentPath: path, profile: profile, into: &bookmarks)
            }

        default:
            break
        }
    }

    /// Chrome stores timestamps as a string of microseconds since 1601-01-01 UTC.
    private static func chromeTimestamp(_ raw: Any?) -> Date? {
        guard let string = raw as? String, let micros = Double(string), micros > 0 else { return nil }
        // 11,644,473,600 seconds between 1601-01-01 and the Unix epoch.
        let unixSeconds = micros / 1_000_000 - 11_644_473_600
        return Date(timeIntervalSince1970: unixSeconds)
    }
}
