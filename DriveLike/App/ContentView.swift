import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgDeep    = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let bgBase    = Color(red: 0.050, green: 0.050, blue: 0.063)
    static let surface   = Color.white.opacity(0.055)
    static let border    = Color.white.opacity(0.09)
    static let textPrim  = Color(red: 0.93, green: 0.93, blue: 0.94)
    static let textMuted = Color(red: 0.54, green: 0.56, blue: 0.60)
    static let accent    = Color(red: 0.114, green: 0.729, blue: 0.333)  // Spotify green
    static let accentTeal = Color(red: 0.05, green: 0.85, blue: 0.65)
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.bgBase, Color.bgDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if auth.isAuthenticated {
                ConnectedView()
            } else {
                WelcomeView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Welcome (unauthenticated)

private struct WelcomeView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @State private var glowOn = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.65, accentY: 0.25)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    // Logo mark
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.15))
                            .frame(width: 100, height: 100)
                            .blur(radius: glowOn ? 28 : 14)

                        Circle()
                            .strokeBorder(Color.accent.opacity(0.25), lineWidth: 1)
                            .frame(width: 82, height: 82)

                        Image(systemName: "car.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color.accent)
                    }
                    .animation(
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                        value: glowOn
                    )

                    VStack(spacing: 12) {
                        Text("DriveLike")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrim)

                        Text("Like songs while you drive.\nNo unlocking. No looking down.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }
                }

                Spacer()

                VStack(spacing: 14) {
                    Button(action: { auth.startAuthentication() }) {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Connect with Spotify")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            ZStack {
                                Capsule().fill(Color.accent)
                                Capsule()
                                    .fill(Color.accent)
                                    .blur(radius: 16)
                                    .opacity(0.5)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        )
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Connect with Spotify")

                    Text("Saves songs locally · One tap to open in Spotify")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 56)
            }
        }
        .onAppear { glowOn = true }
    }
}

// MARK: - Ambient Background

private struct AmbientBackground: View {
    var accentHue: Double = 0.38
    var accentX: Double = 0.6
    var accentY: Double = 0.2
    @State private var driftA = false
    @State private var driftB = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Green blob
                Circle()
                    .fill(Color.accent.opacity(0.13))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(
                        x: geo.size.width * (accentX - 0.5) + (driftA ? 28 : -28),
                        y: geo.size.height * (accentY - 0.5) + (driftA ? -18 : 18)
                    )
                    .animation(
                        .easeInOut(duration: 7).repeatForever(autoreverses: true),
                        value: driftA
                    )

                // Purple blob
                Circle()
                    .fill(Color(hue: 0.75, saturation: 0.6, brightness: 0.6).opacity(0.09))
                    .frame(width: 240, height: 240)
                    .blur(radius: 80)
                    .offset(
                        x: geo.size.width * -0.25 + (driftB ? -24 : 24),
                        y: geo.size.height * 0.25 + (driftB ? 32 : -32)
                    )
                    .animation(
                        .easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1.5),
                        value: driftB
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { driftA = true; driftB = true }
    }
}

// MARK: - Connected

private struct ConnectedView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @Environment(\.openURL) var openURL
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.7, accentY: 0.15)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top bar
                    HStack(alignment: .center) {
                        LivePill()
                        Spacer()
                        Button {
                            auth.logout()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.surface)
                                        .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                                )
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Disconnect Spotify")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                    // Now playing card
                    Group {
                        if let track = polling.currentTrack {
                            NowPlayingCard(track: track)
                        } else {
                            IdleCard()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    // Refresh
                    Button {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await polling.forcePoll()
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color.textMuted)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.textMuted)
                            }
                            Text(isRefreshing ? "Checking…" : "Refresh")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.surface)
                                .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                        )
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(isRefreshing)
                    .padding(.top, 18)
                    .accessibilityLabel(isRefreshing ? "Checking for playing track" : "Refresh currently playing")

                    // Liked tracks
                    if !polling.likedTracks.isEmpty {
                        LikedTracksSection(tracks: polling.likedTracks, openURL: openURL)
                            .padding(.top, 40)
                    }

                    Spacer().frame(height: 60)
                }
            }
        }
    }
}

// MARK: - Live Pill

private struct LivePill: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
                Circle()
                    .fill(Color.accent)
                    .frame(width: 7, height: 7)
            }
            .animation(
                .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                value: pulse
            )

            Text("Live")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.accent.opacity(0.1))
                .overlay(Capsule().strokeBorder(Color.accent.opacity(0.2), lineWidth: 1))
        )
        .onAppear { pulse = true }
    }
}

// MARK: - Now Playing Card

