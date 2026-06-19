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

// TrackDetails and AudioFeatures are defined in Shared/SharedStore.swift
// (must be in the Shared target so the widget extension can also reference them)
