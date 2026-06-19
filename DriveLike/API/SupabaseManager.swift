import Foundation

final class SupabaseManager {
    static let shared = SupabaseManager()

    private let baseURL = "https://naeqgcjyadqfqdeyncyg.supabase.co/rest/v1"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5hZXFnY2p5YWRxZnFkZXluY3lnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzMDM2NDYsImV4cCI6MjA5NDg3OTY0Nn0.xFqw1GtbHdUHt2bgbfMi0Slz22PnavuKNKnaxfR-IhU"

    private var baseHeaders: [String: String] {
        ["apikey": anonKey, "Authorization": "Bearer \(anonKey)", "Content-Type": "application/json"]
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: str) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(str)")
        }
        return d
    }()

    private func request(_ path: String, method: String = "GET",
                         body: Data? = nil, extra: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: URL(string: "\(baseURL)/\(path)")!)
        req.httpMethod = method
        baseHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        extra.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = body
        return req
    }

    // MARK: - Liked Tracks

    private struct LTRow: Codable {
        let spotify_user_id: String
        let track_id: String
        let track_name: String
        let artist_name: String
        let liked_at: Date
        let latitude: Double?
        let longitude: Double?
    }

    func upsertLikedTracks(_ tracks: [LikedTrack], userId: String) async {
        guard !tracks.isEmpty, !userId.isEmpty else { return }
        let rows = tracks.map {
            LTRow(spotify_user_id: userId, track_id: $0.trackId, track_name: $0.trackName,
                  artist_name: $0.artistName, liked_at: $0.likedAt,
                  latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let body = try? encoder.encode(rows) else { return }
        let req = request("liked_tracks", method: "POST", body: body,
                          extra: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        _ = try? await URLSession.shared.data(for: req)
    }

    func fetchLikedTracks(userId: String) async throws -> [LikedTrack] {
        guard !userId.isEmpty else { return [] }
        let req = request("liked_tracks?spotify_user_id=eq.\(userId)&order=liked_at.asc")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else { return [] }
        let rows = (try? decoder.decode([LTRow].self, from: data)) ?? []
        return rows.map {
            LikedTrack(trackId: $0.track_id, trackName: $0.track_name,
                       artistName: $0.artist_name, likedAt: $0.liked_at,
                       latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    // MARK: - Track Details Cache

    private struct TDRow: Codable {
        let spotify_user_id: String
        let track_id: String
        let album_name: String
        let album_art_url: String
        let duration_ms: Int
    }

    func upsertTrackDetails(_ details: TrackDetails, trackId: String, userId: String) async {
        guard !userId.isEmpty else { return }
        let row = TDRow(spotify_user_id: userId, track_id: trackId, album_name: details.albumName,
                        album_art_url: details.albumArtURL, duration_ms: details.durationMs)
        guard let body = try? encoder.encode(row) else { return }
        let req = request("track_details_cache", method: "POST", body: body,
                          extra: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        _ = try? await URLSession.shared.data(for: req)
    }

    func fetchTrackDetailsCache(userId: String) async throws -> [String: TrackDetails] {
        guard !userId.isEmpty else { return [:] }
        let req = request("track_details_cache?spotify_user_id=eq.\(userId)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else { return [:] }
        let rows = (try? JSONDecoder().decode([TDRow].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.track_id, TrackDetails(albumName: $0.album_name, albumArtURL: $0.album_art_url, durationMs: $0.duration_ms))
        })
    }

    // MARK: - Audio Features Cache

    private struct AFRow: Codable {
        let spotify_user_id: String
        let track_id: String
        let tempo: Double
        let energy: Double
        let valence: Double
    }

    func upsertAudioFeatures(_ features: AudioFeatures, trackId: String, userId: String) async {
        guard !userId.isEmpty else { return }
        let row = AFRow(spotify_user_id: userId, track_id: trackId,
                        tempo: features.tempo, energy: features.energy, valence: features.valence)
        guard let body = try? encoder.encode(row) else { return }
        let req = request("audio_features_cache", method: "POST", body: body,
                          extra: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        _ = try? await URLSession.shared.data(for: req)
    }

    func fetchAudioFeaturesCache(userId: String) async throws -> [String: AudioFeatures] {
        guard !userId.isEmpty else { return [:] }
        let req = request("audio_features_cache?spotify_user_id=eq.\(userId)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200 else { return [:] }
        let rows = (try? JSONDecoder().decode([AFRow].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.track_id, AudioFeatures(tempo: $0.tempo, energy: $0.energy, valence: $0.valence))
        })
    }
}
