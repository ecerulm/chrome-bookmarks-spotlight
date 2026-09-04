# ChromeBookmarksSpotlight

A tiny macOS menu-bar agent that reads your Google Chrome bookmarks and publishes
them to the **Core Spotlight** index, so you can find them from Spotlight
(⌘-Space). Selecting a result opens the bookmark's URL in your default browser.

## How it works

- **`ChromeBookmarksReader`** — locates every Chrome profile under
  `~/Library/Application Support/Google/Chrome/*/Bookmarks` and parses the JSON
  bookmark tree (title, URL, folder path, `date_added`, `date_last_used`).
- **`SpotlightIndexer`** — writes each bookmark as a `CSSearchableItem` in a
  private domain (`com.rlm.ChromeBookmarksSpotlight.bookmark`). Reindexing wipes
  that domain and rewrites it, so deleted bookmarks disappear. Each result uses
  Chrome's local favicon when available; the app icon identifies the source app.
- **`ChromeFavicons`** — reads favicon image data from each profile's Chrome
  `Favicons` SQLite database using a read-only connection and persistently caches
  successful favicon data under Application Support.
- **`BookmarksWatcher`** — a `DispatchSource` on each profile directory;
  when Chrome rewrites a `Bookmarks` file the index is refreshed (debounced 1.5s).
- **`AppDelegate`** — the menu-bar UI, and the
  `application(_:continue:)` handler that opens a URL when a Spotlight result is
  chosen (activity type `CSSearchableItemActionType`).

## Build & install

```sh
just build     # SwiftPM release build -> build/ChromeBookmarksSpotlight.app (ad-hoc signed)
just install    # copy to /Applications, register with Launch Services, launch
just clean      # remove build artifacts
```

Installing into `/Applications` matters: Spotlight relaunches the app by its
bundle identifier when you pick a result, so it needs a stable location and a
Launch Services registration.

## Menu

- **N bookmarks indexed · HH:MM** — status of the last reindex
- **Reindex Now**
- **Open Chrome Bookmark Manager**
- **Launch at Login** — via `SMAppService` (macOS 13+)
- **Quit**

## Command-line flags (debugging)

```sh
BIN="build/ChromeBookmarksSpotlight.app/Contents/MacOS/ChromeBookmarksSpotlight"
"$BIN" --list             # print every bookmark that would be indexed
"$BIN" --search khan      # query the live Core Spotlight index for "khan"
"$BIN" --clear            # remove every bookmark this app has indexed
```

## Notes

- Not sandboxed. It only reads the Chrome bookmark files and writes to the
  Spotlight index.
- Third-party Core Spotlight results appear in the normal Spotlight list; if you
  don't see one immediately, keep typing the bookmark title — ranking favours
  exact title matches.
- To remove everything it indexed: quit the app and run the binary with
  `--clear`.
- Requires macOS 13 or later.
