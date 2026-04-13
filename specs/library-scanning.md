# Library Scanning & Album Discovery Specification

## Overview

**Purpose**: Build and maintain a browsable music library from Dropbox folders

**User Need**: Users want to browse their music collection with proper album organization and metadata

---

## Components

### LibraryViewModel
- **Role**: `@MainActor ObservableObject` that owns the scan pipeline
- **Responsibilities**: 
  - Recursive folder traversal
  - Album discovery and creation
  - Multi-disc album merging
  - State management and progress reporting

### DropboxBrowserService
- **Role**: Dropbox API wrapper for folder listing
- **Key Method**: `listFolder(path:)` for directory traversal

### MetadataExtractor
- **Role**: Audio file metadata reader
- **Usage**: Quick-scan for merge decisions, background tag enrichment

### Data Models
- **Album**: Container for tracks with metadata
- **Track**: Individual audio file with parsed metadata

---

## Published State Requirements

**Requirement**: Maintain real-time scan state for UI updates

**Acceptance Criteria**:
- `albums: [Album]` - Complete album list, updates incrementally during scan
- `isScanning: Bool` - True during initial folder traversal
- `scanError: String?` - Non-nil when scan fails
- `scanProgress: String` - Human-readable status (e.g., "Scanning Jazz/Miles Davis...")
- `isTagScanning: Bool` - True during background metadata enrichment
- `tagScanProgress: Double` - 0.0-1.0 completion fraction
- `scanningAlbumId: String?` - ID of album currently being processed

**Performance**:
- State updates must not block main thread
- UI remains responsive during scan

---

## Scan Pipeline Requirements

### Requirement: Discover and organize music library

**User Need**: Users want their music automatically organized into browsable albums

**Acceptance Criteria**:

#### Entry Point: rescanLibrary()
1. Cancels any in-progress background operations
2. Sets `isScanning = true` within 100ms of call
3. Clears existing `albums` array and `scanError`
4. Processes each path in `AppSettings.musicFolderPaths`
5. **Real-time updates**: Albums added to `albums` array as discovered
6. Completes folder traversal within 5 seconds per 1000 folders
7. Executes multi-disc merge pass
8. Sorts final album list by `displayTitle`
9. Sets `isScanning = false` when complete
10. Initiates background tag scan

#### scanFolder(path:depth:)
- **Requirement**: Recursively discover albums in folder hierarchy
- **Acceptance Criteria**:
  - Max depth: 5 levels
  - Lists folder contents via `DropboxBrowserService.listFolder(path:)`
  - Creates `Album` when audio files found
  - Recursively processes subfolders
  - Returns within 2 seconds per folder (95th percentile)

#### Audio File Detection
- **Requirement**: Identify supported audio files
- **Acceptance Criteria**:
  - Supported extensions: mp3, flac, aac, m4a, ogg, wav, aiff, aif, alac, opus
  - Case-insensitive matching
  - Files with multiple extensions handled correctly (e.g., "song.mp3.backup" ignored)

---

## Real-time Album Discovery

**Requirement**: Display albums incrementally during scan

**User Need**: Users want immediate feedback during large library scans

**Acceptance Criteria**:
- Albums appear in UI within 200ms of discovery
- Cover art displays if available during initial scan
- Scan progress continues uninterrupted
- Final album count matches post-scan total
- Multi-disc merge still functions correctly
- No duplicate albums appear

**Performance**:
- UI update latency: <200ms per album
- Memory impact: <10MB additional during scan
- No main thread blocking

---

## Cover Art Detection

**Requirement**: Display album artwork during initial scan with comprehensive filename matching

**User Need**: Users want visual identification of albums using various naming conventions

**Acceptance Criteria**:
- Cover art appears immediately when album is discovered
- Supported image types: jpg, jpeg, png, webp
- **Priority 1 - Preferred names** (case-insensitive): cover, folder, front, albumart, album, artwork (e.g., `cover.jpg`, `FRONT.png`, `AlbumArt.webp`)
- **Priority 2 - Fallback pattern**: Files ending with `-front` or `_front` (case-insensitive) (e.g., `-front.jpg`, `_front.png`, `album-front.webp`, `cover_front.jpeg`, `00-VA_-_Tribal_Science-front.jpg`, `-FRONT.PNG`, `ALBUM-FRONT.WEBP`)
- **Priority 3 - Last resort**: Any image file in the folder
- First matching image is used as album artwork
- For multi-disc releases, cover art file might be located in the main folder (e.g. the one containing subfolders of discs)
- `album.artworkDropboxPath` populated during initial scan
- Fallback to default artwork if no cover found
- Detection completes in <50ms per folder

