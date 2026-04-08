# Metadata & Tag Enrichment Specification

## Overview

Tag reading in DropPlayer is done entirely in-process without third-party tag libraries. `MetadataExtractor` downloads only the first 1 MB of each file via an HTTP byte-range request and parses the raw bytes to extract ID3/Vorbis/MP4 tags and embedded artwork. A background tag scan runs after every library scan to enrich all albums and tracks.

---

## Components

- **`MetadataExtractor`** — `@MainActor` tag parser; stateless methods called per file
- **`LibraryViewModel.startTagScan()`** — drives the background enrichment loop
- **`DropboxBrowserService.downloadData(path:range:)`** — provides the first 1 MB via byte-range

---

## Background Tag Scan

### Entry point: `startTagScan()`

Called after every `rescanLibrary()` completes. Runs as a cancellable `Task`.

1. Iterates every album in `albums`.
2. For each album, iterates every track.
3. Downloads the first 1 MB of the track file from Dropbox.
4. Calls the appropriate `MetadataExtractor` parser.
5. Updates track fields: `title`, `trackNumber`, `artist`.
6. Updates album fields: `title`, `artist`, `year`, `copyright`, `label`, `genre`.
7. Sets `album.tagsLoaded = true` after all tracks in the album are processed.
8. Persists the updated library to `UserDefaults` after each album.
9. Updates `isTagScanning`, `tagScanProgress`, and `scanningAlbumId` throughout.

The task checks for cancellation between albums; calling `rescanLibrary()` cancels the in-progress tag scan before starting a new one.

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

## Artwork Loading (`loadArtwork(for:)`)

Artwork is loaded lazily when an album card or the Now Playing view needs it. The loading pipeline is:

1. **In-memory cache** — `artworkCache` dictionary keyed by `album.id`; returned immediately if present.
2. **Disk cache** — `Caches/AlbumArtwork/` directory; filename is a Base64-encoded album path. If found, decoded to `UIImage` and stored in the in-memory cache.
3. **Folder image file** — downloads `album.artworkDropboxPath` (set during scan) using `DropboxBrowserService.downloadData(path:)`.
4. **`Covers/` subfolder** — if no root image was found, `Covers/` inside the album folder is checked for image files matching the same base-name list.
5. **Embedded tag artwork** — calls `MetadataExtractor.extractArtwork(from:)` on the first track's file data.
6. On success (any source), the image is resized and saved to disk at 0.85 JPEG quality for future fast loads.

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
