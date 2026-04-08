# Dropbox Authentication & Onboarding Specification

## Overview

DropPlayer uses Dropbox OAuth v2 to authenticate users and gain read access to their Dropbox files. Authentication state is persisted and survives app restarts. The onboarding flow guides users from first launch to library setup.

---

## Components

- **`DropboxAuthManager`** — singleton; wraps the `SwiftyDropbox` SDK for sign-in and sign-out
- **`AppSettings`** — persists `isAuthenticated` in `UserDefaults`
- **`SetupView`** — onboarding screen shown to unauthenticated users
- **`DropPlayerApp`** — registers the Dropbox app key at launch and handles the OAuth redirect URL

---

## App Initialisation

- `DropboxClientsManager.setupWithAppKey(...)` is called once at app startup (inside `DropPlayerApp.init()`).
- `onOpenURL` in `DropPlayerApp` intercepts the Dropbox OAuth redirect URI. On successful token exchange it posts `Notification.Name.dropboxAuthSucceeded`.

---

## Sign-In Flow

1. User taps **Connect Dropbox** in `SetupView`.
2. `DropboxAuthManager.shared.signIn(from:)` is called with the current `UIViewController`.
3. The SDK opens Safari (or an in-app `ASWebAuthenticationSession`) to the Dropbox OAuth consent screen, requesting scopes:
   - `files.content.read`
   - `files.metadata.read`
4. After consent, Dropbox redirects back to the app via a custom URL scheme.
5. `DropPlayerApp.onOpenURL` receives the redirect and forwards it to `DropboxClientsManager.handleRedirectURL(_:)`.
6. On success, the notification `dropboxAuthSucceeded` is posted.
7. `SetupView` observes this notification and sets `settings.isAuthenticated = true`.
8. `ContentView` reacts to the `isAuthenticated` change and the UI transitions to the next step (folder selection).

**Timeout:** `SetupView` resets `isConnecting` to `false` after 30 seconds if the flow does not complete.

---

## Sign-Out Flow

1. User selects **Sign Out** from the toolbar in `AlbumListView`.
2. `AppSettings.logOut()` is called, which:
   - Sets `isAuthenticated = false`
   - Clears `musicFolderPaths`
3. `DropboxAuthManager.shared.signOut()` is called, which calls `DropboxClientsManager.unlinkClients()`.
4. `ContentView` reacts to `isAuthenticated = false` and presents `SetupView`.

---

## Persistence

| Key | Default | Description |
|---|---|---|
| `isAuthenticated` | `false` | Whether OAuth is complete |

`isAuthenticated` is a `@Published` `Bool` backed by `UserDefaults`. Any write is immediately persisted.

---

## Authorization Check

`DropboxAuthManager.isAuthorized` returns `DropboxClientsManager.authorizedClient != nil`. This is used to guard API calls in `DropboxBrowserService`.

---

## Security Notes

- Only read scopes are requested (`files.content.read`, `files.metadata.read`); no write access is ever requested.
- The OAuth token is managed entirely by the `SwiftyDropbox` SDK, which stores it in the system Keychain.
- `AppSettings.isAuthenticated` is a secondary indicator only; token validity is determined by `DropboxClientsManager.authorizedClient`.

---

## UI: SetupView

- Displays the app icon, name, and tagline.
- Single primary action: **Connect Dropbox**.
- During the OAuth flow, the button shows a `ProgressView` and is disabled.
- No account details or profile information are shown post-authentication; the view is simply navigated away from.
