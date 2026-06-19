import Foundation

struct SpotifyTrack: Codable, Equatable {
    let id: String
    let name: String
    let artistName: String
    var albumArtURL: String

    init(id: String, name: String, artistName: String, albumArtURL: String = "") {
        self.id = id
        self.name = name
        self.artistName = artistName
        self.albumArtURL = albumArtURL
    }
}

struct PlayerState: Decodable {
    let is_playing: Bool
    let item: TrackItem?
}

struct TrackItem: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: TrackAlbum?
}

struct TrackAlbum: Decodable {
    let images: [TrackAlbumImage]
}

struct TrackAlbumImage: Decodable {
    let url: String
}

struct SpotifyArtist: Decodable {
    let name: String
}

// TrackDetails and AudioFeatures are defined in Shared/SharedStore.swift
// (must be in the Shared target so the widget extension can also reference them)
