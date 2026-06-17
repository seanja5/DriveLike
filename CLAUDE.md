# DriveLike — Claude Context

## What this app does

DriveLike puts a widget below the Spotify lock-screen widget so drivers can tap a heart to like the currently playing song without unlocking their phone or taking their eyes off the road. That's the entire product — one screen, one button.

## Targets

| Target | Bundle ID | Role |
|--------|-----------|------|
| DriveLike | com.drivelike.app | Main app: OAuth, polling, Live Activity management |
| DriveLikeWidget | com.drivelike.app.widget | Widget extension: lock-screen UI, like button intent |

App Group: `group.com.drivelike.app` — shared container for both targets.

## Key architecture

- **Live Activity** (ActivityKit) renders the lock-screen widget. `ContentState` holds `trackName`, `artistName`, `trackId`, `isLiked`.
- **PlaybackPollingManager** polls `/v1/me/player/currently-playing` every 5 seconds. It starts/ends the Live Activity as tracks change.
- **LikeTrackIntent** (`LiveActivityIntent`, iOS 17+) runs in the widget extension process when the user taps the heart.
- **SharedStore** (`Shared/SharedStore.swift`) is the IPC layer between the two processes — file-based, uses the App Group container directory.

## Cross-process communication rules

**Never rely on `UserDefaults(suiteName:)` from the widget extension.** The extension process triggers a `kCFPreferencesAnyUser` cfprefsd detachment warning, making reads unreliable — `defaults.string(forKey:)` silently returns `nil`. This was the original bug: the intent read a nil token and exited without calling the Spotify API.

**Always use SharedStore for anything the widget extension needs to read:**
- `tokens.json` — Spotify access token + refresh token + expiry date
- `liked_ids.json` — set of liked track IDs

**SharedStore must be kept warm proactively.** Writing only during `postToken()` is not enough — that only fires on initial auth or token refresh. The fix:
1. `SpotifyAuthManager.init()` seeds the file immediately on app launch from existing UserDefaults tokens.
2. `SpotifyAuthManager.refreshIfNeeded()` rewrites the file on every 5-second poll.

If you ever touch the token-writing path, make sure both of these calls still happen.

## ActivityKit API

Use the non-deprecated update signature:
```swift
// Correct
await activity.update(ActivityContent(state: newState, staleDate: nil))

// Wrong — deprecated, avoid
await activity.update(using: newState)
```

## Build system

Project is managed by **XcodeGen** (`project.yml`). The `Shared/` directory is a source path for both targets.

**After adding any new file to `Shared/`**, run:
```
xcodegen generate
```
Otherwise the file won't be in `project.pbxproj` and won't compile into either target.

Verify builds with:
```
xcodebuild -project DriveLike.xcodeproj -scheme DriveLike -destination 'generic/platform=iOS' build
```

## Spotify API

- Auth: PKCE flow. Client ID: `b9d717af8d1549f58667611f6f0b2254`. Redirect: `drivelike://callback`.
- Like a track: `PUT /v1/me/tracks` with JSON body `{"ids": ["<trackId>"]}`. Returns `200 OK`.
- Currently playing: `GET /v1/me/player/currently-playing`. Returns `204` when nothing is playing.
- Required scopes: `user-read-playback-state user-library-modify user-read-currently-playing`

## Key files

| File | What it does |
|------|-------------|
| `Shared/SharedStore.swift` | File-based IPC: token cache + liked IDs. Used by both targets. |
| `Shared/DriveLikeActivityAttributes.swift` | `ActivityAttributes` struct shared by both targets. |
| `DriveLikeWidget/LikeIntent.swift` | Heart button intent. Reads token from SharedStore, calls Spotify API, updates Live Activity. |
| `DriveLikeWidget/DriveLikeWidget.swift` | Lock-screen and Dynamic Island widget UI. |
| `DriveLike/Auth/SpotifyAuthManager.swift` | OAuth + token management. Writes to UserDefaults AND SharedStore. Has `logout()`. |
| `DriveLike/Managers/PlaybackPollingManager.swift` | 5s poll loop. Merges liked IDs from SharedStore + legacy UserDefaults key. |
| `DriveLike/Managers/LiveActivityManager.swift` | Start/update/end the Live Activity. |
| `DriveLike/App/ContentView.swift` | Single-screen UI: connection status pill, animated waveform, refresh + disconnect buttons. |

## Spotify API restriction — IMPORTANT

`PUT /v1/me/tracks` (`user-library-modify`) is **permanently blocked** for apps in Development Mode (confirmed 403 even from the main app with a fresh token). As of May 2025, Spotify's Extended Quota program requires 250k+ MAUs and a registered business — unavailable for personal apps.

**The working alternative: save to a playlist instead of Liked Songs.**
- Scope: `playlist-modify-private` (not restricted)
- Endpoint: `POST /v1/playlists/{id}/tracks` with `{"uris": ["spotify:track:{id}"]}`
- Returns `201 Created` on success
- The "DriveLike" playlist is created automatically on first auth via `SpotifyAPIManager.getOrCreateDriveLikePlaylist()`
- Playlist ID is persisted in `SharedStore` (`playlist_id.txt`) so the widget extension can read it

**Do not attempt to re-add `user-library-modify` to kScopes** — it will always 403. The current scope list is `user-read-playback-state playlist-modify-private user-read-currently-playing`.

## Mistakes made previously — do not repeat

1. **SharedStore not seeded at startup.** Writing to `tokens.json` only in `postToken()` meant users with existing valid tokens never got the file written. Always seed in `init()` and sync in `refreshIfNeeded()`.

2. **Assuming UserDefaults works from the extension.** It doesn't reliably. Use SharedStore for any value the widget needs.

3. **Forgetting `xcodegen generate` after adding to `Shared/`.** New shared files will silently not compile into the targets until you regenerate.

4. **Using deprecated `activity.update(using:)`.** Always use `ActivityContent(state:staleDate:)`.
