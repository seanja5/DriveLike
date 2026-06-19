import SwiftUI

// MARK: - Design Tokens (shared across all tabs via private extension)

extension Color {
    static let bgDeep     = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let bgBase     = Color(red: 0.050, green: 0.050, blue: 0.063)
    static let surface    = Color.white.opacity(0.055)
    static let border     = Color.white.opacity(0.09)
    static let textPrim   = Color(red: 0.93, green: 0.93, blue: 0.94)
    static let textMuted  = Color(red: 0.54, green: 0.56, blue: 0.60)
    static let accent     = Color(red: 0.114, green: 0.729, blue: 0.333)
    static let accentTeal = Color(red: 0.05, green: 0.85, blue: 0.65)
}

// MARK: - Tab Definition

enum AppTab: String, CaseIterable, Identifiable {
    case now, drives, discover, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .now:      return "Now"
        case .drives:   return "Drives"
        case .discover: return "Discover"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .now:      return "waveform"
        case .drives:   return "car"
        case .discover: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    var activeIcon: String {
        switch self {
        case .now:      return "waveform"
        case .drives:   return "car.fill"
        case .discover: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @State private var selectedTab: AppTab = .now

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.bgBase, Color.bgDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if auth.isAuthenticated {
                ZStack(alignment: .bottom) {
                    // Tab content
                    Group {
                        switch selectedTab {
                        case .now:      NowPlayingTab()
                        case .drives:   DrivesView()
                        case .discover: DiscoverView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Custom glass tab bar
                    CustomTabBar(selectedTab: $selectedTab)
                }
                .ignoresSafeArea(.keyboard)
            } else {
                WelcomeView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                            .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.accent : Color.textMuted)
                            .scaleEffect(selectedTab == tab ? 1.05 : 1.0)

                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.accent : Color.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    Rectangle()
                        .fill(Color.border)
                        .frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea()
        )
    }
}

// MARK: - Welcome (unauthenticated)

struct WelcomeView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @State private var glowOn = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.65, accentY: 0.25)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
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

// MARK: - Ambient Background (shared by all tabs)

struct AmbientBackground: View {
    var accentHue: Double = 0.38
    var accentX: Double = 0.6
    var accentY: Double = 0.2
    @State private var driftA = false
    @State private var driftB = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.11))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(
                        x: geo.size.width * (accentX - 0.5) + (driftA ? 28 : -28),
                        y: geo.size.height * (accentY - 0.5) + (driftA ? -18 : 18)
                    )
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: driftA)

                Circle()
                    .fill(Color(hue: 0.75, saturation: 0.6, brightness: 0.6).opacity(0.08))
                    .frame(width: 240, height: 240)
                    .blur(radius: 80)
                    .offset(
                        x: geo.size.width * -0.25 + (driftB ? -24 : 24),
                        y: geo.size.height * 0.25 + (driftB ? 32 : -32)
                    )
                    .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1.5), value: driftB)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { driftA = true; driftB = true }
    }
}

// MARK: - Now Playing Tab

private struct NowPlayingTab: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.7, accentY: 0.15)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        LivePill()
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 8)

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

                    Spacer().frame(height: 100)
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
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)

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

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 12)

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
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.border, lineWidth: 1))
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

struct OrganicWaveform: View {
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
        let w1 = sin(x * .pi * 3.0 + t * 2.3)  * 0.42
        let w2 = sin(x * .pi * 7.0 + t * 3.9)  * 0.22
        let w3 = sin(x * .pi * 11.5 + t * 5.1) * 0.12
        let env = (sin(x * .pi) + 1) / 2
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

// MARK: - Press Scale Button Style (shared globally)

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
