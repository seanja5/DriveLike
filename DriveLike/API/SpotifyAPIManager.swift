import Foundation

enum SpotifyAPIError: Error {
    case noToken
    case invalidResponse
    case http(Int)
}

final class SpotifyAPIManager {
    static let shared = SpotifyAPIManager()

    private let defaults = UserDefaults(suiteName: "group.com.drivelike.app")!
    private var token: String? { defaults.string(forKey: "spotify_access_token") }

    // MARK: - Currently Playing

    func getCurrentlyPlaying() async throws -> SpotifyTrack? {
        guard let token else { throw SpotifyAPIError.noToken }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as! HTTPURLResponse).statusCode

        if status == 204 { return nil }               // nothing is playing
        guard status == 200 else { throw SpotifyAPIError.http(status) }

        let state = try JSONDecoder().decode(PlayerState.self, from: data)
        guard state.is_playing, let item = state.item else { return nil }

        return SpotifyTrack(
            id: item.id,
            name: item.name,
            artistName: item.artists.first?.name ?? "Unknown Artist"
        )
    }

    // MARK: - Playlist

    func getOrCreateDriveLikePlaylist() async throws -> String {
        guard let token else {
            print("❌ [API] getOrCreatePlaylist: no token")
            throw SpotifyAPIError.noToken
        }
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
        print("🎵 [API] POST /v1/me/playlists → HTTP \(code)")
        guard code == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            print("❌ [API] createPlaylist FAILED HTTP \(code): \(body)")
            throw SpotifyAPIError.http(code)
        }
        struct Playlist: Decodable { let id: String }
        let playlistId = try JSONDecoder().decode(Playlist.self, from: data).id
        print("✅ [API] Playlist created: \(playlistId)")
        return playlistId
    }

    func addTrackToPlaylist(trackId: String, playlistId: String) async throws {
        guard let token else { throw SpotifyAPIError.noToken }

        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "uris": ["spotify:track:\(trackId)"]
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as! HTTPURLResponse).statusCode
        guard code == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[SpotifyAPI] addToPlaylist HTTP \(code): \(body)")
            throw SpotifyAPIError.http(code)
        }
        print("[SpotifyAPI] Added \(trackId) to playlist \(playlistId)")
    }

    // MARK: - Like Track (requires user-library-modify — blocked in dev mode, kept for future)

    func likeTrack(id: String) async throws {
        guard let token else { throw SpotifyAPIError.noToken }

        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [URLQueryItem(name: "ids", value: id)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as! HTTPURLResponse).statusCode
        guard code == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[SpotifyAPI] likeTrack HTTP \(code): \(body)")
            throw SpotifyAPIError.http(code)
        }
        print("[SpotifyAPI] likeTrack succeeded for \(id)")
    }
}
