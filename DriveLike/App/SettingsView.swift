import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: SpotifyAuthManager
    @EnvironmentObject var polling: PlaybackPollingManager
    @AppStorage("speedGatingEnabled") private var speedGatingEnabled = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        ZStack {
            AmbientBackground(accentHue: 0.38, accentX: 0.4, accentY: 0.6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrim)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 32)

                    // Driving section
                    SettingsSection(title: "DRIVING") {
                        VStack(spacing: 1) {
                            ToggleRow(
                                icon: "speedometer",
                                title: "Speed-based widget",
                                subtitle: "Only show the lock screen widget when moving at driving speed (≥22 mph)",
                                isOn: $speedGatingEnabled
                            )

                            if speedGatingEnabled {
                                SpeedStatusRow(isDriving: polling.isDriving)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Stats section
                    SettingsSection(title: "YOUR STATS") {
                        VStack(spacing: 1) {
                            StatRow(icon: "heart.fill", label: "Songs saved", value: "\(polling.likedTracks.count)")
                            StatRow(icon: "car.fill", label: "Drives recorded",
                                    value: "\(buildSessions(from: polling.likedTracks).count)")
                            if let top = topArtist() {
                                StatRow(icon: "music.mic", label: "Favorite artist", value: top)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Account section
                    SettingsSection(title: "ACCOUNT") {
                        VStack(spacing: 1) {
                            InfoRow(icon: "music.note", label: "Spotify", value: "Connected")
                            Button {
                                showDisconnectConfirm = true
                            } label: {
                                SettingsCellBase {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.red)
                                    Text("Disconnect Spotify")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // App info
                    VStack(spacing: 4) {
                        Text("DriveLike · v1.0")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted.opacity(0.5))
                        Text("Saves songs locally while you drive")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textMuted.opacity(0.35))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
        }
        .confirmationDialog(
            "Disconnect Spotify?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { auth.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved songs will remain in the app.")
        }
    }

    private func topArtist() -> String? {
        let counts = Dictionary(grouping: polling.likedTracks, by: \.artistName)
            .mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .tracking(1.2)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
            )
        }
    }
}

// MARK: - Row types

private struct SettingsCellBase<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textPrim)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(Color.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

private struct SpeedStatusRow: View {
    let isDriving: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDriving ? "speedometer" : "minus.circle")
                .font(.system(size: 14))
                .foregroundStyle(isDriving ? Color.accent : Color.textMuted)
                .frame(width: 22)
            Text(isDriving ? "Driving speed detected" : "Not at driving speed")
                .font(.system(size: 13))
                .foregroundStyle(isDriving ? Color.accent : Color.textMuted)
            Spacer()
            Circle()
                .fill(isDriving ? Color.accent : Color.textMuted.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }
}

private struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        SettingsCellBase {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrim)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        SettingsCellBase {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrim)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
        }
    }
}

