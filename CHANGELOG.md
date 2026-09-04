# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 2026-09-04

### Fixed

- Fix the Quit menu action and package the custom app icon for Finder and Spotlight results.

## 2026-09-03

### Added

- Initial release: menu-bar agent that indexes Google Chrome bookmarks into
  Core Spotlight.
- `ChromeBookmarksReader` — parses `Bookmarks` JSON across all Chrome profiles.
- `SpotlightIndexer` — publishes bookmarks as `CSSearchableItem`s in a private
  domain; reindex wipes and rewrites so deletions propagate.
- `BookmarksWatcher` — auto-reindexes (debounced) when Chrome rewrites bookmarks.
- `AppDelegate` — menu-bar UI and Spotlight result activation (opens the URL).
- `LaunchAtLogin` — `SMAppService`-backed "Launch at Login" toggle.
- `--list`, `--search <term>`, and `--clear` command-line flags for debugging.
- `build_app.sh` / `install.sh` to assemble, sign, and install the `.app` bundle.
