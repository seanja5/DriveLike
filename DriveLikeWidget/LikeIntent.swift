import AppIntents
import ActivityKit
import Foundation

@available(iOS 17.0, *)
struct LikeTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Like Track"
    static var description = IntentDescription("Save the currently playing track to your DriveLike list")

    @Parameter(title: "Track ID")     var trackId: String
    @Parameter(title: "Track Name")   var trackName: String
    @Parameter(title: "Artist Name")  var artistName: String

    init() { trackId = ""; trackName = ""; artistName = "" }
    init(trackId: String, trackName: String, artistName: String) {
        self.trackId    = trackId
        self.trackName  = trackName
        self.artistName = artistName
    }

    func perform() async throws -> some IntentResult {
        SharedStore.appendDebugLog("--- HEART TAPPED ---")
        SharedStore.appendDebugLog("Track: '\(trackName)' by \(artistName)")
        SharedStore.appendDebugLog("TrackID: \(trackId)")

        guard !trackId.isEmpty else {
            SharedStore.appendDebugLog("ABORT: trackId is empty")
            return .result()
        }

        let cache = SharedStore.readTokenCache()
        if let cache {
            let expired = cache.expiryDate <= Date()
            SharedStore.appendDebugLog("Token in SharedStore: \(expired ? "EXPIRED" : "valid, expires \(cache.expiryDate)")")
        } else {
            SharedStore.appendDebugLog("ABORT: No token in SharedStore — open the app so it can write the token")
            return .result()
        }
        guard let cache, cache.expiryDate > Date() else {
            SharedStore.appendDebugLog("ABORT: Token is expired")
            return .result()
        }
        let token = cache.accessToken
        SharedStore.appendDebugLog("Token prefix: \(String(token.prefix(16)))...")

        let storedPlaylistId = SharedStore.readPlaylistId()
        SharedStore.appendDebugLog("PlaylistID in SharedStore: \(storedPlaylistId ?? "MISSING — will create now")")

        let playlistId: String
        if let stored = storedPlaylistId {
            playlistId = stored
        } else {
            SharedStore.appendDebugLog("Creating DriveLike playlist...")
            guard let id = try? await createDriveLikePlaylist(token: token) else {
                SharedStore.appendDebugLog("ABORT: Playlist creation failed (see HTTP error above)")
                return .result()
            }
            SharedStore.writePlaylistId(id)
            playlistId = id
            SharedStore.appendDebugLog("Playlist created: \(id)")
        }

        SharedStore.appendDebugLog("Adding track to playlist \(playlistId)...")
        SharedStore.appendDebugLog("Track URI: spotify:track:\(trackId)")
        let added = await addTrackToPlaylist(trackId: trackId, playlistId: playlistId, token: token)
        SharedStore.appendDebugLog(added ? "SUCCESS: Track added to playlist!" : "FAILED: addTrack call failed (see HTTP error above)")

        // Attach last-known location (written by main app every 5 s)
        let loc = SharedStore.readCurrentLocation()
        SharedStore.appendLikedTrack(LikedTrack(
            trackId:    trackId,
            trackName:  trackName,
            artistName: artistName,
            likedAt:    Date(),
            latitude:   loc?.lat,
            longitude:  loc?.lon
        ))
        SharedStore.addLikedId(trackId)

        var heartFilled = false
        for activity in Activity<DriveLikeActivityAttributes>.activities
                where activity.contentState.trackId == trackId {
            let s = activity.contentState
            await activity.update(ActivityContent(
                state: DriveLikeActivityAttributes.ContentState(
                    trackName: s.trackName,
                    artistName: s.artistName,
                    trackId: s.trackId,
                    isLiked: true
                ),
                staleDate: nil
            ))
            heartFilled = true
        }
        SharedStore.appendDebugLog(heartFilled ? "Heart filled in Live Activity" : "WARNING: No Live Activity found to fill heart")
        SharedStore.appendDebugLog("--- DONE ---")

        return .result()
    }

    // MARK: - Spotify API helpers (inline — SpotifyAPIManager is main-app only)

    private func createDriveLikePlaylist(token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "DriveLike",
            "description": "Songs liked while driving with DriveLike",
            "public": true
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as! HTTPURLResponse).statusCode
        SharedStore.appendDebugLog("POST /v1/me/playlists → HTTP \(code)")
        guard code == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            SharedStore.appendDebugLog("  ERROR body: \(body)")
            throw URLError(.badServerResponse)
        }
        struct Playlist: Decodable { let id: String }
        return try JSONDecoder().decode(Playlist.self, from: data).id
    }

    private func addTrackToPlaylist(trackId: String, playlistId: String, token: String) async -> Bool {
        guard let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks") else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "uris": ["spotify:track:\(trackId)"]
        ])
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            SharedStore.appendDebugLog("  addTrack: network error (no response)")
            return false
        }
        let code = (resp as! HTTPURLResponse).statusCode
        SharedStore.appendDebugLog("POST /playlists/\(playlistId)/tracks → HTTP \(code)")
        if code != 201 {
            SharedStore.appendDebugLog("  ERROR body: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return code == 201
    }
}
