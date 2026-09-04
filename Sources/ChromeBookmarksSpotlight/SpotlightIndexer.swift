import Foundation
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Publishes Chrome bookmarks to the Core Spotlight index so they appear in
/// macOS Spotlight search results.
enum SpotlightIndexer {

    /// Groups every item we own so we can wipe and rebuild in one call.
    static let domainIdentifier = "com.rlm.ChromeBookmarksSpotlight.bookmark"

    /// The unique-identifier prefix carried back to us when a result is opened.
    static let identifierPrefix = "chrome-bookmark://"

    /// Replaces the whole set of indexed bookmarks with `bookmarks`.
    /// `completion` is called on an arbitrary queue with the number of items
    /// written and any error.
    static func reindex(
        _ bookmarks: [ChromeBookmark],
        completion: @escaping (Int, Error?) -> Void
    ) {
        guard CSSearchableIndex.isIndexingAvailable() else {
            completion(0, IndexingError.unavailable)
            return
        }

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { deleteError in
            if let deleteError {
                completion(0, deleteError)
                return
            }

            makeItems(from: bookmarks) { items in
                index.indexSearchableItems(items) { indexError in
                    completion(items.count, indexError)
                }
            }
        }
    }

    /// Removes every bookmark this app has indexed.
    static func clear(completion: @escaping (Error?) -> Void) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domainIdentifier], completionHandler: completion)
    }

    /// Recovers the bookmark URL from the identifier Spotlight hands back on open.
    static func url(forItemIdentifier identifier: String) -> URL? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return URL(string: String(identifier.dropFirst(identifierPrefix.count)))
    }

    // MARK: - Private

    private static func makeItems(
        from bookmarks: [ChromeBookmark],
        completion: @escaping ([CSSearchableItem]) -> Void
    ) {
        var seen = Set<String>()
        var uniqueBookmarks: [ChromeBookmark] = []
        var favicons: [String: ChromeFavicons] = [:]
        let fallbackThumbnail = NSApplication.shared.applicationIconImage?.tiffRepresentation

        for bookmark in bookmarks {
            // De-duplicate identical URLs shared across profiles/folders.
            guard seen.insert(bookmark.url.absoluteString).inserted else { continue }
            uniqueBookmarks.append(bookmark)
        }

        let group = DispatchGroup()
        var thumbnails = Array<Data?>(repeating: nil, count: uniqueBookmarks.count)
        let lock = NSLock()

        for (index, bookmark) in uniqueBookmarks.enumerated() {
            if let cached = ChromeFavicons.cachedData(for: bookmark.url) {
                thumbnails[index] = cached
                continue
            }

            let favicon = favicons[bookmark.profile] ?? ChromeFavicons(profile: bookmark.profile)
            favicons[bookmark.profile] = favicon
            if let data = favicon.data(for: bookmark.url) {
                ChromeFavicons.cache(data: data, for: bookmark.url)
                thumbnails[index] = data
                continue
            }

            group.enter()
            ChromeFavicons.fetchFromNetwork(for: bookmark.url) { data in
                lock.lock()
                if let data {
                    ChromeFavicons.cache(data: data, for: bookmark.url)
                }
                thumbnails[index] = data
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            var items: [CSSearchableItem] = []
            for (index, bookmark) in uniqueBookmarks.enumerated() {
                let attributes = CSSearchableItemAttributeSet(contentType: .data)
                attributes.title = bookmark.title
                attributes.displayName = bookmark.title
                attributes.contentDescription = descriptionText(for: bookmark)
                attributes.kind = "Chrome bookmark"
                attributes.creator = "ChromeBookmarksSpotlight"
                attributes.thumbnailData = thumbnails[index] ?? fallbackThumbnail
                attributes.contentCreationDate = bookmark.dateAdded
                attributes.lastUsedDate = bookmark.dateLastUsed
                attributes.identifier = bookmark.url.absoluteString

                var keywords = ["bookmark", "chrome", "bm"]
                keywords.append(contentsOf: bookmark.folderPath)
                if let host = bookmark.url.host { keywords.append(host) }
                attributes.keywords = keywords

                items.append(CSSearchableItem(
                    uniqueIdentifier: identifierPrefix + bookmark.url.absoluteString,
                    domainIdentifier: domainIdentifier,
                    attributeSet: attributes
                ))
            }
            completion(items)
        }
    }

    private static func descriptionText(for bookmark: ChromeBookmark) -> String {
        var lines = [bookmark.url.absoluteString]
        if !bookmark.folderPath.isEmpty {
            lines.append(bookmark.folderPath.joined(separator: " / "))
        }
        return lines.joined(separator: "\n")
    }

    enum IndexingError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Spotlight indexing is not available on this system."
            }
        }
    }
}
