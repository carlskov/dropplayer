# DropPlayer

An iPhone music player that streams audio files directly from your Dropbox.

## Features

- **Dropbox OAuth login** — secure, browser-based sign-in
- **Folder picker** — navigate your Dropbox tree and choose your music root folder
- **Album grid** — folder-based album list with cover art, album name and artist
- **Album detail** — track listing with disc & track number sorting
- **Streaming playback** — plays MP3, FLAC, AAC, M4A, OGG, WAV, AIFF, ALAC, Opus via Dropbox temporary links
- **Now Playing sheet** — full-screen player with seek bar, transport controls and artwork
- **Mini player** — persistent bar above the tab bar when music is playing
- **Lock screen / Control Center** — media keys and seek via `MPRemoteCommandCenter`
- **Background audio** — keeps playing when the screen is locked

## Setup: Before You Build

### 1. Create a Dropbox App

1. Go to [https://www.dropbox.com/developers/apps](https://www.dropbox.com/developers/apps)
2. Click **Create app**
3. Choose **Scoped access** → **Full Dropbox** (or **App folder** if you prefer a sandboxed approach)
4. Give it a name (e.g. *DropPlayer*)
5. On the app dashboard, copy your **App key**

### 2. Add the App Key to the Project

**In `DropPlayerApp.swift`** replace the placeholder:
```swift
DropboxClientsManager.setupWithAppKey("YOUR_APP_KEY")
```

**In `Info.plist`** replace the URL scheme:
```xml
<string>db-YOUR_APP_KEY</string>
```

### 3. Configure Redirect URI in Dropbox Dashboard

In your Dropbox app settings, add this redirect URI:
```
db-YOUR_APP_KEY://2/token
```

### 4. Required Permissions

In the Dropbox app dashboard under **Permissions**, enable:
- `files.content.read`
- `files.metadata.read`

### 5. Add SwiftyDropbox via Swift Package Manager

The project already references the package. When you first open `DropPlayer.xcodeproj` in Xcode, it will automatically resolve the dependency from:
```
https://github.com/dropbox/SwiftyDropbox.git
```

## Music Folder Structure

DropPlayer treats each **sub-folder** inside your chosen root as an album. For best results, organise your music like this:

```
/Music/                          ← root you select in the app
  Artist A - Album Title (2023)/
    cover.jpg
    01 - Track One.mp3
    02 - Track Two.flac
  Artist B - Another Record/
    folder.jpg
    01. Opening.m4a
```

### Folder naming convention
DropPlayer parses folder names using the pattern:
```
Artist Name - Album Title (Year)
```
Year is optional. If the folder name doesn't match, the entire folder name is used as the album title.

### Cover art
DropPlayer looks for image files named: `cover`, `folder`, `front`, `album`, `artwork`, or `albumart` (with `.jpg`, `.jpeg`, `.png`, or `.webp` extension).

## Build & Run

1. Open `DropPlayer/DropPlayer.xcodeproj` in Xcode 15+
2. Select your iPhone device or simulator (iOS 17+)
3. Set your development team under **Signing & Capabilities**
4. Build and run (⌘R)

## Architecture

| File | Role |
|---|---|
| `DropPlayerApp.swift` | App entry point, SwiftyDropbox setup, OAuth URL handling |
| `AppSettings.swift` | `UserDefaults`-backed auth state & folder path |
| `DropboxAuthManager.swift` | OAuth sign-in / sign-out wrapper |
| `DropboxBrowserService.swift` | Dropbox API: folder listing, temp links, data download |
| `LibraryViewModel.swift` | Recursive folder scan → `[Album]` |
| `PlayerEngine.swift` | `AVPlayer` wrapper with queue, seek, remote commands |
| `ContentView.swift` | Root navigation (setup → folder picker → library) |
| `SetupView.swift` | Sign-in screen |
| `FolderPickerView.swift` | Interactive Dropbox folder browser |
| `AlbumListView.swift` | Searchable album grid |
| `AlbumDetailView.swift` | Track list + play/shuffle |
| `NowPlayingView.swift` | Full-screen player |
| `MiniPlayerView.swift` | Persistent mini player bar |
| `AlbumArtView.swift` | Shared artwork image / placeholder view |
