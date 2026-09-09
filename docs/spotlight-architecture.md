# Spotlight Architecture and Cleanup

This project interacts with several macOS services that are all described as
"Spotlight", but they store different kinds of state. A stale entry in System
Settings > Spotlight > Results from Apps is not necessarily a stale indexed
bookmark, and deleting one kind of state does not delete the others.

## Components

### The application bundle

The application is assembled as:

```text
/Applications/ChromeBookmarksSpotlight.app
```

Its stable bundle identifier is:

```text
com.rlm.ChromeBookmarksSpotlight
```

The bundle identifier must not change. macOS uses it when associating an app
with Launch Services, Core Spotlight continuations, preference state, and
other application metadata.

Older development builds used names like:

```text
chrome-bookmarks-spotlight-555549440571615bd87035a7895c4921d709c967
```

That name is not the current bundle identifier. It is an old generated
application or receiver name that can survive after the corresponding app
copy has been deleted.

### Launch Services

Launch Services maintains the macOS registry of applications. It discovers app
bundles and records their paths, names, display names, bundle identifiers,
icons, executable information, and supported roles.

The private `lsregister` utility can inspect and modify this registry:

```sh
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

"$LSREGISTER" -dump
"$LSREGISTER" -u "/path/to/obsolete.app"
"$LSREGISTER" -gc
"$LSREGISTER" -f "/Applications/ChromeBookmarksSpotlight.app"
```

Use `-u` only for an app bundle that has been verified as obsolete. `-gc`
removes records for bundles that are already gone. Do not use the broad
`-delete` operation: it removes the whole Launch Services database and is not
necessary for this project.

Launch Services is relevant because System Settings can obtain app/result
provider information from registered applications. Removing a Core Spotlight
item does not unregister an app, and unregistering an app does not remove its
Core Spotlight items.

### Core Spotlight and `CSSearchableIndex`

The app publishes bookmarks through the Core Spotlight framework:

```swift
CSSearchableIndex.default().indexSearchableItems(items)
```

The implementation is in `Sources/ChromeBookmarksSpotlight/SpotlightIndexer.swift`.
Each bookmark is a `CSSearchableItem` with:

- A unique identifier beginning with `chrome-bookmark://`.
- The private domain `com.rlm.ChromeBookmarksSpotlight.bookmark`.
- Metadata such as title, URL, folder path, keywords, dates, and thumbnail.

Reindexing first deletes this app-owned domain and then writes the current
bookmark set. Normal removal should therefore use:

```swift
CSSearchableIndex.default()
    .deleteSearchableItems(withDomainIdentifiers: [
        "com.rlm.ChromeBookmarksSpotlight.bookmark"
    ])
```

The command-line `--clear` flag uses the same domain-scoped deletion. This is
safe for other applications' indexes.

`deleteAllSearchableItems()` is different: it removes every Core Spotlight item
owned by every application for the user. It is appropriate only for a
deliberate emergency cleanup on a disposable or dedicated account. It should
not be the normal cleanup mechanism on a machine containing other indexed
apps.

The `--search` flag uses `CSSearchQuery` and filters by the app-owned domain.
That query tests the Core Spotlight item index directly; it does not test
Launch Services or the Results from Apps settings list.

### The private Core Spotlight database

Core Spotlight also maintains a private per-user database at:

```text
~/Library/Metadata/CoreSpotlight/
```

This directory is opaque and is not a normal plist database. A recursive text
search may not find a provider name even when the provider is still represented
in the database. The directory is separate from the preference plists and from
the redonation pipeline state described below.

The Results from Apps list in System Settings can retain a provider registration
from this internal Core Spotlight state after the app, Launch Services record,
preference keys, and redonation records have all been removed. In that case the
visible entry is a cosmetic system artifact, not proof that the app is still
installed or indexing content.

Apple does not document a supported per-provider command for removing one stale
registration from this database. `CSSearchableIndex` can delete searchable
items, but it does not expose an API for deleting a provider's historical
presence from the Results from Apps registration list.

