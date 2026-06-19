import SwiftUI
import CoreLocation

// MARK: - Drive Session Model

struct DriveSession: Identifiable {
    let id = UUID()
    let tracks: [LikedTrack]
    var date: Date { tracks.first?.likedAt ?? Date() }
}

func buildSessions(from tracks: [LikedTrack]) -> [DriveSession] {
    guard !tracks.isEmpty else { return [] }
    let sorted = tracks.sorted { $0.likedAt < $1.likedAt }
    var buckets: [[LikedTrack]] = [[sorted[0]]]
    for track in sorted.dropFirst() {
        let gap = track.likedAt.timeIntervalSince(buckets.last!.last!.likedAt)
        if gap > 1800 { buckets.append([track]) }
        else { buckets[buckets.count - 1].append(track) }
    }
    return buckets.reversed().map { DriveSession(tracks: $0) }
}

// MARK: - Drives View

struct DrivesView: View {
    @EnvironmentObject var polling: PlaybackPollingManager
    @EnvironmentObject var auth: SpotifyAuthManager
    @Environment(\.openURL) var openURL

    @State private var sessionLocations: [UUID: String] = [:]
    @State private var audioFeatures: [String: AudioFeatures] = [:]
    @State private var trackDetails: [String: TrackDetails] = [:]
    @State private var selectedTrack: LikedTrack? = nil
    @State private var showFullMap = false
    @State private var appear = false

    private let api = SpotifyAPIManager.shared

    var tracksWithLocation: [LikedTrack] {
        polling.likedTracks.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var sessions: [DriveSession] {
        buildSessions(from: polling.likedTracks)
    }

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.3, accentY: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Map preview card
                    MapPreviewCard(tracks: tracksWithLocation) { showFullMap = true }
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 20)

                    // Page header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("My Drives")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrim)
                            Text("\(sessions.count) drives · \(polling.likedTracks.count) songs")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    if polling.likedTracks.isEmpty {
                        emptyState
                    } else {
                        statsCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        ForEach(sessions) { session in
                            SessionSection(
                                session: session,
                                locationLabel: sessionLocations[session.id],
                                audioFeatures: audioFeatures,
                                openURL: openURL,
                                onTrackTap: { selectedTrack = $0 }
                            )
                            .padding(.bottom, 24)
                            .onAppear { geocodeSession(session) }
                        }
                    }

