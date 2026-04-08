# DropPlayer

An iOS music player written in Swift/SwiftUI that streams audio directly from a user's Dropbox account.

## Project layout

All app source is under `DropPlayer/DropPlayer/`. Key files:

| File | Role |
|------|------|
| `DropPlayerApp.swift` | App entry point, SwiftyDropbox setup, OAuth URL handling |
| `AppSettings.swift` | UserDefaults-backed auth state & folder path |
| `DropboxAuthManager.swift` | OAuth sign-in / sign-out wrapper |
| `DropboxBrowserService.swift` | Dropbox API: folder listing, temp links, data download. Declared as `actor` for safe concurrent cache access |
| `LibraryViewModel.swift` | Recursive folder scan → [Album]; background tag scan; artwork cache |
| `PlayerEngine.swift` | AVPlayer wrapper — queue, seek, auto-advance, remote commands. `@MainActor` class |
| `AudioTranscodeProxy.swift` | Local HTTP server that transcodes AIFF → ADTS-AAC on the fly for Chromecast |
| `CastManager.swift` | Google Cast session management and playback |
| `NowPlayingCoordinator.swift` | Controls NowPlaying sheet presentation |
| `ContentView.swift` | Root navigation (setup → folder picker → library) |
| `NowPlayingView.swift` | Full-screen now-playing sheet |
| `MiniPlayerView.swift` | Persistent mini player bar above tab bar |
| `AlbumListView.swift` | Searchable album grid |
| `AlbumDetailView.swift` | Track list with play/shuffle |
| `MetadataExtractor.swift` | Reads ID3/Vorbis/AIFF tags from partial Dropbox downloads |
| `Theme.swift` | App-wide colours and styles |

Specs for each major feature are in `specs/`.

## Tech stack

- Swift 5.10+, SwiftUI, iOS 17+
- AVFoundation / AVKit for local audio playback
- Google Cast SDK (via CocoaPods) for Chromecast
- SwiftyDropbox (Swift Package Manager) for Dropbox API

## Architecture rules

- `PlayerEngine` is `@MainActor` — all state mutations must happen on the main actor. Notification/KVO callbacks must hop via `Task { @MainActor in ... }`.
- `DropboxBrowserService` is an `actor` — call its methods with `await`.
- Avoid blocking the main thread; use `Task` / `async-await` for network work.
- When in doubt, mirror the existing patterns in the file you're editing.

## Coding conventions

- Follow the existing file's style (spacing, MARK sections, access modifiers).
- Prefer `guard` early-exit over deeply nested `if`.
- Use `weak self` in closures to avoid retain cycles.
- Write `// MARK: - Section` headers for new logical groups.
- Keep views in SwiftUI; UIKit wrapping via `UIViewRepresentable` is fine when necessary (e.g. `AVRoutePickerView`, `GCKUICastButton`).

## Testing

Unit tests live in `DropPlayerTests/`. Run with:

```
xcodebuild test -workspace DropPlayer/DropPlayer.xcworkspace \
  -scheme DropPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
```
