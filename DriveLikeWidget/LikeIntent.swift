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
        guard !trackId.isEmpty else { return .result() }

        // Read the token from the shared file — UserDefaults is unreliable from the widget process.
        guard let cache = SharedStore.readTokenCache(), cache.expiryDate > Date() else {
            print("[LikeIntent] No valid token in SharedStore — aborting")
            return .result()
        }
        let token = cache.accessToken

        // Resolve the playlist ID, creating the playlist if this is the very first tap.
        let playlistId: String
        if let stored = SharedStore.readPlaylistId() {
            playlistId = stored
        } else {
            print("[LikeIntent] No playlist ID cached — creating DriveLike playlist")
            guard let id = try? await createDriveLikePlaylist(token: token) else {
                print("[LikeIntent] Playlist creation failed — aborting")
                return .result()
            }
            SharedStore.writePlaylistId(id)
            playlistId = id
        }

        // Add the track to the playlist.
        let added = await addTrackToPlaylist(trackId: trackId, playlistId: playlistId, token: token)
        if added {
            print("[LikeIntent] Added '\(trackName)' to playlist \(playlistId)")
        } else {
            print("[LikeIntent] Failed to add '\(trackName)' to playlist")
        }

        // Update local liked state so the polling loop reflects the heart immediately.
        SharedStore.appendLikedTrack(LikedTrack(
            trackId:    trackId,
            trackName:  trackName,
            artistName: artistName,
            likedAt:    Date()
        ))
        SharedStore.addLikedId(trackId)

        // Fill the heart in the Live Activity.
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
        }

        return .result()
    }

    // MARK: - Spotify API helpers (inline — SpotifyAPIManager is main-app only)

    private func createDriveLikePlaylist(token: String) async throws -> String {
        // Step 1: get the current user's Spotify ID.
        var meReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        meReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (meData, meResp) = try await URLSession.shared.data(for: meReq)
        guard (meResp as! HTTPURLResponse).statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Me: Decodable { let id: String }
        let userId = try JSONDecoder().decode(Me.self, from: meData).id

        // Step 2: create the private "DriveLike" playlist.
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
        guard (resp as! HTTPURLResponse).statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[LikeIntent] createPlaylist error: \(body)")
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
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return false }
        let code = (resp as! HTTPURLResponse).statusCode
        if code != 201 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[LikeIntent] addTrack HTTP \(code): \(body)")
        }
        return code == 201
    }
}
