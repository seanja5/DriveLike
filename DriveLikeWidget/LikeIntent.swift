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
        print("❤️ [LikeIntent] ========== HEART TAPPED ==========")
        print("❤️ [LikeIntent] Track: '\(trackName)' by \(artistName) (id: \(trackId))")

        guard !trackId.isEmpty else {
            print("❌ [LikeIntent] trackId is empty — aborting")
            return .result()
        }

        // Read the token from the shared file — UserDefaults is unreliable from the widget process.
        let cache = SharedStore.readTokenCache()
        print("❤️ [LikeIntent] SharedStore token: \(cache != nil ? "✅ found (expires \(cache!.expiryDate))" : "❌ MISSING")")

        guard let cache, cache.expiryDate > Date() else {
            print("❌ [LikeIntent] Token missing or expired — widget cannot call Spotify. Make sure app is open and polling.")
            return .result()
        }
        let token = cache.accessToken
        print("❤️ [LikeIntent] Token valid — prefix: \(String(token.prefix(12)))...")

        // Resolve the playlist ID.
        let storedPlaylistId = SharedStore.readPlaylistId()
        print("❤️ [LikeIntent] SharedStore playlistId: \(storedPlaylistId ?? "❌ MISSING — will create now")")

        let playlistId: String
        if let stored = storedPlaylistId {
            playlistId = stored
        } else {
            print("❤️ [LikeIntent] Creating DriveLike playlist from widget intent...")
            guard let id = try? await createDriveLikePlaylist(token: token) else {
                print("❌ [LikeIntent] Playlist creation failed — cannot save song. Check scope logs above.")
                return .result()
            }
            SharedStore.writePlaylistId(id)
            playlistId = id
            print("✅ [LikeIntent] Playlist created: \(id)")
        }

        // Add the track to the playlist.
        print("❤️ [LikeIntent] Adding track to playlist \(playlistId)...")
        let added = await addTrackToPlaylist(trackId: trackId, playlistId: playlistId, token: token)
        print(added
            ? "✅ [LikeIntent] Track added to playlist successfully!"
            : "❌ [LikeIntent] addTrack FAILED — see HTTP error above")

        // Update local liked state.
        SharedStore.appendLikedTrack(LikedTrack(
            trackId:    trackId,
            trackName:  trackName,
            artistName: artistName,
            likedAt:    Date()
        ))
        SharedStore.addLikedId(trackId)

        // Fill the heart in the Live Activity.
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
        print(heartFilled
            ? "✅ [LikeIntent] Heart filled in Live Activity"
            : "⚠️ [LikeIntent] No matching Live Activity found to update heart")
        print("❤️ [LikeIntent] ========== DONE ==========")

        return .result()
    }

    // MARK: - Spotify API helpers (inline — SpotifyAPIManager is main-app only)

    private func createDriveLikePlaylist(token: String) async throws -> String {
        var meReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        meReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (meData, meResp) = try await URLSession.shared.data(for: meReq)
        let meStatus = (meResp as! HTTPURLResponse).statusCode
        print("❤️ [LikeIntent] GET /v1/me → HTTP \(meStatus)")
        guard meStatus == 200 else {
            print("❌ [LikeIntent] /v1/me failed: \(String(data: meData, encoding: .utf8) ?? "")")
            throw URLError(.badServerResponse)
        }
        struct Me: Decodable { let id: String }
        let userId = try JSONDecoder().decode(Me.self, from: meData).id

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/users/\(userId)/playlists")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "DriveLike",
            "description": "Songs liked while driving with DriveLike",
            "public": false
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as! HTTPURLResponse).statusCode
        print("❤️ [LikeIntent] POST /playlists → HTTP \(code)")
        guard code == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            print("❌ [LikeIntent] createPlaylist FAILED HTTP \(code): \(body)")
            if code == 403 { print("❌ [LikeIntent] 403 = missing playlist-modify-private scope — reconnect Spotify") }
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
            print("❌ [LikeIntent] addTrack network error")
            return false
        }
        let code = (resp as! HTTPURLResponse).statusCode
        print("❤️ [LikeIntent] POST /playlists/\(playlistId)/tracks → HTTP \(code)")
        if code != 201 {
            print("❌ [LikeIntent] addTrack FAILED HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return code == 201
    }
}
