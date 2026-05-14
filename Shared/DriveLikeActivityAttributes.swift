import ActivityKit
import Foundation

struct DriveLikeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackName: String
        var artistName: String
        var trackId: String
        var isLiked: Bool
    }
}
