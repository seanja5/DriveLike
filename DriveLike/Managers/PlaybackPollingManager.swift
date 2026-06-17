import Foundation

@MainActor
final class PlaybackPollingManager: ObservableObject {
    static let shared = PlaybackPollingManager()

    @Published var currentTrack: SpotifyTrack?
    @Published var reauthNeeded = false
    @Published var likedTracks: [LikedTrack] = []

    private var timer: Timer?
    private let auth     = SpotifyAuthManager.shared
    private let api      = SpotifyAPIManager.shared
    private let live     = LiveActivityManager.shared
    private let defaults = UserDefaults(suiteName: "group.com.drivelike.app")!

    // Require 2 consecutive "nothing playing" responses before ending the Live Activity.
    private var consecutiveEmptyPolls = 0
    private let emptyPollThreshold    = 2

    // MARK: - Public

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { @MainActor in await poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func forcePoll() async {
        await poll()
    }

    // MARK: - Private

    private func poll() async {
        reauthNeeded = SharedStore.reauthNeeded
        likedTracks  = SharedStore.readLikedTracks()
        await auth.refreshIfNeeded()

        // Create the DriveLike playlist the first time we poll after auth.
        // Retries every 5 s until the ID is stored — visible in the main-app console.
        if SharedStore.readPlaylistId() == nil {
            do {
                let id = try await api.getOrCreateDriveLikePlaylist()
                SharedStore.writePlaylistId(id)
                print("[Polling] DriveLike playlist ready: \(id)")
            } catch {
                print("[Polling] Playlist creation failed (will retry): \(error)")
            }
        }

        do {
            let track = try await api.getCurrentlyPlaying()
            if let track {
                consecutiveEmptyPolls = 0

                // Merge liked IDs from both the shared file (widget extension writes here)
                // and the legacy UserDefaults key (backwards compat).
                let likedIds = SharedStore.readLikedIds()
                    .union(Set(defaults.stringArray(forKey: "drivelike_liked_ids") ?? []))
                let isLiked  = likedIds.contains(track.id)

                if currentTrack?.id != track.id {
                    // New track — end old activity and start a fresh one.
                    if currentTrack != nil { await live.end() }
                    await live.start(track: track, isLiked: isLiked)
                    currentTrack = track
                } else {
                    // Same track still playing — sync liked state in case the widget
                    // intent wrote to UserDefaults since the last poll.
                    await live.syncLikedState(trackId: track.id, isLiked: isLiked)
                }
            } else {
                consecutiveEmptyPolls += 1
                if consecutiveEmptyPolls >= emptyPollThreshold, currentTrack != nil {
                    await live.end()
                    currentTrack = nil
                    consecutiveEmptyPolls = 0
                }
            }
        } catch {
            print("[Polling] Error: \(error)")
        }
    }
}
