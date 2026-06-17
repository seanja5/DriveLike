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
        guard let token else { throw SpotifyAPIError.noToken }

        // Search existing playlists for "DriveLike" before creating a new one.
        var listReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (listData, listResp) = try await URLSession.shared.data(for: listReq)
        if (listResp as! HTTPURLResponse).statusCode == 200 {
            struct Item: Decodable { let id: String; let name: String }
            struct Page: Decodable { let items: [Item] }
            if let page = try? JSONDecoder().decode(Page.self, from: listData),
               let existing = page.items.first(where: { $0.name == "DriveLike" }) {
                SharedStore.appendDebugLog("[API] Found existing DriveLike playlist: \(existing.id)")
                print("✅ [API] Found existing DriveLike playlist: \(existing.id)")
                return existing.id
            }
        }

        // Not found — create it.
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
        guard code == 201 else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            SharedStore.appendDebugLog("[API] createPlaylist FAILED HTTP \(code): \(body)")
            print("❌ [API] createPlaylist FAILED HTTP \(code): \(body)")
            throw SpotifyAPIError.http(code)
        }
        struct Playlist: Decodable { let id: String }
        let playlistId = try JSONDecoder().decode(Playlist.self, from: data).id
        SharedStore.appendDebugLog("[API] Playlist created: \(playlistId)")
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
        SharedStore.appendDebugLog("[MainApp] POST /playlists/\(playlistId)/tracks uri=spotify:track:\(trackId)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as! HTTPURLResponse).statusCode
        SharedStore.appendDebugLog("[MainApp] HTTP \(code) — \(code == 201 ? "SUCCESS" : String(data: data, encoding: .utf8) ?? "")")
        guard code == 201 else {
            throw SpotifyAPIError.http(code)
        }
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
