import AppIntents
import ActivityKit
import Foundation

// LiveActivityIntent (iOS 17+) allows this button to fire directly from the
// lock screen / Dynamic Island without requiring the user to unlock the device.
@available(iOS 17.0, *)
struct LikeTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Like Track"
    static var description = IntentDescription("Like the currently playing Spotify track")

    @Parameter(title: "Track ID")
    var trackId: String

    init() { trackId = "" }
    init(trackId: String) { self.trackId = trackId }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.drivelike.app")!

        // Refresh the token if it has expired before calling the API.
        // The widget extension has no SpotifyAuthManager, so we do it inline.
        guard let token = await validToken(from: defaults) else {
            return .result()
        }

        // PUT /v1/me/tracks with a JSON body — saves the track to Liked Songs.
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": [trackId]])
        _ = try? await URLSession.shared.data(for: req)

        // Immediately reflect the liked state in every matching Live Activity.
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

    // Returns a valid access token, refreshing via Spotify's PKCE refresh flow if needed.
    private func validToken(from defaults: UserDefaults) async -> String? {
        let existing = defaults.string(forKey: "spotify_access_token")
        let expiry   = defaults.object(forKey: "spotify_token_expiry") as? Date

        // Still valid (60-second buffer so we don't use a token that's about to expire).
        if let expiry, expiry > Date().addingTimeInterval(60), let existing {
            return existing
        }

        // Attempt a silent refresh.
        guard let refreshToken = defaults.string(forKey: "spotify_refresh_token") else {
            return existing
        }

        return await refreshAccessToken(refreshToken, into: defaults) ?? existing
    }

    private func refreshAccessToken(_ refreshToken: String, into defaults: UserDefaults) async -> String? {
        let clientId = "b9d717af8d1549f58667611f6f0b2254"

        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let encoded = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken
        req.httpBody = "grant_type=refresh_token&refresh_token=\(encoded)&client_id=\(clientId)"
            .data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let tr = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        else { return nil }

        defaults.set(tr.access_token, forKey: "spotify_access_token")
        defaults.set(Date().addingTimeInterval(Double(tr.expires_in)), forKey: "spotify_token_expiry")
        if let newRefresh = tr.refresh_token {
            defaults.set(newRefresh, forKey: "spotify_refresh_token")
        }

        return tr.access_token
    }
}

private struct TokenRefreshResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}
