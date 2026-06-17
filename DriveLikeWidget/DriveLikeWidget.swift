import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// MARK: - Widget Configuration

struct DriveLikeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveLikeActivityAttributes.self) { ctx in
            LockScreenView(ctx: ctx)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                // Expanded pill
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.green)
                        .font(.title3)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeartButton(ctx: ctx)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.state.trackName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(ctx.state.artistName)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Image(systemName: ctx.state.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(ctx.state.isLiked ? .white : Color(.systemGray))
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Lock Screen Layout

struct LockScreenView: View {
    let ctx: ActivityViewContext<DriveLikeActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Spotify-green music icon
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.green)

            // Track info
            VStack(alignment: .leading, spacing: 3) {
                Text(ctx.state.trackName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(ctx.state.artistName)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer()

            // Like button
            HeartButton(ctx: ctx)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Heart Button (iOS 17 interactive / iOS 16 static)

struct HeartButton: View {
    let ctx: ActivityViewContext<DriveLikeActivityAttributes>

    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: LikeTrackIntent(
                trackId:    ctx.state.trackId,
                trackName:  ctx.state.trackName,
                artistName: ctx.state.artistName
            )) {
                heartImage
            }
            .disabled(ctx.state.isLiked)
            .tint(.clear)
        } else {
            heartImage
        }
    }

    private var heartImage: some View {
        Image(systemName: ctx.state.isLiked ? "heart.fill" : "heart")
            .font(.title)
            .foregroundStyle(.white)
            .contentTransition(.identity)
    }
}
