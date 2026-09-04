import Foundation
import CoreSpotlight

/// Debug helper for the `--search` flag: runs a `CSSearchQuery` against our
/// indexed bookmarks and prints the matches.
enum SpotlightSearchProbe {

    static func run(query term: String) {
        let escaped = term.replacingOccurrences(of: "\"", with: "\\\"")
        let queryString = "(title == \"*\(escaped)*\"cd || textContent == \"*\(escaped)*\"cd)"
            + " && domainIdentifier == \"\(SpotlightIndexer.domainIdentifier)\""

        let queryContext = CSSearchQueryContext()
        queryContext.fetchAttributes = ["title", "contentURL"]
        let query = CSSearchQuery(queryString: queryString, queryContext: queryContext)
        var count = 0

        query.foundItemsHandler = { items in
            for item in items {
                count += 1
                let title = item.attributeSet.title ?? "(untitled)"
                let url = item.attributeSet.contentURL?.absoluteString ?? item.uniqueIdentifier
                print("\(title)\t\(url)")
            }
        }

        query.completionHandler = { error in
            if let error {
                FileHandle.standardError.write(Data("search error: \(error)\n".utf8))
                exit(1)
            }
            print("— \(count) match(es)")
            exit(0)
        }

        query.start()
    }
}
