import Foundation

struct SpotifyTrack: Codable, Equatable {
    let id: String
    let name: String
    let artistName: String
}

struct PlayerState: Decodable {
    let is_playing: Bool
    let item: TrackItem?
}

struct TrackItem: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
}

struct SpotifyArtist: Decodable {
    let name: String
}
