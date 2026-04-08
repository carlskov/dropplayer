# Chromecast Feature Specification

## Overview

DropPlayer supports casting audio to Google Cast devices (Chromecast, Nest Audio, etc.) over the local Wi-Fi network. Audio files are served from the iOS device directly to the Cast receiver via an embedded HTTP server — no cloud relay is involved.

The feature is implemented across three components:

- **`CastManager`** — session lifecycle, media loading, playback control, progress polling
- **`AudioTranscodeProxy`** — live-stream server for AIFF files (PCM → AAC-LC transcode)
- **`LocalAudioServer`** — buffered file server for seekable M4A and other formats

---

## Session Management

- Uses the **Google Cast SDK** (`GoogleCast.xcframework`) with the default media receiver (`kGCKDefaultMediaReceiverApplicationID`).
- `CastManager` registers as a `GCKSessionManagerListener` and reacts to:
  - `didStart` / `didResumeCastSession` → marks `isConnected = true`, stores the device's `friendlyName` in `connectedDeviceName`, starts progress polling, and hands off the current track.
  - `didEnd` / `didSuspend` → marks `isConnected = false`, clears `connectedDeviceName`, stops progress polling, resumes local playback.
- When a session starts, local `AVPlayer` playback is paused (`pauseForCasting()`) and the current track is loaded onto the Cast device from the current playback position.

---

## Published State (observable by SwiftUI views)

| Property | Type | Description |
|---|---|---|
| `castState` | `GCKCastState` | Current Cast framework state (no devices / not connected / connecting / connected) |
| `isConnected` | `Bool` | True when a Cast session is active |
| `isCastPlaying` | `Bool` | True when the receiver reports `playerState == .playing` |
| `castCurrentTime` | `Double` | Receiver's current stream position in seconds |
| `castDuration` | `Double` | Current track duration reported by the receiver |
| `connectedDeviceName` | `String?` | Friendly name of the connected Cast device, or `nil` when not connected |

---

## Track Loading

`loadTrack(_:startTime:album:artwork:)` is the entry point for sending a track to the receiver:

1. Cancels any in-progress background transcode task.
2. Resets `previousPlayerState` to `.unknown` (prevents stale state from triggering auto-advance).
3. Fetches a fresh Dropbox temporary link for the track.
4. Dispatches to either the **AIFF path** or the **direct path** based on file extension.

### Direct path (MP3, M4A, FLAC, WAV, OGG)

- The Dropbox temporary URL is sent directly to the Cast receiver via `GCKRemoteMediaClient.loadMedia`.
- Stream type: `.buffered`.
- The receiver fetches the file itself from Dropbox.

### AIFF path (two-phase)

AIFF files cannot be streamed directly because the Cast default receiver does not support the format.

**Phase 1 — Live stream (immediate playback)**

- `AudioTranscodeProxy` opens an HTTP listener on a random local port.
- On incoming Cast connection: streams the AIFF from Dropbox via `URLSession`, parses the `COMM`/`SSND` chunks on the fly, converts PCM → AAC-LC using `AVAudioConverter`, wraps each output packet in an ADTS header, and sends as `Transfer-Encoding: chunked`.
- Cast receives `http://<device-ip>:<proxy-port>/stream.aac` (stream type: `.live`).
- Playback starts within seconds. Seeking is supported by restarting the proxy with an HTTP `Range` request calculated from the cached sample rate and bit depth.

**Phase 2 — Background transcode → buffered swap**

- Concurrently, the full AIFF is downloaded to a temp file and exported to M4A via `AVAssetExportSession` (preset: `AVAssetExportPresetAppleM4A`).
- Once transcoding completes, `LocalAudioServer` serves the M4A file with byte-range support.
- Cast is reloaded with `http://<device-ip>:<buffered-port>/track.m4a` (stream type: `.buffered`) at the current playback position, enabling full seek support.
- The live proxy temp file is cleaned up; the M4A temp file is cleaned up when the next track loads or `CastManager` is deallocated.

---

## Queue & Auto-Advance

- The playback queue is owned by `PlayerEngine` (`queue: [Track]`, `currentIndex: Int`).
- When a track is started from `AlbumDetailView`, `PlayerEngine.play(track:in:album:)` replaces the entire queue with the album's sorted tracks and sets the index to the selected track. This clears any previous queue.
- `CastManager` subscribes to `PlayerEngine.$currentTrack`. Whenever `currentTrack` changes while connected, `handleTrackChange` loads the new track onto the receiver.
- **Auto-advance**: `pollProgress()` (called every 0.5 s) detects the transition `playing → idle/finished` via `GCKMediaPlayerState`. When this occurs, `playerEngine?.skipForward()` is called, which increments `currentIndex` and sets the next `currentTrack`, triggering the Combine sink and loading the next track automatically.

---

## Playback Controls

All transport controls delegate to Cast when `isConnected` is true:

| Action | Implementation |
|---|---|
| Play / Pause | `GCKRemoteMediaClient.play()` / `.pause()` |
| Seek | `GCKMediaSeekOptions` (buffered) or proxy restart with Range header (AIFF Phase 1) |
| Skip forward | `PlayerEngine.skipForward()` → `currentTrack` change → `handleTrackChange` |
| Skip back | `PlayerEngine.skipBack()` → `currentTrack` change → `handleTrackChange` |

---

## UI Integration

- **`CastButtonView`** (`GCKUICastButton` wrapper) — shown in `NowPlayingView` toolbar; opens the Cast device picker.
- **`NowPlayingView`** — seek bar, transport controls, and progress all switch to Cast state (`castCurrentTime`, `castDuration`, `isCastPlaying`) when `cast.isConnected` is true.
- **`MiniPlayerView`** — play/pause button and progress bar also reflect Cast state.
- **`AudioRouteView`** (in `NowPlayingView`) — displays the connected Cast device's `connectedDeviceName` with a `dot.radiowaves.left.and.right` icon when casting; otherwise shows the current `AVAudioSession` output route.

---

## Local Servers

| Server | Role | Protocol |
|---|---|---|
| `AudioTranscodeProxy` | AIFF live-stream (Phase 1) | HTTP/1.1, chunked transfer encoding |
| `LocalAudioServer` | Transcoded M4A (Phase 2) | HTTP/1.1, byte-range support |

Both servers bind to a random available local port on startup and expose their port via a `port: UInt16` property. The device's local IP address is resolved via `getifaddrs` filtering for `en0` (Wi-Fi interface).

---

## Supported Audio Formats

| Format | Cast path |
|---|---|
| MP3 | Direct Dropbox URL |
| M4A / AAC | Direct Dropbox URL |
| FLAC | Direct Dropbox URL |
| WAV | Direct Dropbox URL |
| OGG | Direct Dropbox URL |
| AIFF / AIF | Two-phase transcode via local proxy |
