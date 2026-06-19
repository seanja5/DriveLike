import Foundation
import CoreLocation

@MainActor
final class PlaybackPollingManager: NSObject, ObservableObject {
    static let shared = PlaybackPollingManager()

    @Published var currentTrack: SpotifyTrack?
    @Published var reauthNeeded = false
    @Published var likedTracks: [LikedTrack] = []
    @Published var recommendations: [SpotifyTrack] = []
    @Published var isDriving = false

    private var timer: Timer?
    private let auth     = SpotifyAuthManager.shared
    private let api      = SpotifyAPIManager.shared
    private let live     = LiveActivityManager.shared
    private let defaults = UserDefaults(suiteName: "group.com.drivelike.app")!

    private var consecutiveEmptyPolls = 0
    private let emptyPollThreshold    = 2

    private var recentSpeeds: [Double] = []
    private var locationManager: CLLocationManager?
    private var lastLikedCount = 0
    private var isPolling = false   // prevents concurrent polls from overlapping

    // MARK: - Public

    func start() {
        guard timer == nil else { return }
        setupLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { @MainActor in
            await poll()
            // Pull from Supabase on fresh install (when local store is empty)
            if likedTracks.isEmpty { await syncFromCloud() }
        }
    }

    func syncFromCloud() async {
        guard let userId = auth.spotifyUserId, !userId.isEmpty else { return }
        guard let remote = try? await SupabaseManager.shared.fetchLikedTracks(userId: userId),
              !remote.isEmpty else { return }
        let local = SharedStore.readLikedTracks()
        // Merge: local takes precedence (may have newer location data from the widget)
        var merged: [String: LikedTrack] = Dictionary(uniqueKeysWithValues: remote.map { ($0.trackId, $0) })
        for track in local { merged[track.trackId] = track }
        let result = Array(merged.values).sorted { $0.likedAt < $1.likedAt }
        SharedStore.writeLikedTracks(result)
        likedTracks = result
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        locationManager?.stopUpdatingLocation()
    }

    func forcePoll() async {
        await poll()
    }


    func fetchRecommendations() async {
        guard !likedTracks.isEmpty else { return }
        let artistCounts = Dictionary(grouping: likedTracks, by: \.artistName).mapValues(\.count)
        let topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(4).map(\.key)
        let excludeIds = Set(likedTracks.map(\.trackId))
        if let recs = try? await api.getDiscoverTracks(topArtists: topArtists, excludeIds: excludeIds) {
            recommendations = recs
        }
    }

    // MARK: - Location setup

    private func setupLocation() {
        let lm = CLLocationManager()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Fire on every update (no minimum distance) so the app gets continuous
        // background execution time — this is what keeps the polling timer alive
        // while the phone is locked during a drive.
        lm.distanceFilter = kCLDistanceFilterNone
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        locationManager = lm
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
    }

    // MARK: - Poll

    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        reauthNeeded = SharedStore.reauthNeeded
        likedTracks  = SharedStore.readLikedTracks()
        await auth.refreshIfNeeded()

        // Fetch recommendations + sync to Supabase when liked count changes
        if likedTracks.count != lastLikedCount && !likedTracks.isEmpty {
            lastLikedCount = likedTracks.count
            await fetchRecommendations()
            if let userId = auth.spotifyUserId, !userId.isEmpty {
                let snapshot = likedTracks
                Task { await SupabaseManager.shared.upsertLikedTracks(snapshot, userId: userId) }
            }
        }

        do {
            let track = try await api.getCurrentlyPlaying()
            if let track {
                consecutiveEmptyPolls = 0

                let likedIds = SharedStore.readLikedIds()
                    .union(Set(defaults.stringArray(forKey: "drivelike_liked_ids") ?? []))
                let isLiked = likedIds.contains(track.id)

                if currentTrack?.id != track.id {
                    if currentTrack == nil {
                        // First song after launch or after silence — Activity.request() requires
                        // foreground, which is safe here since currentTrack being nil means the
                        // app was just opened or music just resumed.
                        await live.start(track: track, isLiked: isLiked, speedGated: speedGateBlocks)
                    } else {
                        // Song changed while music was playing — update the existing activity
                        // in place. activity.update() works from the background, so the
                        // lock-screen widget transitions to the new song without opening the app.
                        await live.updateTrack(track, isLiked: isLiked)
                    }
                    currentTrack = track
                } else {
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

    // Returns true when speed gating is on AND we're not at driving speed
    private var speedGateBlocks: Bool {
        let gatingEnabled = UserDefaults.standard.bool(forKey: "speedGatingEnabled")
        return gatingEnabled && !isDriving
    }
}

// MARK: - CLLocationManagerDelegate

extension PlaybackPollingManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let speed = loc.speed  // m/s, negative if invalid
        let coordinate = loc.coordinate
        Task { @MainActor [weak self] in
            guard let self else { return }
            if speed >= 0 {
                self.recentSpeeds.append(speed)
                if self.recentSpeeds.count > 3 { self.recentSpeeds.removeFirst() }
                self.isDriving = self.recentSpeeds.filter { $0 > 10 }.count >= 2
            }
            SharedStore.writeCurrentLocation(StoredLocation(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                timestamp: Date()
            ))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
