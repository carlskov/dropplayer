# Library Scanning & Album Discovery Specification

## Overview

`LibraryViewModel` builds the album library by recursively traversing the configured Dropbox folders. The scan identifies albums by grouping audio files within the same folder. A second-pass multi-disc merge combines sibling folders that belong to the same release.

---

## Components

- **`LibraryViewModel`** — `@MainActor ObservableObject`; owns the full scan pipeline
- **`DropboxBrowserService`** — provides `listFolder(path:)` for directory traversal
- **`MetadataExtractor`** — used in the quick-scan pre-merge step and the background tag scan (see [metadata.md](metadata.md))
- **`Album`** / **`Track`** — value types produced by the scan

---

## Published State

| Property | Type | Description |
|---|---|---|
| `albums` | `[Album]` | Full sorted library |
| `isScanning` | `Bool` | True during the initial folder scan |
| `scanError` | `String?` | Set if any scan step throws |
| `scanProgress` | `String` | Human-readable status message (e.g., "Scanning Jazz/Miles Davis...") |
| `isTagScanning` | `Bool` | True during background tag enrichment |
| `tagScanProgress` | `Double` | 0.0–1.0 fraction of albums processed |
| `scanningAlbumId` | `String?` | ID of the album currently being tag-scanned (for per-card indicators) |

---

## Scan Pipeline

### Entry point: `rescanLibrary()`

1. Cancels any in-progress background tag scan.
2. Sets `isScanning = true`, clears `albums` and `scanError`.
3. Iterates each path in `AppSettings.musicFolderPaths`.
4. Calls `scanFolder(path:depth:)` for each root.
5. After all folders are scanned, runs the multi-disc merge pass.
6. Sorts the final album list by `displayTitle`.
7. Sets `isScanning = false`, starts background tag scan (`startTagScan`).

### `scanFolder(path:depth:)` — recursive folder walk (max depth: 5)

- Calls `DropboxBrowserService.listFolder(path:)` to list entries.
- Audio file entries are collected. If any are found, the folder becomes an `Album`.
- Sub-folders are recursively scanned (depth - 1).

### Audio file detection

Supported extensions: `mp3`, `flac`, `aac`, `m4a`, `ogg`, `wav`, `aiff`, `aif`, `alac`, `opus`.

### Cover art detection

Image files are checked against these base names (case-insensitive): `cover`, `folder`, `front`, `albumart`, `album`, `artwork`. Supported image types: `jpg`, `jpeg`, `png`, `webp`. The first match is stored in `album.artworkDropboxPath`.

---

## Track Filename Parsing (`makeTrack(from:)`)

Track metadata is initially derived from the filename alone (tag enrichment happens later). Parsed patterns include:

| Pattern | Example |
|---|---|
| `NN. Title` | `03. Kind of Blue.mp3` |
| `NN - Title` | `03 - Kind of Blue.mp3` |
| `Artist - NN - Title` | `Miles Davis - 03 - Kind of Blue.mp3` |
| `Artist - Title` (no number) | `Miles Davis - Kind of Blue.mp3` |
| Plain filename | `kind_of_blue.mp3` |

Parsed fields: `trackNumber`, `artist` (if embedded in filename), `title`.

---

## Album Folder Name Parsing (`parseAlbumMetadata`)

Folder names are parsed to extract album title, artist, and year before any tags are read. Recognised patterns:

| Pattern | Example |
|---|---|
| `Artist - Album (Year)` | `Miles Davis - Kind of Blue (1959)` |
| `Artist - Album` | `Miles Davis - Kind of Blue` |
| `Album (Year)` | `Kind of Blue (1959)` |
| Plain folder name | `Kind of Blue` |

---

## Multi-Disc Merge

### Quick pre-scan (`quickScanForMerge`)

Before merging, the first track of each album candidate is passed through `MetadataExtractor` to read its disc number and album title tags. This avoids false merges when folder naming patterns are ambiguous.

### Merge logic (`mergeMultiDiscAlbums`)

Albums with the same **base name** are grouped and merged. Disc suffix patterns stripped from folder names before comparison:

- `[Disc N]`, `(Disc N)`
- `[CD N]`, `(CD N)`
- `Part N`, `Vol. N`, `Vol N`
- Trailing ` 2`, ` 3` (bare number suffix)

Albums in a group are merged into a single `Album`:
- `tracks` are concatenated from all discs, sorted by disc → track number.
- `discNumber` is assigned per-disc based on position or parsed suffix.
- Metadata (title, artist, year) is taken from the first disc.
- `folderPath` is set to the shared parent path.

### Sort order within an album

Tracks are sorted: `discNumber` ascending → `trackNumber` ascending → `id` (path) ascending as tiebreaker.

---

## Final Sorting

After merge, `albums` is sorted by `displayTitle` (case-insensitive, `localizedStandardCompare`). Sort order can be changed by the user in the UI (see [album-library-view.md](album-library-view.md)); the sort is applied at display time by `AlbumListView`, not stored on the model.

---

## Persistence

The completed album list (with tags if available) is serialised to `UserDefaults` as JSON. On next launch the cached library is loaded instantly while a background rescan refreshes it.
