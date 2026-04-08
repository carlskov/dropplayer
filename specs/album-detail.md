# Album Detail & Track List Specification

## Overview

`AlbumDetailView` shows the full album header (artwork, metadata, action buttons) and a scrollable track list. Tapping a track starts playback via `PlayerEngine` and opens the Now Playing overlay.

---

## Components

- **`AlbumDetailView`** — main view pushed from `AlbumListView`
- **`TrackRowView`** — single row in the track list
- **`DiscHeaderView`** — section header shown above the first track of each disc in multi-disc albums
- **`AlbumArtView`** — reusable artwork component (`.fixed` size in the header)
- **`ZoomableImageView`** / **`ZoomScrollView`** — fullscreen pinch-to-zoom artwork viewer
- **`PlayerEngine`** — receives `play(track:in:album:)` calls

---

## Album Header

| Element | Content |
|---|---|
| Artwork | Square image (fixed size); placeholder if not yet loaded |
| Title | `album.displayTitle` |
| Artist | `album.displayArtist` |
| Year | From `album.year` (year portion only if ISO date format) |
| Label | `album.label` (if present) |
| Genre | `album.genre` (if present) |
| **Play** button | Starts from the first track |
| **Shuffle** button | Starts from a random track; subsequent skips are sequential from that point |

**Artwork tap** → opens `ZoomableImageView` (full-screen modal).

### ZoomableImageView

- Wraps `UIScrollView` with `maximumZoomScale = 5.0` and `minimumZoomScale = 1.0`.
- Double-tap gesture toggles between 1× and 3×.
- Swipe-down gesture dismisses the modal.

---

## Track List

### TrackRowView

| Element | Content |
|---|---|
| Leading glyph | Track number (e.g., `"3"` or `"3."`) — replaced with animated `waveform` SF Symbol when this track is currently playing |
| Title | Bold when this is the currently playing track; otherwise regular weight |
| Per-track artist | Shown below title if `track.artist` differs from `album.displayArtist` |
| Trailing | Formatted duration (`mm:ss`) from `track.durationSeconds` |

Tapping a row:
1. Calls `player.play(track:in:album:)` — sets the full album as the playback queue.
2. Loads artwork asynchronously for the Now Playing view.
3. Sets `nowPlaying.isPresented = true` to open the Now Playing overlay.

### DiscHeaderView

Displayed above the first track of each disc in multi-disc albums (i.e., when `album.tracks` contains tracks with more than one distinct `discNumber`). Shows `"Disc N"` as a section label.

---

## Queue Behaviour

When a track is tapped, `PlayerEngine.play(track:in:album:)`:
- Replaces the entire queue with the album's sorted tracks.
- Sets `currentIndex` to the index of the tapped track.
- This clears any previously loaded queue (e.g., from a different album).

Shuffle sets `currentIndex` to a random position, then playback advances sequentially from that point (no ongoing shuffle mode).

---

## Footer

`labelFooter` at the bottom of the track list shows:
- Total song count (e.g., `"12 songs"`)
- Copyright string (`album.copyright`) if present

---

## Metadata Loading

When `AlbumDetailView` appears (and when the current track changes), it:
1. Loads the artwork image via `library.loadArtwork(for:)`.
2. Updates `player.updateAlbum(_:)` and `player.updateArtwork(_:)` so the lock-screen Now Playing info reflects the current album.
