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

            let items = makeItems(from: bookmarks)
            index.indexSearchableItems(items) { indexError in
                completion(items.count, indexError)
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

    private static func makeItems(from bookmarks: [ChromeBookmark]) -> [CSSearchableItem] {
        var seen = Set<String>()
        var items: [CSSearchableItem] = []

        for bookmark in bookmarks {
            // De-duplicate identical URLs shared across profiles/folders.
            guard seen.insert(bookmark.url.absoluteString).inserted else { continue }

            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = bookmark.title
            attributes.displayName = bookmark.title
            attributes.contentURL = bookmark.url
            attributes.contentDescription = descriptionText(for: bookmark)
            attributes.kind = "Chrome bookmark"
            attributes.thumbnailData = NSApplication.shared.applicationIconImage?.tiffRepresentation
            attributes.contentCreationDate = bookmark.dateAdded
            attributes.lastUsedDate = bookmark.dateLastUsed
            attributes.identifier = bookmark.url.absoluteString

            var keywords = ["bookmark", "chrome", "bm"]
            keywords.append(contentsOf: bookmark.folderPath)
            if let host = bookmark.url.host { keywords.append(host) }
            attributes.keywords = keywords

            let item = CSSearchableItem(
                uniqueIdentifier: identifierPrefix + bookmark.url.absoluteString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
            items.append(item)
        }
        return items
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
