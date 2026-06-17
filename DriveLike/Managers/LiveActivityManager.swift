import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<DriveLikeActivityAttributes>?

    // MARK: - Public

    func start(track: SpotifyTrack, isLiked: Bool = false) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any orphaned activities left over from a previous app session.
        // Without this, Activity.request() fails silently and the old dead
        // activity stays on the lock screen with a non-functional heart button.
        for orphan in Activity<DriveLikeActivityAttributes>.activities {
            await orphan.end(dismissalPolicy: .immediate)
        }
        activity = nil

        let state = DriveLikeActivityAttributes.ContentState(
            trackName: track.name,
            artistName: track.artistName,
            trackId: track.id,
            isLiked: isLiked
        )
        do {
            activity = try Activity<DriveLikeActivityAttributes>.request(
                attributes: DriveLikeActivityAttributes(),
                contentState: state,
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Start error: \(error)")
        }
    }

    // Called by the polling loop to sync the liked state that the widget intent wrote
    // to shared UserDefaults. Only issues an update when the state actually changed.
    func syncLikedState(trackId: String, isLiked: Bool) async {
        guard let a = activity,
              a.contentState.trackId == trackId,
              a.contentState.isLiked != isLiked
        else { return }
        let s = a.contentState
        await a.update(ActivityContent(
            state: DriveLikeActivityAttributes.ContentState(
                trackName: s.trackName,
                artistName: s.artistName,
                trackId: s.trackId,
                isLiked: isLiked
            ),
            staleDate: nil
        ))
    }

    func end() async {
        await activity?.end(dismissalPolicy: .immediate)
        activity = nil
    }
}
