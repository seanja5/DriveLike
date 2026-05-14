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
        guard let token = defaults.string(forKey: "spotify_access_token") else {
            return .result()
        }

        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [URLQueryItem(name: "ids", value: trackId)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: req)

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
}