**Examples**:
- `front.jpg` → Preferred name (highest priority)
- `-front.png` → Fallback pattern
- `album-front.webp` → Fallback pattern
- `00-VA_-_Tribal_Science-front.jpg` → Fallback pattern
- `random.jpg` → Last resort (if no preferred/fallback found)

---

## Track Filename Parsing

**Requirement**: Extract metadata from filenames when tags unavailable

**User Need**: Users want meaningful track information even without embedded metadata

**Acceptance Criteria**:
- Supported patterns:
  - `NN. Title` → `03. Kind of Blue.mp3`
  - `NN - Title` → `03 - Kind of Blue.mp3`
  - `Artist - NN - Title` → `Miles Davis - 03 - Kind of Blue.mp3`
  - `Artist - Title` → `Miles Davis - Kind of Blue.mp3`
  - Plain filename → `kind_of_blue.mp3`
- Parsed fields: `trackNumber`, `artist` (if present), `title`
- Handles malformed filenames gracefully
- Completes in <10ms per filename

---

## Album Folder Name Parsing

**Requirement**: Extract album metadata from folder names

**User Need**: Users want proper album organization even without tags

**Acceptance Criteria**:
- Supported patterns:
  - `Artist - Album (Year)` → `Miles Davis - Kind of Blue (1959)`
  - `Artist - Album` → `Miles Davis - Kind of Blue`
  - `Album (Year)` → `Kind of Blue (1959)`
  - Plain folder name → `Kind of Blue`
- Extracted fields: `title`, `artist`, `year`
- Handles special characters and Unicode
- Completes in <5ms per folder name

---

## Multi-Disc Album Merge

**Requirement**: Combine multi-disc albums into single entries

**User Need**: Users want complete albums, not split across multiple discs

**Acceptance Criteria**:

### Quick Pre-Scan
- Reads first track of each album candidate
- Extracts disc number and album title tags
- Completes in <100ms per album
- Prevents false merges from ambiguous folder names

### Merge Logic
- Albums with same base name are grouped
- Disc suffix patterns stripped before comparison:
  - `[Disc N]`, `(Disc N)`
  - `[CD N]`, `(CD N)`
  - `Part N`, `Vol. N`, `Vol N`
  - Trailing ` 2`, ` 3` (bare number suffix)
- Merged album characteristics:
  - Tracks concatenated from all discs
  - Sorted by disc number → track number
  - Metadata from first disc
  - Folder path set to shared parent
- Completes merge pass in <2 seconds per 100 albums

---

## Final Sorting

**Requirement**: Present albums in consistent, user-configurable order

**User Need**: Users want to find albums quickly

**Acceptance Criteria**:
- Default sort: `displayTitle` case-insensitive
- Sort algorithm: `localizedStandardCompare`
- Completes in <100ms per 1000 albums
- Supports user-configured sort orders
- UI applies sort at display time (not stored in model)

---

## Persistence

**Requirement**: Cache library for instant startup

**User Need**: Users want fast app launch even with large libraries

**Acceptance Criteria**:
- Completed album list serialized to `UserDefaults` as JSON
- Cache includes tags if available
- Loads from cache on launch in <500ms
- Background rescan updates cache without UI freeze
- Cache invalidated on Dropbox auth changes
- Handles corrupt cache gracefully

---

## Performance Requirements

**Overall Scan**:
- <10 seconds per 1000 folders (95th percentile)
- <50MB memory usage during scan
- No ANRs or UI freezes

**Background Tag Scan**:
- <30 seconds per 100 albums
- <20MB additional memory
- Can be cancelled and resumed

**Error Handling**:
- Network errors retry automatically (3 attempts)
- Corrupt files skipped with error logging
- Scan continues on partial failures
- User notified only on complete failure

## Folder Deletion Handling

**Requirement**: During tag rescan, remove albums if their source folder is deleted

**User Need**: Users want their library to stay in sync with their Dropbox folder structure

**Acceptance Criteria**:
- When `rescanTagsForAlbum(_:)` is called on a deleted folder:
  - Dropbox API returns "not_found" or "does not exist" error
  - Album is removed from the `albums` array
  - Album artwork cache is cleared
  - Changes are persisted via `saveAlbums()`
  - Scanning state is properly cleaned up
- Other types of errors (network issues, auth errors) keep existing album data
- UI updates immediately to reflect the removed album
- No partial album data remains in the library

**Implementation**:
- `rescanFolderContents(for:)` returns `Bool` indicating folder existence
- Error message pattern matching detects folder-not-found errors
- Guard clause in `rescanTagsForAlbum(_:)` handles folder deletion case
- Album removal happens before artwork/embedded metadata processing