private struct NowPlayingCard: View {
    let track: SpotifyTrack
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            // Waveform area
            ZStack {
                Ellipse()
                    .fill(Color.accent.opacity(0.18))
                    .frame(width: 160, height: 40)
                    .blur(radius: 28)
                    .offset(y: 32)

                OrganicWaveform()
                    .frame(height: 100)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Track info
            VStack(spacing: 5) {
                Text(track.name)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrim)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(track.artistName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(Color.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.spring(dampingFraction: 0.82), value: appear)
        .onAppear { appear = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing: \(track.name) by \(track.artistName)")
    }
}

// MARK: - Organic Waveform

private struct OrganicWaveform: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private let barCount = 30

    var body: some View {
        if reduceMotion {
            staticBars
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    drawBars(in: ctx, size: size, t: timeline.date.timeIntervalSince1970)
                }
            }
        }
    }

    private var staticBars: some View {
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(0..<barCount, id: \.self) { i in
                let norm = sin(Double(i) / Double(barCount) * .pi)
                Capsule()
                    .fill(Color.accent.opacity(0.6 + norm * 0.4))
                    .frame(width: 3.5, height: 12 + norm * 52)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBars(in ctx: GraphicsContext, size: CGSize, t: Double) {
        let barCount = self.barCount
        let barW: CGFloat = 4
        let gap: CGFloat  = 3
        let totalW = CGFloat(barCount) * (barW + gap) - gap
        let startX = (size.width - totalW) / 2
        let centerY = size.height / 2

        for i in 0..<barCount {
            let h = barHeight(index: i, total: barCount, t: t)
            let x = startX + CGFloat(i) * (barW + gap)
            let y = centerY - h / 2
            let rect = CGRect(x: x, y: y, width: barW, height: h)
            let path = Path(roundedRect: rect, cornerRadius: barW / 2)

            ctx.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.accentTeal.opacity(0.75), location: 0),
                    .init(color: Color.accent, location: 1)
                ]),
                startPoint: CGPoint(x: x, y: y),
                endPoint: CGPoint(x: x, y: y + h)
            ))
        }
    }

    private func barHeight(index: Int, total: Int, t: Double) -> CGFloat {
        let x  = Double(index) / Double(total)

        // Three overlapping sine waves at musical interval ratios
        let w1 = sin(x * .pi * 3.0 + t * 2.3)  * 0.42
        let w2 = sin(x * .pi * 7.0 + t * 3.9)  * 0.22
        let w3 = sin(x * .pi * 11.5 + t * 5.1) * 0.12

        // Slow envelope (wide arch across bars)
        let env = (sin(x * .pi) + 1) / 2

        // Beat transient — periodic kick every ~0.55s
        let beat = max(0, sin(t * .pi / 0.55)) * 0.28

        let raw = (w1 + w2 + w3) * env + beat
        return CGFloat(10 + (raw + 1) / 2 * 76)
    }
}

// MARK: - Idle Card

private struct IdleCard: View {
    @State private var appear = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.textMuted.opacity(0.07))
                    .frame(width: 76, height: 76)
                Image(systemName: "waveform.slash")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
            }

            VStack(spacing: 7) {
                Text("Nothing playing")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrim)
                Text("Open Spotify and start a song,\nthen tap Refresh")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.border, lineWidth: 1))
        )
        .opacity(appear ? 1 : 0)
        .animation(.easeOut(duration: 0.28), value: appear)
        .onAppear { appear = true }
        .accessibilityLabel("No track currently playing")
    }
}

// MARK: - Liked Tracks Section

private struct LikedTracksSection: View {
    let tracks: [LikedTrack]
    let openURL: OpenURLAction
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accent)
                Text("LIKED WHILE DRIVING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.4)
                Spacer()
                Text("\(tracks.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.surface)
                            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                    )
            }
            .padding(.horizontal, 24)

            // Rows
            VStack(spacing: 6) {
                ForEach(Array(tracks.reversed().prefix(50).enumerated()), id: \.element.id) { idx, track in
                    LikedTrackRow(track: track, index: idx, openURL: openURL)
                }
            }
            .padding(.horizontal, 20)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.spring(dampingFraction: 0.85).delay(0.08), value: appear)
        .onAppear { appear = true }
    }
}

private struct LikedTrackRow: View {
    let track: LikedTrack
    let index: Int
    let openURL: OpenURLAction
    @State private var appear = false

    var body: some View {
        Button {
            if let url = URL(string: "spotify://track/\(track.trackId)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                // Row number
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textMuted.opacity(0.45))
                    .frame(width: 22, alignment: .trailing)

                // Track info
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

                // Open in Spotify arrow
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressScaleStyle())
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 5)
        .animation(
            .spring(dampingFraction: 0.82).delay(Double(index) * 0.035),
            value: appear
        )
        .onAppear { appear = true }
        .accessibilityLabel("Open \(track.trackName) by \(track.artistName) in Spotify")
    }
}

// MARK: - Press Scale Button Style

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}
