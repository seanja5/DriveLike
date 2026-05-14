import Foundation

@MainActor
final class PlaybackPollingManager: ObservableObject {
    static let shared = PlaybackPollingManager()

    @Published var currentTrack: SpotifyTrack?

    private var timer: Timer?
    private let auth = SpotifyAuthManager.shared
    private let api  = SpotifyAPIManager.shared
    private let live = LiveActivityManager.shared

    // Require 2 consecutive "nothing playing" responses before ending the Live Activity.
    // This prevents a single slow/flaky API response from killing the activity mid-song.
    private var consecutiveEmptyPolls = 0
    private let emptyPollThreshold = 2

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

    /// Called from AppDelegate background tasks — same logic as the timer poll.
    func forcePoll() async {
        await poll()
    }

    // MARK: - Private

    private func poll() async {
        await auth.refreshIfNeeded()
        do {
            let track = try await api.getCurrentlyPlaying()
            if let track {
                consecutiveEmptyPolls = 0
                if currentTrack?.id != track.id {
                    if currentTrack != nil { await live.end() }
                    await live.start(track: track)
                    currentTrack = track
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
