import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var polling: PlaybackPollingManager
    @Environment(\.openURL) var openURL
    @State private var appear = false
    @State private var isLoading = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.75, accentX: 0.7, accentY: 0.3)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Page header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Discover")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrim)
                            Text("Based on what you like while driving")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        if !polling.likedTracks.isEmpty {
                            Button {
                                guard !isLoading else { return }
                                isLoading = true
                                Task {
                                    await polling.fetchRecommendations()
                                    isLoading = false
                                }
                            } label: {
                                Image(systemName: isLoading ? "arrow.clockwise" : "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.textMuted)
                                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                                    .animation(isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isLoading)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color.surface)
                                            .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                                    )
                            }
                            .buttonStyle(PressScaleStyle())
                            .disabled(isLoading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 28)

                    if polling.likedTracks.isEmpty {
                        emptyStateLikeSongs
                    } else if polling.recommendations.isEmpty && isLoading {
                        loadingState
                    } else if polling.recommendations.isEmpty {
                        emptyStateLoading
                    } else {
                        recommendationList
                    }

                    Spacer().frame(height: 100)
                }
            }
        }
        .onAppear {
            appear = true
            if polling.recommendations.isEmpty && !polling.likedTracks.isEmpty {
                isLoading = true
                Task {
                    await polling.fetchRecommendations()
                    isLoading = false
                }
            }
        }
    }

    // MARK: - States

    private var emptyStateLoading: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(Color.textMuted.opacity(0.6))
            }
            VStack(spacing: 8) {
                Text("Tap refresh to load")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrim)
                Text("Hit the refresh button above\nto find music based on your drives")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    private var emptyStateLikeSongs: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(Color.textMuted.opacity(0.6))
            }
            VStack(spacing: 8) {
                Text("Nothing to discover yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrim)
                Text("Like songs while driving and we'll\nfind similar music for you here")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                ShimmerRow()
                    .opacity(appear ? 1 : 0)
                    .animation(.easeIn(duration: 0.2).delay(Double(i) * 0.06), value: appear)
            }
        }
        .padding(.horizontal, 20)
    }

    private var recommendationList: some View {
        VStack(spacing: 6) {
            ForEach(Array(polling.recommendations.enumerated()), id: \.element.id) { idx, track in
                RecommendationRow(track: track, index: idx, openURL: openURL)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Recommendation Row

private struct RecommendationRow: View {
    let track: SpotifyTrack
    let index: Int
    let openURL: OpenURLAction
    @State private var appear = false

    var body: some View {
        Button {
            if let url = URL(string: "spotify://track/\(track.id)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                // Index
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textMuted.opacity(0.45))
                    .frame(width: 22, alignment: .trailing)

                // Sparkle indicator (shows these are recommendations)
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hue: 0.75, saturation: 0.6, brightness: 0.8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrim)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.accent.opacity(0.12))
                            .overlay(Circle().strokeBorder(Color.accent.opacity(0.2), lineWidth: 1))
                    )
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
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 5)
        .animation(.spring(dampingFraction: 0.82).delay(Double(index) * 0.03), value: appear)
        .onAppear { appear = true }
        .accessibilityLabel("Open \(track.name) by \(track.artistName) in Spotify")
    }
}

// MARK: - Shimmer loading row

private struct ShimmerRow: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.06))
                .frame(width: 22, height: 10)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 120, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.border, lineWidth: 1))
        )
    }
}

