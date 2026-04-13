# Local Audio Playback Specification

## Overview

`PlayerEngine` controls local audio playback using `AVPlayer`. Tracks are streamed directly from Dropbox temporary URLs. The engine manages the playback queue, skip logic, seek, lock-screen controls, and coordinates with `CastManager` to suppress local playback during Chromecast sessions.

---

## Components

- **`PlayerEngine`** — `@MainActor ObservableObject`; owns `AVPlayer`
- **`DropboxBrowserService`** — provides short-lived HTTPS streaming URLs
- **`MPRemoteCommandCenter`** / **`MPNowPlayingInfoCenter`** — lock screen and Control Center integration
- **`AVAudioSession`** — `.playback` category; activated at init

---

## Published State

| Property | Type | Description |
|---|---|---|
| `currentTrack` | `Track?` | Currently loaded track |
| `queue` | `[Track]` | Full playback queue |
| `currentIndex` | `Int` | Index in `queue` of the current track |
| `isPlaying` | `Bool` | True when `AVPlayer` is actively playing |
| `isBuffering` | `Bool` | True while the player item status is loading |
| `currentTime` | `Double` | Current playback position in seconds |
| `duration` | `Double` | Duration of the current track in seconds |
| `bufferedTime` | `Double` | Furthest buffered position in seconds (for seek bar UI) |
| `errorMessage` | `String?` | Set if playback fails |
| `currentArtwork` | `UIImage?` | Artwork displayed in lock screen info |
| `isCasting` | `Bool` | When `true`, local `AVPlayer.play()` is suppressed |

---

## Playback Flow Requirements

**Requirement**: Manage track playback initiation and queue setup

**User Need**: Users want reliable playback with proper queue management

### Play Method Requirements (`play(track:in:album:)`)

**Acceptance Criteria**:
- Sets `queue` to full album track list (sorted by track number)
- Sets `currentIndex` to position of selected track
- Calls `loadAndPlay(track:)` to initiate playback

**Performance**:
- Queue setup: <50ms
- Playback initiation: <500ms total

### Load and Play Requirements (`loadAndPlay(track:)`)

**Acceptance Criteria**:
- Sets `isBuffering = true` immediately
- Fetches Dropbox temporary link via `DropboxBrowserService.shared.temporaryLink(for:)`
- On success: calls `startPlayback(url:track:)`
- On failure: sets `errorMessage` and maintains current state
- Handles network errors gracefully with user feedback

**Performance**:
- Temporary link fetch: <300ms
- Playback start: <200ms after link received

### `startPlayback(url:track:)`

1. Creates `AVURLAsset` with appropriate per-format options (see below).
2. Creates `AVPlayerItem` from the asset.
3. Replaces the current `AVPlayer` item.
4. **Adaptive buffering**: Sets `automaticallyWaitsToMinimizeStalling` based on format:
   - Lossless formats (FLAC, ALAC, WAV, AIFF): `true` for smoother playback
   - Lossy formats (MP3, AAC, M4A, OGG): `false` for quicker start
5. Adds KVO observer on `AVPlayerItem.status`; when `.readyToPlay`:
   - Calls `player.play()` (unless `isCasting`).
   - Updates `MPNowPlayingInfoCenter`.
   - Calls `prefetchNextTrackURLs()` to warm the link cache for the next 3 tracks.
6. Registers `AVPlayerItem.didPlayToEndTimeNotification` observer for automatic advance.
7. Starts a periodic time observer (0.5 s interval) to update `currentTime`.
8. **Buffered range observation**: Observes `loadedTimeRanges` and updates `bufferedTime` for seek bar UI.

### `prefetchNextTrackURLs()`

Called when the current item reaches `.readyToPlay`. Fires background `Task`s that call `DropboxBrowserService.shared.temporaryLink(for:)` for the next 3 tracks in the queue (`queue[currentIndex + 1]`, `currentIndex + 2`, `currentIndex + 3`). The results are silently discarded; the side-effect is that the URLs are stored in `DropboxBrowserService`'s 1-hour link cache. This multi-track prefetching ensures smooth transitions even when users skip ahead multiple tracks.

---

## Format-Specific Asset Configuration

| Extension | `AVURLAsset` option | Reason |
|---|---|---|
| `aiff`, `aif` | `AVURLAssetPreferPreciseDurationAndTimingKey = true` | AIFF requires full parse for accurate seek |
| All others | (default — key omitted) | Avoids slow initial buffering |

### UTType content type hints (passed to `AVURLAsset`)

| Extension | UTType |
|---|---|
| `aiff`, `aif` | `public.aiff-audio` |
| `wav` | `com.microsoft.waveform-audio` |
| `flac` | `org.xiph.flac` |
| `mp3` | `public.mp3` |
| `m4a` | `com.apple.m4a-audio` |
| `aac` | `public.aac-audio` |

---

## Auto-Advance

When `AVPlayerItem.didPlayToEndTimeNotification` fires, `skipForward()` is called automatically. This advances `currentIndex` and loads the next track. If the queue is exhausted, playback stops.

---

## Transport Controls

| Method | Behaviour |
|---|---|
| `togglePlayPause()` | Calls `player.play()` or `player.pause()` based on current `isPlaying` state |
| `seek(to:)` | Calls `player.seek(to: CMTime(seconds:...))` |
| `skipForward()` | Advances `currentIndex + 1`; if at end, no-op. When `isCasting`, moves the pointer only (no `AVPlayer` load) |
| `skipBack()` | If `currentTime > 3` s: seeks to 0. Otherwise: `currentIndex - 1`. When `isCasting`, moves the pointer only |
| `pauseForCasting()` | Pauses `AVPlayer` without touching `isCasting`; called by `CastManager` before sending track to Cast device |

---

## Cast Coordination

- `CastManager` sets `playerEngine.isCasting = true` when a Cast session is active.
- When `isCasting` is `true`, `AVPlayer.play()` is never called; all playback state is driven by `CastManager`.
- `skipForward()` / `skipBack()` still advance `currentIndex` and update `currentTrack` while casting; this is the mechanism by which `CastManager`'s Combine subscription receives the new track.
- `pauseForCasting()` pauses the local player before handoff without altering the `isCasting` flag.

---

## Lock Screen & Control Center

`MPRemoteCommandCenter` handlers registered at init:

| Command | Handler |
|---|---|
| `playCommand` | `togglePlayPause()` |
| `pauseCommand` | `togglePlayPause()` |
| `nextTrackCommand` | `skipForward()` |
| `previousTrackCommand` | `skipBack()` |
| `changePlaybackPositionCommand` | `seek(to:)` |

`MPNowPlayingInfoCenter` is updated on every state change with: title, artist, album title, duration, elapsed time, and artwork (`MPMediaItemArtwork`).

`updateArtwork(_:)` and `updateAlbum(_:)` are called from `AlbumDetailView` and `NowPlayingView` to keep lock-screen info in sync when navigating albums.

---

## Audio Session

`AVAudioSession.sharedInstance().setCategory(.playback)` is activated in `PlayerEngine.init()`. This enables background audio and disables mixing with other apps.