Do not add a deletion of this directory to `just cleanup-legacy`: it contains
state for unrelated applications. A full Core Spotlight reset is a manual,
user-wide last resort only.

Before considering that reset, make a backup and close applications that use
Spotlight:

```sh
mv "$HOME/Library/Metadata/CoreSpotlight" \
   "$HOME/Library/Metadata/CoreSpotlight.backup.$(date +%Y%m%d-%H%M%S)"
sudo shutdown -r now
```

macOS should recreate the directory after reboot. Other applications may need
time to donate their searchable content again, and some search results may be
temporarily absent. Keep the backup until the user confirms that unrelated
Spotlight results and provider settings have recovered. Restore the backup only
after stopping relevant Spotlight processes and only as an intentional rollback;
do not merge opaque database files by hand.

This procedure is based on reports of phantom Results from Apps entries in
macOS 26, including:

- [Apple Stack Exchange: phantom/deleted app entry in Spotlight Results from Apps](https://apple.stackexchange.com/questions/485475/how-can-i-remove-a-phantom-deleted-app-entry-from-the-spotlight-results-for-apps)
- [Stack Exchange API: answers for the same report](https://api.stackexchange.com/2.3/questions/485475/answers?site=apple&filter=withbody)

Those reports agree that editing the visible preference plists is insufficient,
that the internal list is not documented, and that deleting the complete
CoreSpotlight directory may remove phantom entries while preserving the normal
Spotlight preference settings. This is third-party evidence, not an Apple
supported recovery procedure.

### Spotlight preference domains

System Settings stores app/result-provider preference state in preference
domains that can be inspected with `defaults`:

```sh
defaults export com.apple.Spotlight -
defaults export com.apple.corespotlightui -
```

Relevant keys observed on macOS include:

- `com.apple.Spotlight` / `EnabledPreferenceRules`: the ordered list of
  enabled Spotlight result providers.
- `com.apple.corespotlightui` /
  `CSReceiverBundleIdentifierState`: receiver/provider state keyed by app or
  receiver identifier.

These values can contain both the current app name (`ChromeBookmarksSpotlight`)
and old generated names (`chrome-bookmarks-spotlight-...`). Editing these
preferences removes UI/provider state only. It does not remove indexed items,
Launch Services registrations, or Spotlight Knowledge records.

Always edit these plists by exporting, modifying only exact stale keys, and
importing them again. Do not delete the complete plist because it contains
preferences for unrelated apps.

### `spotlightknowledged`

`spotlightknowledged` is the Spotlight Knowledge daemon. It maintains
background processing state around Spotlight data, including bookkeeping for
bundle redonation.

**Redonation** means asking a searchable-content provider to publish its
content to Core Spotlight again. Spotlight may need this after an index is
rebuilt, migrated, compacted, or otherwise loses the provider's previously
donated records. The provider is expected to respond by donating a fresh set of
items, rather than Spotlight reconstructing those items from the old index.

For this project, a normal donation is the call to
`CSSearchableIndex.indexSearchableItems` in `SpotlightIndexer`. Redonation is
not a second kind of bookmark index and it is not the same as registering the
app with Launch Services. It is a retry/request queue maintained by Spotlight
for providers whose content may need to be donated again.

Its per-user preference state is commonly visible at:

```text
~/Library/Preferences/com.apple.spotlightknowledged.pipeline.plist
```

This file may contain values such as:

```text
awaitingRedonationBundles
itemsAwaitingRedonation_chrome-bookmarks-spotlight-<hash>
```

The `awaitingRedonationBundles` array is the set of providers waiting for a
redonation. An `itemsAwaitingRedonation_<bundle>` key records additional
progress or pending-item information for that provider. A generated name in
this queue does not prove that an app bundle still exists; it only proves that
Spotlight Knowledge still remembers a provider identity that was once active.

Those generated names are the source of the especially persistent stale
entries encountered during legacy cleanup. They are not necessarily present in
Launch Services and will not be removed by `lsregister -u`, nor by deleting
`EnabledPreferenceRules`. Conversely, removing a redonation record does not
delete already-indexed items or unregister an application.

Cleanup must remove generated legacy names from both dictionaries and arrays in
this pipeline state. After changing the state, terminate the supervised
`spotlightknowledged` process so launchd can restart it with the new state:

```sh
pkill -x spotlightknowledged 2>/dev/null || true
```

Do not manually delete arbitrary Spotlight Knowledge files or reset the entire
Spotlight index just to remove one stale app name. The pipeline plist contains
state for many Apple and third-party providers.

### `corespotlightd` and related agents

`corespotlightd` is the Core Spotlight daemon that accepts and processes
indexing requests. `spotlightknowledged` performs higher-level Knowledge and
redonation bookkeeping. They are separate processes with overlapping names and
different responsibilities.

Other processes may appear while debugging, including:

- `Spotlight.app`, the user-facing Spotlight interface.
- `SpotlightPreferenceExtension`, the System Settings extension that renders
  Spotlight settings.
- `spotlightknowledged`, the Knowledge/redonation daemon.
- `corespotlightd`, the Core Spotlight indexing daemon.

Restarting the System Settings app is required to refresh an already-open
Results from Apps screen. Restarting `cfprefsd` can be useful if preference
values are cached, but it should be a last step because it affects preference
caching for the entire user session:

```sh
killall "System Settings" 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
open -a "System Settings"
```

No full `mdutil -E` rebuild is normally needed for stale app/provider names.
That operation is broader and affects filesystem Spotlight indexes rather than
just this app's provider registration state.

## Cleanup Decision Table

| Symptom | State to inspect | Correct cleanup |
| --- | --- | --- |
| Bookmark result still appears | Core Spotlight item index | Delete the app-owned domain |
| Old app path appears in app registry | Launch Services | `lsregister -u` the verified old bundle, then `-gc` |
| Provider appears in Results from Apps | Spotlight preference domains | Remove the exact old provider key/rule |
| `chrome-bookmarks-spotlight-<hash>` persists | Spotlight Knowledge pipeline | Remove it from redonation dictionaries/arrays and restart `spotlightknowledged` |
| Settings screen does not change | Cached UI/preferences | Quit and reopen System Settings; restart `cfprefsd` only if necessary |
| Provider remains after all targeted cleanup and reboot | Private Core Spotlight database | Consider the manual user-wide database reset; do not automate it |

## Current Project Cleanup

`just cleanup-legacy` is intended to perform a targeted cleanup across these
layers while preserving the canonical installation in `/Applications`.

It should:

1. Stop old app and System Settings processes.
2. Remove Core Spotlight content belonging to legacy cleanup state.
3. Remove exact stale provider entries from `com.apple.Spotlight` and
   `com.apple.corespotlightui`.
4. Remove generated `chrome-bookmarks-spotlight-*` names from
   `com.apple.spotlightknowledged.pipeline`.
5. Unregister obsolete app copies and garbage-collect Launch Services.
6. Register `/Applications/ChromeBookmarksSpotlight.app`.
7. Restart relevant supervised agents and reopen System Settings when needed.

If the old entry remains after these steps and a reboot, that does not mean the
cleanup failed. It indicates that the provider registration is probably in the
opaque Core Spotlight database. Use the diagnostic procedure above and reserve
the full database reset for an explicit manual decision.

When debugging a future failure, identify which layer contains the stale name
before changing the cleanup command. A useful search sequence is:

```sh
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

"$LSREGISTER" -dump | rg 'chrome-bookmarks-spotlight-|ChromeBookmarksSpotlight'
defaults read com.apple.Spotlight 2>/dev/null | rg 'chrome-bookmarks-spotlight-|ChromeBookmarksSpotlight'
defaults read com.apple.corespotlightui 2>/dev/null | rg 'chrome-bookmarks-spotlight-|ChromeBookmarksSpotlight'
plutil -p "$HOME/Library/Preferences/com.apple.spotlightknowledged.pipeline.plist" |
    rg 'chrome-bookmarks-spotlight-|ChromeBookmarksSpotlight'
```

Do not infer that an empty result from one command proves the state is gone:
each command checks a different Spotlight component.
