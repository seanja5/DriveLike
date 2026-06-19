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
- **PlaybackPollingManager** polls `/v1/me/player/currently-playing` every **3 seconds**. It manages the Live Activity as tracks change.
- **LikeTrackIntent** (`LiveActivityIntent`, iOS 17+) runs in the widget extension process when the user taps the heart.
- **SharedStore** (`Shared/SharedStore.swift`) is the IPC layer between the two processes — file-based, uses the App Group container directory.

## Cross-process communication rules

**Never rely on `UserDefaults(suiteName:)` from the widget extension.** The extension process triggers a `kCFPreferencesAnyUser` cfprefsd detachment warning, making reads unreliable — `defaults.string(forKey:)` silently returns `nil`.

**Always use SharedStore for anything the widget extension needs to read:**
- `tokens.json` — Spotify access token + refresh token + expiry date
- `liked_ids.json` — set of liked track IDs

**SharedStore must be kept warm proactively.**
1. `SpotifyAuthManager.init()` seeds the file immediately on app launch from existing UserDefaults tokens.
2. `SpotifyAuthManager.refreshIfNeeded()` rewrites the file on every poll.

If you ever touch the token-writing path, make sure both of these calls still happen.

## ActivityKit API

Use the non-deprecated update signature:
```swift
// Correct
await activity.update(ActivityContent(state: newState, staleDate: nil))

// Wrong — deprecated, avoid
await activity.update(using: newState)
```

## Live Activity lifecycle — CRITICAL, do not change

`Activity.request()` **requires the app to be in the foreground**. `activity.update()` works from the background. This constraint drives the entire design.

**The rule: one persistent Live Activity, updated in place across all songs.**

Never end and restart the activity between songs. Doing so means `Activity.request()` is called from the background when the next song starts, which silently fails and produces no popup.

### Poll logic in `PlaybackPollingManager.poll()`

```
currentTrack == nil  →  live.start()          ← safe: app just launched (foreground)
currentTrack != nil, song changed  →  live.updateTrack()   ← works from background
same song, hasActiveActivity  →  live.syncLikedState()
same song, !hasActiveActivity  →  live.updateTrack()       ← restarts lost activity
nothing playing (emptyPollThreshold hit)  →  live.end(), currentTrack = nil
```

### `LikeTrackIntent.perform()`

- Fills heart optimistically via `activity.update()` (widget extension process — OK)
- Writes to SharedStore (`liked_tracks.json`, `liked_ids.json`)
- **Does NOT end the activity** — the main app's poll transitions to the next song

### UX (confirmed working, do not change)

- Popup appears when song starts ✓
- Heart fills 2–3s after tap (widget extension cold-start delay — system limitation) ✓
- Widget transitions to next song within 3s of skipping, without opening the app ✓
- Popup does **not** disappear after liking — stays visible, transitions to next song. User confirmed this is the correct behavior. ✓
- Dynamic Island compact: green `car.fill` left, heart right ✓

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
- Currently playing: `GET /v1/me/player/currently-playing`. Returns `204` when nothing is playing.
- Active scopes: `user-read-playback-state user-read-currently-playing`

## Spotify API restrictions — IMPORTANT

Both of the following are **permanently blocked** for apps in Development Mode and must not be used:

- `PUT /v1/me/tracks` (`user-library-modify`) — 403 always. Do not add this scope.
- `POST /v1/playlists/{id}/tracks` (`playlist-modify-private`) — also 403. Playlist creation/saving has been removed entirely.

Songs are saved **locally only** to SharedStore, then synced to Supabase. There is no Spotify-side save.

## Key files

| File | What it does |
|------|-------------|
| `Shared/SharedStore.swift` | File-based IPC: token cache, liked tracks, liked IDs, current location. Used by both targets. |
| `Shared/DriveLikeActivityAttributes.swift` | `ActivityAttributes` struct shared by both targets. |
| `DriveLikeWidget/LikeIntent.swift` | Heart button intent. Updates Live Activity heart fill, writes to SharedStore. No Spotify API calls, does not end the activity. |
| `DriveLikeWidget/DriveLikeWidget.swift` | Lock-screen and Dynamic Island widget UI. Compact leading: green `car.fill`. |
| `DriveLike/Auth/SpotifyAuthManager.swift` | OAuth + token management. Writes to UserDefaults AND SharedStore. Has `logout()`. |
| `DriveLike/Managers/PlaybackPollingManager.swift` | 3s poll loop. Background location keeps it alive while driving. |
| `DriveLike/Managers/LiveActivityManager.swift` | Manages the single persistent Live Activity: `start()`, `updateTrack()`, `syncLikedState()`, `end()`, `hasActiveActivity`. |
| `DriveLike/API/SupabaseManager.swift` | Cloud sync for liked tracks, track details, audio features via PostgREST (no SPM package). |
| `DriveLike/App/ContentView.swift` | Tab bar + Now Playing tab. |
| `DriveLike/App/DrivesView.swift` | Drives tab: Music Map card + liked track list. |
| `DriveLike/App/MapView.swift` | Full-screen dark map with green pin annotations for liked track locations. |

## Mistakes made previously — do not repeat

1. **Calling `live.start()` on every song change.** `Activity.request()` requires foreground. Calling it from the background silently fails. Use `live.updateTrack()` for mid-drive song changes.

2. **Ending the activity from `LikeTrackIntent` after heart fill.** Removed. The intent no longer calls `act.end()`. Ending from the widget extension prevents the main app from starting a new activity for the next song (background restriction).

3. **SharedStore not seeded at startup.** Always seed in `SpotifyAuthManager.init()` and sync in `refreshIfNeeded()`.

4. **Assuming UserDefaults works from the extension.** It doesn't reliably. Use SharedStore.

5. **Forgetting `xcodegen generate` after adding to `Shared/`.** New shared files will silently not compile into the targets until you regenerate.

6. **Using deprecated `activity.update(using:)`.** Always use `ActivityContent(state:staleDate:)`.

7. **Adding `user-library-modify` or `playlist-modify-private` to scopes.** Both 403 in dev mode, always.