                    Spacer().frame(height: 100)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            DriveMapView(tracks: tracksWithLocation, trackDetails: trackDetails)
        }
        .sheet(item: $selectedTrack) { track in
            TrackDetailSheet(
                track: track,
                details: trackDetails[track.trackId],
                features: audioFeatures[track.trackId],
                openURL: openURL
            )
            .onAppear {
                fetchTrackDetails(for: track)
                fetchAudioFeatures(for: track)
            }
        }
        .onAppear {
            audioFeatures = SharedStore.readAudioFeaturesCache()
            trackDetails  = SharedStore.readTrackDetailsCache()
            appear = true
            fetchMissingFeatures()
            // Pull caches from Supabase if local is empty (e.g. after reinstall)
            Task {
                guard let userId = auth.spotifyUserId, !userId.isEmpty else { return }
                if trackDetails.isEmpty,
                   let remote = try? await SupabaseManager.shared.fetchTrackDetailsCache(userId: userId),
                   !remote.isEmpty {
                    trackDetails = remote
                    SharedStore.writeTrackDetailsCache(remote)
                }
                if audioFeatures.isEmpty,
                   let remote = try? await SupabaseManager.shared.fetchAudioFeaturesCache(userId: userId),
                   !remote.isEmpty {
                    audioFeatures = remote
                    SharedStore.writeAudioFeaturesCache(remote)
                }
            }
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        let topArtist = topArtistName()
        let avgBPM    = averageBPM()

        return HStack(spacing: 0) {
            StatItem(value: "\(polling.likedTracks.count)", label: "Songs")
            Divider().background(Color.border).frame(height: 36)
            StatItem(value: "\(sessions.count)", label: "Drives")
            Divider().background(Color.border).frame(height: 36)
            StatItem(value: topArtist ?? "—", label: "Top Artist", compact: true)
            if let bpm = avgBPM {
                Divider().background(Color.border).frame(height: 36)
                StatItem(value: "\(Int(bpm))", label: "Avg BPM")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.border, lineWidth: 1))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Color.textMuted.opacity(0.6))
            Text("No drives yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textPrim)
            Text("Like songs from the lock screen\nwhile driving to see them here")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Computed stats

    private func topArtistName() -> String? {
        let counts = Dictionary(grouping: polling.likedTracks, by: \.artistName)
            .mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func averageBPM() -> Double? {
        let bpms = polling.likedTracks.compactMap { audioFeatures[$0.trackId]?.tempo }
        guard !bpms.isEmpty else { return nil }
        return bpms.reduce(0, +) / Double(bpms.count)
    }

    // MARK: - Location geocoding

    private func geocodeSession(_ session: DriveSession) {
        guard sessionLocations[session.id] == nil else { return }
        let tracks = session.tracks

        // Reverse geocode first and last track locations
        guard let firstTrack = tracks.first,
              let lat1 = firstTrack.latitude, let lon1 = firstTrack.longitude
        else { return }

        let startLoc = CLLocation(latitude: lat1, longitude: lon1)
        CLGeocoder().reverseGeocodeLocation(startLoc) { [session] placemarks, _ in
            guard let p1 = placemarks?.first else { return }
            let startName = p1.locality ?? p1.subLocality ?? p1.name ?? ""

            // If last track has a different location, also geocode that
            if let lastTrack = tracks.last,
               let lat2 = lastTrack.latitude, let lon2 = lastTrack.longitude,
               lastTrack.trackId != firstTrack.trackId {
                let distance = CLLocation(latitude: lat2, longitude: lon2)
                    .distance(from: startLoc)
                if distance > 800 {
                    CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat2, longitude: lon2)) { [session, startName] placemarks2, _ in
                        let endName = placemarks2?.first.flatMap { $0.locality ?? $0.subLocality ?? $0.name } ?? ""
                        let label = endName.isEmpty || endName == startName
                            ? "Near \(startName)"
                            : "\(startName) → \(endName)"
                        DispatchQueue.main.async { self.sessionLocations[session.id] = label }
                    }
                    return
                }
            }
            let label = startName.isEmpty ? nil : "Near \(startName)"
            DispatchQueue.main.async { self.sessionLocations[session.id] = label }
        }
    }

    // MARK: - Lazy feature fetching

    private func fetchMissingFeatures() {
        let missing = polling.likedTracks.filter { audioFeatures[$0.trackId] == nil }
        for track in missing {
            Task {
                guard let feat = try? await api.getAudioFeatures(id: track.trackId) else { return }
                await MainActor.run {
                    audioFeatures[track.trackId] = feat
                    SharedStore.writeAudioFeaturesCache(audioFeatures)
                }
                if let userId = auth.spotifyUserId {
                    await SupabaseManager.shared.upsertAudioFeatures(feat, trackId: track.trackId, userId: userId)
                }
            }
        }
    }

    private func fetchTrackDetails(for track: LikedTrack) {
        guard trackDetails[track.trackId] == nil else { return }
        Task {
            guard let details = try? await api.getTrackDetails(id: track.trackId) else { return }
            await MainActor.run {
                trackDetails[track.trackId] = details
                SharedStore.writeTrackDetailsCache(trackDetails)
            }
            if let userId = auth.spotifyUserId {
                await SupabaseManager.shared.upsertTrackDetails(details, trackId: track.trackId, userId: userId)
            }
        }
    }

    private func fetchAudioFeatures(for track: LikedTrack) {
        guard audioFeatures[track.trackId] == nil else { return }
        Task {
            guard let feat = try? await api.getAudioFeatures(id: track.trackId) else { return }
            await MainActor.run {
                audioFeatures[track.trackId] = feat
                SharedStore.writeAudioFeaturesCache(audioFeatures)
            }
            if let userId = auth.spotifyUserId {
                await SupabaseManager.shared.upsertAudioFeatures(feat, trackId: track.trackId, userId: userId)
            }
        }
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let value: String
    let label: String
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: compact ? 13 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Section

private struct SessionSection: View {
    let session: DriveSession
    let locationLabel: String?
    let audioFeatures: [String: AudioFeatures]
    let openURL: OpenURLAction
    let onTrackTap: (LikedTrack) -> Void

    private var sessionDateString: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.date) { return "Today" }
        if cal.isDateInYesterday(session.date) { return "Yesterday" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        return df.string(from: session.date)
    }

    private var sessionTimeString: String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: session.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Session header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accent)
                    Text(sessionDateString.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .tracking(1.2)
                    Spacer()
                    Text("\(session.tracks.count) songs")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }

                HStack(spacing: 6) {
                    Text(sessionTimeString)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)

                    if let loc = locationLabel {
                        Text("·")
                            .foregroundStyle(Color.textMuted.opacity(0.4))
                        Text(loc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Track rows
            VStack(spacing: 6) {
                ForEach(Array(session.tracks.reversed().enumerated()), id: \.element.id) { idx, track in
                    DriveTrackRow(
                        track: track,
                        bpm: audioFeatures[track.trackId].map { Int($0.tempo) },
                        onTap: { onTrackTap(track) }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Drive Track Row

private struct DriveTrackRow: View {
    let track: LikedTrack
    let bpm: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accent.opacity(0.7))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.trackName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrim)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let bpm {
                    Text("\(bpm) BPM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accent.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accent.opacity(0.1))
                                .overlay(Capsule().strokeBorder(Color.accent.opacity(0.2), lineWidth: 1))
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.border, lineWidth: 1))
            )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("\(track.trackName) by \(track.artistName)")
    }
}

// MARK: - Track Detail Sheet

struct TrackDetailSheet: View {
    let track: LikedTrack
    let details: TrackDetails?
    let features: AudioFeatures?
    let openURL: OpenURLAction

    @Environment(\.dismiss) var dismiss

    private var likedDateString: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: track.likedAt)
    }

    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.border)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Album art
                        Group {
                            if let url = details.map({ URL(string: $0.albumArtURL) }) ?? nil {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    case .failure, .empty:
                                        albumArtPlaceholder
                                    @unknown default:
                                        albumArtPlaceholder
                                    }
                                }
                            } else {
                                albumArtPlaceholder
                            }
                        }
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accent.opacity(0.2), radius: 24, y: 12)

                        // Track info
                        VStack(spacing: 6) {
                            Text(track.trackName)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrim)
                                .multilineTextAlignment(.center)
                            Text(track.artistName)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.textMuted)
                            if let albumName = details?.albumName {
                                Text(albumName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textMuted.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 32)

                        // Audio feature pills
                        if let feat = features {
                            HStack(spacing: 10) {
                                FeaturePill(icon: "waveform", label: "\(Int(feat.tempo)) BPM")
                                FeaturePill(icon: "bolt.fill", label: energyLabel(feat.energy))
                                FeaturePill(icon: "face.smiling", label: moodLabel(feat.valence))
                            }
                            .padding(.horizontal, 24)
                        }

                        // Metadata
                        VStack(spacing: 10) {
                            MetaRow(label: "Liked at", value: likedDateString)
                            if let durationMs = details?.durationMs {
                                MetaRow(label: "Duration", value: formatDuration(durationMs))
                            }
                        }
                        .padding(.horizontal, 24)

                        // Open in Spotify
                        Button {
                            dismiss()
                            if let url = URL(string: "spotify://track/\(track.trackId)") {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Open in Spotify")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(Color.accent)
                                    .shadow(color: Color.accent.opacity(0.35), radius: 16, y: 8)
                            )
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(.horizontal, 24)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var albumArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.surface)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(Color.textMuted)
            )
    }

    private func energyLabel(_ e: Double) -> String {
        switch e {
        case 0..<0.33: return "Calm"
        case 0.33..<0.66: return "Moderate"
        default: return "High Energy"
        }
    }

    private func moodLabel(_ v: Double) -> String {
        switch v {
        case 0..<0.33: return "Melancholic"
        case 0.33..<0.66: return "Neutral"
        default: return "Upbeat"
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let total = ms / 1000
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct FeaturePill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textPrim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.surface)
                .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        )
    }
}

private struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textPrim)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.border, lineWidth: 1))
        )
    }
}

