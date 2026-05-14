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

        if status == 204 { return nil }
        guard status == 200 else { throw SpotifyAPIError.http(status) }

        let state = try JSONDecoder().decode(PlayerState.self, from: data)
        guard state.is_playing, let item = state.item else { return nil }

        return SpotifyTrack(
            id: item.id,
            name: item.name,
            artistName: item.artists.first?.name ?? "Unknown Artist"
        )
    }

    // MARK: - Like Track

    func likeTrack(id: String) async throws {
        guard let token else { throw SpotifyAPIError.noToken }

        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [URLQueryItem(name: "ids", value: id)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }
    }
}
