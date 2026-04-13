# Chromecast Feature Specification

## Overview

DropPlayer supports casting audio to Google Cast devices (Chromecast, Nest Audio, etc.) over the local Wi-Fi network. Audio files are served from the iOS device directly to the Cast receiver via an embedded HTTP server — no cloud relay is involved.

The feature is implemented across three components:

- **`CastManager`** — session lifecycle, media loading, playback control, progress polling
- **`AudioTranscodeProxy`** — live-stream server for AIFF files (PCM → AAC-LC transcode)
- **`LocalAudioServer`** — buffered file server for seekable M4A and other formats

---

## Session Management Requirements

**Requirement**: Manage Cast session lifecycle and synchronize playback state

**User Need**: Users want seamless casting with automatic playback handoff between local and Cast devices

**Acceptance Criteria**:
- Uses Google Cast SDK with default media receiver (`kGCKDefaultMediaReceiverApplicationID`)
- `CastManager` registers as `GCKSessionManagerListener`
- Session start/resume behavior:
  - Marks `isConnected = true`
  - Stores device `friendlyName` in `connectedDeviceName`
  - Starts progress polling
  - Hands off current track to Cast device
- Session end/suspend behavior:
  - Marks `isConnected = false`
  - Clears `connectedDeviceName`
  - Stops progress polling
  - Resumes local playback
- On session start: pauses local `AVPlayer` and loads current track from current position

**Performance**:
- Session establishment: <2 seconds
- Playback handoff: <500ms interruption
- State synchronization: <100ms

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

## Track Loading Requirements

**Requirement**: Load and stream audio tracks to Cast devices with format-specific handling

**User Need**: Users want reliable casting with support for all audio formats in their library

**Acceptance Criteria**:
- `loadTrack(_:startTime:album:artwork:)` is the entry point for track loading
- Cancels in-progress transcode tasks
- Resets `previousPlayerState` to prevent stale state issues
- Fetches fresh Dropbox temporary link for the track
- Dispatches to appropriate path based on file extension

### Direct Path Requirements (MP3, M4A, FLAC, WAV, OGG)

**Requirement**: Stream supported formats directly to Cast receiver

**Acceptance Criteria**:
- Dropbox temporary URL sent via `GCKRemoteMediaClient.loadMedia`
- Stream type: `.buffered`
- Receiver fetches file directly from Dropbox
- Supports seeking and progress tracking

**Performance**:
- Track load time: <1 second
- Seeking response: <300ms

### AIFF Path Requirements (Two-Phase Transcoding)

**Requirement**: Support AIFF format through real-time transcoding

**User Need**: Users want to cast AIFF files without pre-conversion

**Acceptance Criteria**:
- Phase 1 (Live Stream):
  - `AudioTranscodeProxy` opens HTTP listener on random port
  - Streams AIFF from Dropbox, parses chunks on-the-fly
  - Converts PCM → AAC-LC using `AVAudioConverter`
  - Wraps in ADTS headers, sends as chunked transfer
  - Playback starts within seconds
  - Supports seeking via HTTP Range requests
- Phase 2 (Background Transcode):
  - Full AIFF downloaded to temp file
  - Exported to M4A via `AVAssetExportSession`
  - `LocalAudioServer` serves M4A with byte-range support
  - Cast reloaded with buffered stream at current position
  - Temp files cleaned up appropriately

**Performance**:
- Phase 1 startup: <2 seconds
- Phase 2 completion: <track duration + 10 seconds
- Seeking in Phase 2: <100ms response

---

## Queue & Auto-Advance Requirements

**Requirement**: Manage playback queue and automatic track advancement during casting

**User Need**: Users want continuous playback and proper queue management when casting

**Acceptance Criteria**:
- Playback queue owned by `PlayerEngine` (`queue: [Track]`, `currentIndex: Int`)
- Album playback: replaces entire queue with album's sorted tracks
- `CastManager` subscribes to `PlayerEngine.$currentTrack`
- Track change handling: loads new track onto receiver when `currentTrack` changes
- Auto-advance mechanism:
  - `pollProgress()` called every 0.5 seconds
  - Detects `playing → idle/finished` transition via `GCKMediaPlayerState`
  - Calls `playerEngine?.skipForward()` to increment index
  - Sets next `currentTrack`, triggering automatic load

**Performance**:
- Queue replacement: <100ms
- Auto-advance detection: <500ms from track end
- Track transition: <1 second total

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
