import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<DriveLikeActivityAttributes>?

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

    // Watch for the activity ending (programmatically, after heart fill) and
    // immediately poll so the next-song popup appears without waiting 5 seconds.
    private func observeActivityState() {
        guard let a = activity else { return }
        Task { [weak self] in
            for await state in a.activityStateUpdates {
                guard state == .ended else { continue }
                // Popup dismissed after heart fill — immediately check for the next
                // song so its popup can appear without waiting for the next timer tick.
                await PlaybackPollingManager.shared.forcePoll()
            }
            _ = self
        }
    }

    // Called by the polling loop. If the heart just flipped to filled, mirror
    // the same 1-second dismiss that the widget intent does (handles the edge
    // case where the poll races ahead of the intent's optimistic update).
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
        if isLiked {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.end()
            }
        }
    }

    func end() async {
        await activity?.end(dismissalPolicy: .immediate)
        activity = nil
    }
}
