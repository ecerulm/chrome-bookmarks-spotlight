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

    /// Load the packaged icon directly. Menu-bar agents can have no
    /// `applicationIconImage` while they are starting up.
    private static let fallbackThumbnailData: Data? = {
        let bundledIcon = Bundle.main.url(
            forResource: "ChromeBookmarksSpotlight",
            withExtension: "icns"
        )
        return bundledIcon.flatMap(pngData(for:))
            ?? NSApplication.shared.applicationIconImage.flatMap(pngData(for:))
    }()

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

            let (items, uniqueBookmarks) = makeItems(from: bookmarks)
            index.indexSearchableItems(items) { indexError in
                completion(items.count, indexError)
            }

            enrichItems(items, bookmarks: uniqueBookmarks, in: index)
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

    private static func makeItems(from bookmarks: [ChromeBookmark]) -> ([CSSearchableItem], [ChromeBookmark]) {
        var seen = Set<String>()
        var uniqueBookmarks: [ChromeBookmark] = []

        for bookmark in bookmarks {
            // De-duplicate identical URLs shared across profiles/folders.
            guard seen.insert(bookmark.url.absoluteString).inserted else { continue }
            uniqueBookmarks.append(bookmark)
        }

        let items = uniqueBookmarks.map { bookmark in
            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = bookmark.title
            attributes.displayName = bookmark.title
            attributes.contentURL = bookmark.url
            attributes.contentDescription = descriptionText(for: bookmark)
            attributes.kind = "Chrome bookmark"
            attributes.creator = "ChromeBookmarksSpotlight"
            attributes.thumbnailData = fallbackThumbnailData
            attributes.contentCreationDate = bookmark.dateAdded
            attributes.lastUsedDate = bookmark.dateLastUsed
            attributes.identifier = bookmark.url.absoluteString

            var keywords = ["bookmark", "chrome", "bm"]
            keywords.append(contentsOf: bookmark.folderPath)
            if let host = bookmark.url.host { keywords.append(host) }
            attributes.keywords = keywords

            return CSSearchableItem(
                uniqueIdentifier: identifierPrefix + bookmark.url.absoluteString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
        return (items, uniqueBookmarks)
    }

    private static func enrichItems(
        _ items: [CSSearchableItem],
        bookmarks: [ChromeBookmark],
        in index: CSSearchableIndex
    ) {
        DispatchQueue.global(qos: .utility).async {
            var favicons: [String: ChromeFavicons] = [:]
            var enriched: [CSSearchableItem] = []

            for (item, bookmark) in zip(items, bookmarks) {
                let url = bookmark.url
                let data: Data?
                if let cached = ChromeFavicons.cachedData(for: url) {
                    data = cached
                } else {
                    let favicon = favicons[bookmark.profile] ?? ChromeFavicons(profile: bookmark.profile)
                    favicons[bookmark.profile] = favicon
                    data = favicon.data(for: url)
                }

                guard let data else { continue }
                ChromeFavicons.cache(data: data, for: url)
                item.attributeSet.thumbnailData = data
                item.isUpdate = true
                enriched.append(item)
            }

            guard !enriched.isEmpty else { return }
            index.indexSearchableItems(enriched, completionHandler: nil)
        }
    }

    private static func descriptionText(for bookmark: ChromeBookmark) -> String {
        var lines = [bookmark.url.absoluteString]
        if !bookmark.folderPath.isEmpty {
            lines.append(bookmark.folderPath.joined(separator: " / "))
        }
        return lines.joined(separator: "\n")
    }

    private static func pngData(for url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return pngData(for: image)
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
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
