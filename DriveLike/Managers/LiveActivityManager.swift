import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<DriveLikeActivityAttributes>?
    var hasActiveActivity: Bool { activity != nil }

    // MARK: - Public

    func start(track: SpotifyTrack, isLiked: Bool = false, speedGated: Bool = false) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !speedGated else { return }

        // End any orphaned activities left over from a previous session.
        for orphan in Activity<DriveLikeActivityAttributes>.activities {
            await orphan.end(dismissalPolicy: .immediate)
        }
        activity = nil

        // Give ActivityKit a moment to process the terminations before requesting
        // a new activity — avoids a silent failure when the widget process just
        // ended the previous activity a fraction of a second ago.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let state = DriveLikeActivityAttributes.ContentState(
            trackName: track.name,
            artistName: track.artistName,
            trackId: track.id,
            isLiked: isLiked
        )
        // Try up to twice — the first attempt occasionally fails right after the
        // widget extension ends the previous activity.
        for attempt in 1...2 {
            do {
                activity = try Activity<DriveLikeActivityAttributes>.request(
                    attributes: DriveLikeActivityAttributes(),
                    contentState: state,
                    pushType: nil
                )
                observeActivityState()
                break
            } catch {
                print("[LiveActivity] Start attempt \(attempt) failed: \(error)")
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    // Update the existing activity in place with new song data.
    // Called on every song change while music is playing — activity.update() works
    // from the background, which is the key property that makes the next-song widget
    // appear without the user having to open the app.
    func updateTrack(_ track: SpotifyTrack, isLiked: Bool) async {
        let state = DriveLikeActivityAttributes.ContentState(
            trackName: track.name,
            artistName: track.artistName,
            trackId: track.id,
            isLiked: isLiked
        )
        if let a = activity {
            await a.update(ActivityContent(state: state, staleDate: nil))
        } else {
            // Activity was manually dismissed or killed — try to restart.
            await start(track: track, isLiked: isLiked)
        }
    }

    // Watch for the activity ending and clear the local reference so the next poll
    // can restart it cleanly (handles manual dismissal and iOS kill scenarios).
    private func observeActivityState() {
        guard let a = activity else { return }
        Task { [weak self] in
            for await state in a.activityStateUpdates {
                guard state == .ended else { continue }
                await MainActor.run { self?.activity = nil }
                await PlaybackPollingManager.shared.forcePoll()
            }
        }
    }

    // Called by the polling loop to mirror the liked state from SharedStore into the
    // widget — handles the race where the poll runs before the intent's optimistic fill.
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
        // No dismiss after like — the activity stays alive and updates in place
        // when the next song starts, which is how background song-change detection works.
    }

    func end() async {
        await activity?.end(dismissalPolicy: .immediate)
        activity = nil
    }
}
