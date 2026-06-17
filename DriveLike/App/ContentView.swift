import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if auth.isAuthenticated {
                ConnectedView()
            } else {
                WelcomeView()
            }
        }
    }
}

// MARK: - Welcome (unauthenticated)

private struct WelcomeView: View {
    @EnvironmentObject var auth: SpotifyAuthManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "music.note")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 8) {
                    Text("DriveLike")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Like songs while you drive — without looking down.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.systemGray))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            Button(action: { auth.startAuthentication() }) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.body.weight(.semibold))
                    Text("Connect with Spotify")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - Connected

private struct ConnectedView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @Environment(\.openURL) var openURL
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatusPill(connected: true)
                    .padding(.top, 64)
                    .padding(.bottom, 32)

                if let track = polling.currentTrack {
                    NowPlayingContent(track: track)
                } else {
                    IdleContent()
                }

                // Controls
                VStack(spacing: 16) {
                    Button {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await polling.forcePoll()
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.semibold))
                            }
                            Text(isRefreshing ? "Checking…" : "Refresh")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(Capsule())
                    }
                    .disabled(isRefreshing)
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
                }

                // Liked while driving
                if !polling.likedTracks.isEmpty {
                    LikedTracksSection(tracks: polling.likedTracks, openURL: openURL)
                        .padding(.top, 32)
                }

                Button(action: { auth.logout() }) {
                    Text("Disconnect Spotify")
                        .font(.subheadline)
                        .foregroundStyle(Color(.systemGray))
                }
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Liked Tracks Section

private struct LikedTracksSection: View {
    let tracks: [LikedTrack]
    let openURL: OpenURLAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.semibold))
                Text("Liked While Driving")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.systemGray))
                Spacer()
            }
            .padding(.horizontal, 28)

            ForEach(tracks.reversed()) { track in
                LikedTrackRow(track: track, openURL: openURL)
            }
        }
    }
}

private struct LikedTrackRow: View {
    let track: LikedTrack
    let openURL: OpenURLAction

    var body: some View {
        Button {
            if let url = URL(string: "spotify://track/\(track.trackId)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.trackName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundStyle(Color(.systemGray))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGray2))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Pill

private struct StatusPill: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color(.systemGray))
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Not Connected")
                .font(.caption.weight(.medium))
                .foregroundStyle(connected ? Color.green : Color(.systemGray))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill((connected ? Color.green : Color(.systemGray)).opacity(0.12))
        )
    }
}

// MARK: - Now Playing Content

private struct NowPlayingContent: View {
    let track: SpotifyTrack

    var body: some View {
        VStack(spacing: 28) {
            AudioWaveform()
                .frame(height: 160)

            VStack(spacing: 6) {
                Text(track.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemGray))
                    .lineLimit(1)
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Idle Content

private struct IdleContent: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color(.systemGray2))
            Text("No track playing")
                .font(.headline)
                .foregroundStyle(Color(.systemGray))
            Text("Play something in Spotify, then tap Refresh")
                .font(.caption)
                .foregroundStyle(Color(.systemGray2))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Animated Waveform

private struct AudioWaveform: View {
    @State private var animating = false

    private let bars: [(height: CGFloat, delay: Double)] = [
        (38, 0.00), (82, 0.07), (58, 0.14), (124, 0.21), (72, 0.28),
        (148, 0.35), (54, 0.42), (108, 0.49), (88, 0.56), (44, 0.63),
        (118, 0.70), (66, 0.77)
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: animating ? bar.height : 6)
                    .animation(
                        .easeInOut(duration: 0.52)
                        .repeatForever(autoreverses: true)
                        .delay(bar.delay),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
