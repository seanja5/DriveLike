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
            artistName: item.artists.first?.name ?? "Unknown Artist",
            albumArtURL: item.album?.images.first?.url ?? ""
        )
    }

    // MARK: - Current User

    func getCurrentUserId() async throws -> String {
        guard let token else { throw SpotifyAPIError.noToken }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else {
            throw SpotifyAPIError.http((resp as! HTTPURLResponse).statusCode)
        }
        struct Me: Decodable { let id: String }
        return try JSONDecoder().decode(Me.self, from: data).id
    }

    // MARK: - Track Details (album art, album name, duration)

    func getTrackDetails(id: String) async throws -> TrackDetails {
        guard let token else { throw SpotifyAPIError.noToken }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/tracks/\(id)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else {
            throw SpotifyAPIError.http((resp as! HTTPURLResponse).statusCode)
        }
        struct Image: Decodable { let url: String }
        struct Album: Decodable { let name: String; let images: [Image] }
        struct Track: Decodable { let album: Album; let duration_ms: Int }
        let track = try JSONDecoder().decode(Track.self, from: data)
        return TrackDetails(
            albumName:   track.album.name,
            albumArtURL: track.album.images.first?.url ?? "",
            durationMs:  track.duration_ms
        )
    }

    // MARK: - Audio Features (BPM, energy, valence)

    func getAudioFeatures(id: String) async throws -> AudioFeatures {
        guard let token else { throw SpotifyAPIError.noToken }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/audio-features/\(id)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else {
            throw SpotifyAPIError.http((resp as! HTTPURLResponse).statusCode)
        }
        struct Raw: Decodable { let tempo: Double; let energy: Double; let valence: Double }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return AudioFeatures(tempo: raw.tempo, energy: raw.energy, valence: raw.valence)
    }

    // MARK: - Discover tracks (search-based, works in dev mode)
    // /v1/recommendations is blocked for dev-mode apps since Nov 2024 — use search instead.

    func getDiscoverTracks(topArtists: [String], excludeIds: Set<String>) async throws -> [SpotifyTrack] {
        guard let token else { throw SpotifyAPIError.noToken }

        struct SArtist: Decodable { let name: String }
        struct SImage:  Decodable { let url: String }
        struct SAlbum:  Decodable { let images: [SImage] }
        struct SItem:   Decodable { let id: String; let name: String; let artists: [SArtist]; let album: SAlbum? }
        struct SPage:   Decodable { let items: [SItem] }
        struct SRoot:   Decodable { let tracks: SPage }

        var results: [SpotifyTrack] = []

        for artist in topArtists.prefix(4) {
            var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
            comps.queryItems = [
                .init(name: "q", value: "artist:\(artist)"),
                .init(name: "type", value: "track"),
                .init(name: "limit", value: "8")
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as! HTTPURLResponse).statusCode == 200 else { continue }
            guard let root = try? JSONDecoder().decode(SRoot.self, from: data) else { continue }
            let tracks = root.tracks.items
                .filter { !excludeIds.contains($0.id) }
                .map { SpotifyTrack(id: $0.id, name: $0.name, artistName: $0.artists.first?.name ?? "",
                                    albumArtURL: $0.album?.images.first?.url ?? "") }
            results.append(contentsOf: tracks)
        }

        // Deduplicate while preserving order, limit to 10
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }.prefix(10).map { $0 }
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
