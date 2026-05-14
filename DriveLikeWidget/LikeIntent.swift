import AppIntents
import ActivityKit
import Foundation

@available(iOS 17.0, *)
struct LikeTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Like Track"
    static var description = IntentDescription("Like the currently playing Spotify track")

    @Parameter(title: "Track ID")
    var trackId: String

    init() { trackId = "" }
    init(trackId: String) { self.trackId = trackId }

    func perform() async throws -> some IntentResult {
        guard !trackId.isEmpty else { return .result() }

        let defaults = UserDefaults(suiteName: "group.com.drivelike.app")!

        // Refresh the token if expired — widget extension has no SpotifyAuthManager.
        guard let token = await validToken(from: defaults) else { return .result() }

        // PUT /v1/me/tracks — saves to Liked Songs.
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": [trackId]])
        _ = try? await URLSession.shared.data(for: req)

        // Write the liked ID to shared UserDefaults. The main app's polling loop reads
        // this every 5 s and updates the Live Activity — a reliable fallback for the
        // direct Activity update below, which can fail when extension/app processes diverge.
        var liked = Set(defaults.stringArray(forKey: "drivelike_liked_ids") ?? [])
        liked.insert(trackId)
        defaults.set(Array(liked), forKey: "drivelike_liked_ids")

        // Also try an immediate Live Activity update from within the extension.
        for activity in Activity<DriveLikeActivityAttributes>.activities
                 where activity.contentState.trackId == trackId {
            let s = activity.contentState
            await activity.update(using: DriveLikeActivityAttributes.ContentState(
                trackName: s.trackName,
                artistName: s.artistName,
                trackId: s.trackId,
                isLiked: true
            ))
        }

        return .result()
    }

    // MARK: - Token management

    private func validToken(from defaults: UserDefaults) async -> String? {
        let existing = defaults.string(forKey: "spotify_access_token")
        let expiry   = defaults.object(forKey: "spotify_token_expiry") as? Date

        if let expiry, expiry > Date().addingTimeInterval(60), let existing {
            return existing
        }

        guard let refreshToken = defaults.string(forKey: "spotify_refresh_token") else {
            return existing
        }

        return await refreshAccessToken(refreshToken, into: defaults) ?? existing
    }

    private func refreshAccessToken(_ refreshToken: String, into defaults: UserDefaults) async -> String? {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken
        req.httpBody = "grant_type=refresh_token&refresh_token=\(encoded)&client_id=b9d717af8d1549f58667611f6f0b2254"
            .data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let tr = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        else { return nil }

        defaults.set(tr.access_token, forKey: "spotify_access_token")
        defaults.set(Date().addingTimeInterval(Double(tr.expires_in)), forKey: "spotify_token_expiry")
        if let r = tr.refresh_token { defaults.set(r, forKey: "spotify_refresh_token") }

        return tr.access_token
    }
}

private struct TokenRefreshResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}
