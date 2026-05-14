import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                if auth.isAuthenticated {
                    authenticatedView
                } else {
                    unauthenticatedView
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Authenticated

    private var authenticatedView: some View {
        VStack(spacing: 20) {
            Text("Connected to Spotify")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            if let track = polling.currentTrack {
                nowPlayingCard(track: track)
            } else {
                VStack(spacing: 8) {
                    Text("No track playing")
                        .foregroundStyle(.gray)
                        .font(.subheadline)
                    Text("Play something in Spotify and tap refresh")
                        .foregroundStyle(Color(.systemGray2))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }

            // Manual refresh button — triggers an immediate poll
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await polling.forcePoll()
                    isRefreshing = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "Checking\u{2026}" : "Refresh")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.green)
                .clipShape(Capsule())
            }
            .disabled(isRefreshing)
        }
    }

    private func nowPlayingCard(track: SpotifyTrack) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.green)
                .font(.title3)
            Text(track.name)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(track.artistName)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Unauthenticated

    private var unauthenticatedView: some View {
        VStack(spacing: 12) {
            Text("DriveLike")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Like songs while you drive")
                .font(.subheadline)
                .foregroundStyle(.gray)

            Spacer().frame(height: 8)

            Button(action: { auth.startAuthentication() }) {
                Label("Connect with Spotify", systemImage: "music.note")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green)
                    .clipShape(Capsule())
            }
        }
    }
}
