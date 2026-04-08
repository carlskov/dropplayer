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
| `errorMessage` | `String?` | Set if playback fails |
| `currentArtwork` | `UIImage?` | Artwork displayed in lock screen info |
| `isCasting` | `Bool` | When `true`, local `AVPlayer.play()` is suppressed |

---

## Playback Flow

### `play(track:in:album:)`

1. Sets `queue` to the full album track list (sorted).
2. Sets `currentIndex` to the position of the selected track.
3. Calls `loadAndPlay(track:)`.

### `loadAndPlay(track:)`

1. Sets `isBuffering = true`.
2. Calls `DropboxBrowserService.shared.temporaryLink(for: track.dropboxPath)`.
3. On success, calls `startPlayback(url:track:)`.
4. On failure, sets `errorMessage`.

### `startPlayback(url:track:)`

1. Creates `AVURLAsset` with appropriate per-format options (see below).
2. Creates `AVPlayerItem` from the asset.
3. Replaces the current `AVPlayer` item.
4. Adds KVO observer on `AVPlayerItem.status`; when `.readyToPlay`:
   - Calls `player.play()` (unless `isCasting`).
   - Updates `MPNowPlayingInfoCenter`.
   - Calls `prefetchNextTrackURL()` to warm the link cache for the next queued track.
5. Registers `AVPlayerItem.didPlayToEndTimeNotification` observer for automatic advance.
6. Starts a periodic time observer (0.5 s interval) to update `currentTime`.

### `prefetchNextTrackURL()`

Called when the current item reaches `.readyToPlay`. Fires a background `Task` that calls `DropboxBrowserService.shared.temporaryLink(for:)` for `queue[currentIndex + 1]`. The result is silently discarded; the side-effect is that the URL is stored in `DropboxBrowserService`'s 1-hour link cache. When auto-advance fires at end of track, `loadAndPlay` finds the URL already cached and hands it to `AVPlayer` immediately, eliminating the API round-trip gap between tracks.

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
