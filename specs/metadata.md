# Metadata & Tag Enrichment Specification

## Overview

Tag reading in DropPlayer is done entirely in-process without third-party tag libraries. `MetadataExtractor` downloads only the first 1 MB of each file via an HTTP byte-range request and parses the raw bytes to extract ID3/Vorbis/MP4 tags and embedded artwork. A background tag scan runs after every library scan to enrich all albums and tracks.

---

## Components

- **`MetadataExtractor`** — `@MainActor` tag parser; stateless methods called per file
- **`LibraryViewModel.startTagScan()`** — drives the background enrichment loop
- **`DropboxBrowserService.downloadData(path:range:)`** — provides the first 1 MB via byte-range

---

## Background Tag Scan Requirements

**Requirement**: Enrich album and track metadata after library discovery

**User Need**: Users want complete metadata (artist, album, year, etc.) for proper organization and display

**Acceptance Criteria**:
- `startTagScan()` is called automatically after every `rescanLibrary()` completes
- Runs as a cancellable background `Task` that doesn't block the main thread
- Processes albums sequentially, tracks within each album sequentially
- Downloads only the first 1 MB of each track file using byte-range requests
- Extracts metadata using format-specific parsers
- Updates track fields: `title`, `trackNumber`, `artist`
- Updates album fields: `title`, `artist`, `year`, `copyright`, `label`, `genre`
- Sets `album.tagsLoaded = true` after processing all tracks in an album
- Persists updated library to `UserDefaults` after each album
- Updates published state: `isTagScanning`, `tagScanProgress`, `scanningAlbumId`
- Checks for cancellation between albums
- Calling `rescanLibrary()` cancels any in-progress tag scan

**Performance**:
- Processes <100 albums in <30 seconds
- Memory usage <20MB during scan
- Network usage optimized with byte-range requests

---

## Supported Formats & Parsers

| Format | Parser | Detection |
|---|---|---|
| MP3 | `parseID3v2` | File extension or `ID3` magic bytes |
| M4A / AAC / ALAC | `parseM4A` / `parseMP4Box` | `.m4a`, `.aac`, `.alac` extension |
| FLAC | `parseFLAC` | `fLaC` magic bytes |
| OGG / Opus | `parseVorbis` | `.ogg`, `.opus` extension |
| WAV | `parseWAV` | `RIFF…WAVE` header with `id3 ` LIST chunk |
| AIFF | `parseAIFF` | `FORM…AIFF` header with `ID3 ` chunk |

---

## Fields Extracted

| Field | Source frames/atoms/keys |
|---|---|
| Title | `TIT2` (ID3), `©nam` (M4A), `TITLE` (Vorbis/FLAC) |
| Track artist | `TPE1` (ID3), `©ART` (M4A), `ARTIST` (Vorbis) |
| Album artist | `TPE2` (ID3), `aART` (M4A), `ALBUMARTIST` (Vorbis) |
| Album title | `TALB` (ID3), `©alb` (M4A), `ALBUM` (Vorbis) |
| Year | `TDRC`/`TYER` (ID3), `©day` (M4A), `DATE` (Vorbis) |
| Track number | `TRCK` (ID3), `trkn` (M4A), `TRACKNUMBER` (Vorbis) |
| Disc number | `TPOS` (ID3), `disk` (M4A), `DISCNUMBER` (Vorbis) |
| Genre | `TCON` (ID3), `©gen`/`gnre` (M4A), `GENRE` (Vorbis) |
| Copyright | `TCOP` (ID3), `cprt` (M4A), `COPYRIGHT` (Vorbis) |
| Label | `TPUB` (ID3), `©pub` (M4A), `ORGANIZATION` (Vorbis) |

Year values may be full ISO dates (`"2005-06-12"`) or bare years (`"2005"`). Both formats are stored as-is and year-sorted views extract the year prefix.

---

## Genre Normalisation

ID3v2 numeric genre codes (e.g., `(17)` = Rock) are resolved using the full 207-entry Winamp-compatible genre table. Inline codes like `(NN)SomeGenre` are also handled; the string after the code is preferred if present.

---

## Artwork Loading Requirements

**Requirement**: Load album artwork efficiently from multiple sources with caching

**User Need**: Users want to see album covers quickly without repeated network requests

**Acceptance Criteria**:
- `loadArtwork(for:)` loads artwork lazily when needed by UI
- Follows a multi-tier caching and fallback pipeline:
  1. **In-memory cache** — `artworkCache` dictionary keyed by `album.id`
  2. **Disk cache** — `Caches/AlbumArtwork/` directory with Base64-encoded filenames
  3. **Folder image file** — downloads from `album.artworkDropboxPath`
  4. **`Covers/` subfolder** — checks for artwork in subfolder
  5. **Embedded tag artwork** — extracts from first track's metadata
- Successful loads are resized and saved to disk at 0.85 JPEG quality
- Each source is tried sequentially until artwork is found
- Failed attempts don't prevent fallback to next source

**Performance**:
- In-memory cache hit: <1ms response time
- Disk cache hit: <10ms response time
- Network load: <500ms for typical image sizes

### Embedded artwork extraction

| Format | Mechanism |
|---|---|
| MP3 | `APIC` ID3 frame; front-cover type (type byte = 3) preferred over other picture types |
| M4A | Recursive MP4 atom walk: `moov → meta → ilst → covr → data` |
| FLAC | `METADATA_BLOCK_PICTURE` (block type 6), Base64-decoded |
| AIFF | Walks `FORM/AIFF` chunks to find `ID3 ` chunk, then extracts `APIC` frame |

---

## Data Models

### `Track` fields populated by tag scan

| Field | Type |
|---|---|
| `title` | `String` |
| `trackNumber` | `Int?` |
| `discNumber` | `Int?` |
| `artist` | `String?` |
| `durationSeconds` | `Double?` |

### `Album` fields populated by tag scan

| Field | Type |
|---|---|
| `title` | `String` |
| `artist` | `String` |
| `year` | `String?` |
| `genre` | `String?` |
| `copyright` | `String?` |
| `label` | `String?` |
| `tagsLoaded` | `Bool` |
