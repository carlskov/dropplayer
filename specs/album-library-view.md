# Album Library View Specification

## Overview

`AlbumListView` is the main screen of the app. It shows the full album library as a scrollable grid of cards with search, sort, and column-count controls. Tapping a card opens the album detail sheet.

---

## Components

- **`AlbumListView`** — main library screen with grid layout and toolbar
- **`AlbumCardView`** — individual album grid cell (artwork + title + artist)
- **`AlbumArtView`** — reusable artwork component used by cards and other views
- **`AlbumDetailView`** — pushed on tap (see [album-detail.md](album-detail.md))
- **`NowPlayingCoordinator`** — mediates navigation from Now Playing back to the library

---

## Layout

- **Grid**: `LazyVGrid` with 2 or 3 adaptive columns.
- **Column toggle**: toolbar button cycles between 2 and 3 columns. Preference is not persisted.
- Each card shows: album artwork (square, fills column width), album title (bold, 2 lines max), artist (secondary, 1 line).
- While a card's album is being tag-scanned (`library.scanningAlbumId == album.id`), a small scanning indicator overlay appears on the card.

---

## Search

- Inline search bar (SwiftUI `.searchable`) filters `albums` by:
  - `album.displayTitle` (case-insensitive contains)
  - `album.displayArtist` (case-insensitive contains)
- Active search text is local state; clearing the field restores the full list.
- Search and sort are applied together (sort first, then filter).

---

## Sort Options

Controlled by `AppSettings.albumSortOption` (persisted). The sort menu is in the toolbar.

| Option | Sort key | Notes |
|---|---|---|
| Title | `displayTitle` | `localizedStandardCompare`, ascending |
| Artist | `displayArtist` + `displayTitle` | Artist primary, title secondary |
| Year | Extracted year integer | **Descending** (newest first); albums with no year go last |
| Location | `folderPath` | Alphabetical by Dropbox path |
| Genre | `genre` + `displayTitle` | Albums with genre before albums without |

**Year extraction:** Handles both `"2005"` and `"2005-06-12"` by taking the first 4 characters and parsing as `Int`.

---

## Scanning State

When `library.isScanning` is true, a scanning progress view is shown instead of the grid. It displays `library.scanProgress` (e.g., "Scanning Jazz/Miles Davis…").

---

## Empty State

When `albums` is empty and no scan is in progress, an empty-state view is shown with a **Manage Folders** button that opens `LibraryFoldersView`.

---

## Toolbar Actions

| Action | Behaviour |
|---|---|
| Grid columns | Toggles between 2 and 3 columns |
| Sort menu | Sets `settings.albumSortOption`; menu shows a checkmark on active option |
| Rescan Library | Calls `library.rescanLibrary()` |
| Manage Folders | Opens `LibraryFoldersView` as a sheet |
| Sign Out | Calls `library.clear()`, `AppSettings.logOut()`, `DropboxAuthManager.shared.signOut()` |

---

## Navigation to Album Detail

- Tapping an `AlbumCardView` pushes `AlbumDetailView` onto the `NavigationStack`.
- After dismissing `NowPlayingView`, if the user tapped the album title there, `NowPlayingCoordinator.navigateToAlbum` is set. `AlbumListView` observes this via `onChange` and programmatically pushes the corresponding `AlbumDetailView`.

---

## AlbumCardView

- Displays `AlbumArtView` (flexible mode, fills card width at 1:1 aspect ratio).
- Album title and artist below the artwork.
- A small `ProgressView` overlay appears when the album is being actively tag-scanned.

---

## AlbumArtView

Two size modes:
- `.fixed(CGFloat)` — fixed square at the given point size.
- `.flexible` — fills the available container at a 1:1 aspect ratio.

Artwork source: `library.loadArtwork(for:)` called async when the view appears.

Fallback (no artwork): music note SF Symbol on a gray rounded background.
