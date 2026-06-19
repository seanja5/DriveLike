import AppIntents
import ActivityKit
import Foundation

@available(iOS 17.0, *)
struct LikeTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Like Track"
    static var description = IntentDescription("Save the currently playing track to your DriveLike list")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

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

        // Fill the heart immediately — don't wait for anything
        for act in Activity<DriveLikeActivityAttributes>.activities
                where act.contentState.trackId == trackId {
            let s = act.contentState
            await act.update(ActivityContent(
                state: DriveLikeActivityAttributes.ContentState(
                    trackName: s.trackName, artistName: s.artistName,
                    trackId: s.trackId, isLiked: true),
                staleDate: nil))
        }

        // Store locally
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

        // The activity stays alive — the main app's poll updates it in place
        // when the next song starts, which works from the background.

        return .result()
    }
}
