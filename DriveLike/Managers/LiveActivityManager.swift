import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<DriveLikeActivityAttributes>?

    // MARK: - Public

    func start(track: SpotifyTrack) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Activities not enabled on this device/OS")
            return
        }
        let state = DriveLikeActivityAttributes.ContentState(
            trackName: track.name,
            artistName: track.artistName,
            trackId: track.id,
            isLiked: false
        )
        do {
            let activity = try Activity<DriveLikeActivityAttributes>.request(
                attributes: DriveLikeActivityAttributes(),
                contentState: state,
                pushType: nil
            )
            self.activity = activity
            print("[LiveActivity] Started: \(activity.id)")
        } catch {
            print("[LiveActivity] Start error: \(error)")
        }
    }

    func markLiked(trackId: String) async {
        guard let a = activity, a.contentState.trackId == trackId else { return }
        let s = a.contentState
        await a.update(using: DriveLikeActivityAttributes.ContentState(
            trackName: s.trackName,
            artistName: s.artistName,
            trackId: s.trackId,
            isLiked: true
        ))
    }

    func end() async {
        await activity?.end(dismissalPolicy: .immediate)
        activity = nil
    }
}
