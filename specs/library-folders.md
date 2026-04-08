# Library Folder Management Specification

## Overview

Users configure one or more Dropbox folder paths as music roots. DropPlayer recursively scans these folders to build the album library. Folder paths are persisted across sessions. Users can add and remove folders at any time from the dedicated management screen.

---

## Components

- **`AppSettings`** — persists `musicFolderPaths` in `UserDefaults`
- **`FolderPickerView`** — Dropbox folder browser for selecting a new music root
- **`LibraryFoldersView`** — management screen for viewing and deleting configured folders
- **`LibraryViewModel`** — re-scans the library whenever the folder list changes

---

## Persistence

`musicFolderPaths: [String]` is a `@Published` property backed by `UserDefaults` (JSON-encoded array of Dropbox path strings).

**Legacy migration:** If `UserDefaults` contains the old single-path key `musicFolderPath` but not the new array key `musicFolderPaths`, `AppSettings` reads the single string and migrates it into a one-element array automatically on first launch after upgrade.

---

## Adding a Folder

### Initial Setup (post-authentication)

- After authenticating, `ContentView` detects `isAuthenticated = true` and `musicFolderPaths.isEmpty` and presents `FolderPickerView(isInitialSetup: true)`.
- Selecting a folder here also triggers the initial library scan.

### Adding Additional Folders

- From the `AlbumListView` toolbar, the user opens **Manage Folders**.
- `LibraryFoldersView` presents a "+" button that opens `FolderPickerView(isInitialSetup: false)`.
- The selected path is appended to `settings.musicFolderPaths` and `library.rescanLibrary()` is called.

### FolderPickerView Behaviour

- Presents a list of Dropbox folders, starting at the root (`""`).
- Only `FolderMetadata` (folder) entries are shown; files are hidden.
- Folders are sorted alphabetically.
- Custom navigation stack managed via `navigationStack: [String]` (a manual path stack, not `NavigationStack`) to allow back navigation.
- The **Use This Folder** / **Add This Folder** button at the bottom of each screen adds the currently displayed path.
- The button is disabled if the path is already in `settings.musicFolderPaths`.
- Uses `DropboxBrowserService.listFolder(path:)` to load each directory level; handles pagination automatically.

---

## Removing a Folder

- `LibraryFoldersView` lists all configured paths.
- Swipe-to-delete on a row removes that path from `settings.musicFolderPaths`.
- `library.rescanLibrary()` is called immediately after removal so the album list reflects the change.
- Removing all folders leaves the library empty; `ContentView` will present `FolderPickerView(isInitialSetup: true)` again.

---

## Rescan Trigger

Any change to `musicFolderPaths` (add or remove) triggers a full library rescan via `library.rescanLibrary()`. There is no partial/incremental scan; the entire library is rebuilt from the new folder list.

---

## UI: LibraryFoldersView

- Shown as a sheet.
- Lists each configured path with a folder icon.
- Swipe-to-delete support.
- Toolbar "+" button opens `FolderPickerView`.
- Empty state shows `ContentUnavailableView` with a prompt to add a folder.
