# Project Instructions

## Git Workflow

- Commit directly on `main` in this repository.
- Do not create feature branches or pull requests unless explicitly requested.
- Ask before pushing commits.

## Build and Install

- `just build` creates the release app bundle at
  `build/ChromeBookmarksSpotlight.app`.
- `just install` copies the app to `/Applications`, registers it with Launch
  Services, and launches it.
- `just clean` removes build artifacts.
- `just cleanup-legacy` removes registrations and Spotlight entries from older
  app copies while preserving the canonical installation.

## Project Notes

- This is a macOS 13+ Swift application that indexes Google Chrome bookmarks
  in Core Spotlight.
- Keep the bundle identifier unchanged: `com.rlm.ChromeBookmarksSpotlight`.
