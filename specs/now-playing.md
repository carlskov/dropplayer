# Now Playing UI Specification

## Overview

The Now Playing experience consists of three surfaces: the persistent **Mini Player** bar at the bottom of the library, the **full-screen Now Playing overlay**, and the **lock screen / Control Center** (handled by `PlayerEngine`). A shared `NowPlayingCoordinator` singleton coordinates sheet presentation and cross-view navigation.

All three surfaces automatically switch between local-player state and Cast state when a Cast session is active.

---

## Components

- **`MiniPlayerView`** — persistent bottom bar; visible whenever a track is loaded or Cast is connected
- **`NowPlayingView`** — full-screen overlay opened by tapping the mini player or a track row
- **`NowPlayingCoordinator`** — `ObservableObject` singleton; owns `isPresented` and `navigateToAlbum`
- **`SeekBarView`** — draggable progress capsule used inside `NowPlayingView`
- **`MarqueeText`** — auto-scrolling text for long track titles
- **`AudioRouteView`** — shows active AirPlay/Bluetooth/speaker route or Cast device name
- **`CastButtonView`** — `GCKUICastButton` wrapper in the Now Playing toolbar

---

## NowPlayingCoordinator

| Property | Type | Description |
|---|---|---|
| `isPresented` | `Bool` | Controls the full-screen cover in `MainTabView` |
| `navigateToAlbum` | `Album?` | Set when the user taps the album title in Now Playing; `AlbumListView` observes this to push album detail |

`NowPlayingCoordinator.shared` is injected into the environment and used by both `NowPlayingView` and `AlbumListView`. Marking it as a shared singleton ensures both views see the same state.

---

## MiniPlayerView

Shown at the bottom of the screen via `.safeAreaInset(edge: .bottom)` in `MainTabView`. Visible when `player.currentTrack != nil` OR `cast.isConnected`.

### Layout

- **Artwork thumbnail** (fixed small square) — loaded async from `library.loadArtwork(for:)`
- **Track info** (title + artist, or "Connected" + Cast device name when casting with no track)
- **Play/Pause button** — routes to `cast.togglePlayPause()` when connected, else `player.togglePlayPause()`; shows `ProgressView` when `player.isBuffering`
- **Skip-forward button** — routes to `cast.skipForward()` or `player.skipForward()`
- **Thin progress bar** (2 pt height) spanning the full width at the bottom of the bar

### Progress bar

Sources `currentTime` and `duration` from `cast` when `cast.isConnected`, otherwise from `player`. Drawn as a filled `Capsule` in `Theme.accentColor` over an `Theme.lighterAccentColor` background.

### Tap behaviour

Tapping anywhere on the mini player (outside the control buttons) sets `nowPlaying.isPresented = true`, opening the full-screen Now Playing overlay.

---

## NowPlayingView

Full-screen modal opened via `.fullScreenCover(isPresented: $nowPlaying.isPresented)` in `MainTabView`.

### Header bar

- **Dismiss button** — chevron-down icon; sets `isPresented = false`
- **Title** — "Now Playing"
- **`CastButtonView`** — opens the Cast device picker

### Artwork

`AlbumArtView` in `.flexible` mode, scaled to ~80 % of screen width.

- Scale animation: `1.0` when playing, `0.88` when paused (spring animation, responds to `isPlaying` / `isCastPlaying`).
- Tapping the artwork sets `nowPlaying.navigateToAlbum` to the current album and dismisses the sheet, causing `AlbumListView` to navigate to that album's detail view.

### Track info section

- **Title** — `MarqueeText` (auto-scrolling for long names)
- **Artist** — tappable; tapping has no current navigation action
- **Album** — tappable; sets `navigateToAlbum` and dismisses
- **Track position** — `"Track N of M"` computed from `currentIndex` and `queue.count`

#### MarqueeText

For titles that overflow the available width:
- Pauses for 2 seconds.
- Scrolls at 40 px/s.
- Loops continuously while the track title remains unchanged.

### SeekBarView

Draggable progress bar.

| State | Source |
|---|---|
| Current time | `cast.castCurrentTime` when connected, else `player.currentTime` |
| Duration | `cast.castDuration` when connected, else `player.duration` |
| Seek action | `cast.seek(to:)` when connected, else `player.seek(to:)` |

The bar is a `Capsule` that expands slightly during drag (interaction affordance). Elapsed and total time labels flank the bar.

### Transport controls

| Control | Cast-connected | Local |
|---|---|---|
| Play / Pause | `cast.togglePlayPause()` | `player.togglePlayPause()` |
| Skip back | `cast.skipBack()` | `player.skipBack()` |
| Skip forward | `cast.skipForward()` | `player.skipForward()` |

The play/pause button shows `ProgressView` when `player.isBuffering` is true.

### AudioRouteView

Shown below the transport controls.

| Condition | Display |
|---|---|
| Cast connected | `dot.radiowaves.left.and.right` icon + `cast.connectedDeviceName` |
| AirPlay / Bluetooth / Wired headphones active | Appropriate SF Symbol + route name from `AVAudioSession.currentRoute` |
| Internal speaker | Speaker SF Symbol + "iPhone Speaker" |

### Dismiss gesture

Downward swipe of ≥ 40 points on the artwork or track-info region dismisses the overlay.

---

## State Sources by Context

| Property | Local playback | Casting |
|---|---|---|
| Current time | `player.currentTime` | `cast.castCurrentTime` |
| Duration | `player.duration` | `cast.castDuration` |
| Is playing | `player.isPlaying` | `cast.isCastPlaying` |
| Play/Pause action | `player.togglePlayPause()` | `cast.togglePlayPause()` |
| Seek action | `player.seek(to:)` | `cast.seek(to:)` |
