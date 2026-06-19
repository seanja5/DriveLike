import Foundation

// MARK: - Shared metadata models (used by both app and widget targets)

struct TrackDetails: Codable {
    let albumName: String
    let albumArtURL: String
    let durationMs: Int
}

struct AudioFeatures: Codable {
    let tempo: Double    // BPM
    let energy: Double   // 0–1
    let valence: Double  // 0–1, sad → happy
}

struct LikedTrack: Codable, Identifiable {
    var id: String { trackId }
    let trackId: String
    let trackName: String
    let artistName: String
    let likedAt: Date
    let latitude: Double?   // captured from SharedStore at heart-tap time
    let longitude: Double?

    // Backward-compatible init for callers that don't supply location
    init(trackId: String, trackName: String, artistName: String, likedAt: Date,
         latitude: Double? = nil, longitude: Double? = nil) {
        self.trackId    = trackId
        self.trackName  = trackName
        self.artistName = artistName
        self.likedAt    = likedAt
        self.latitude   = latitude
        self.longitude  = longitude
    }
}

struct StoredLocation: Codable {
    let lat: Double
    let lon: Double
    let timestamp: Date
}

struct TokenCache: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiryDate: Date
}

enum SharedStore {
    static let appGroupID = "group.com.drivelike.app"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: - Tokens

    static func readTokenCache() -> TokenCache? {
        guard let containerURL else {
            print("[SharedStore] readTokenCache: containerURL is nil — App Group not accessible")
            return nil
        }
        let url = containerURL.appendingPathComponent("tokens.json")
        guard let data = try? Data(contentsOf: url) else {
            print("[SharedStore] readTokenCache: tokens.json not found at \(url.path)")
            return nil
        }
        guard let cache = try? JSONDecoder().decode(TokenCache.self, from: data) else {
            print("[SharedStore] readTokenCache: JSON decode failed")
            return nil
        }
        print("[SharedStore] readTokenCache: token expires \(cache.expiryDate)")
        return cache
    }

    static func writeTokenCache(accessToken: String, refreshToken: String?, expiresIn: Int) {
        guard let containerURL else {
            print("[SharedStore] writeTokenCache: containerURL is nil — App Group not accessible")
            return
        }
        let url = containerURL.appendingPathComponent("tokens.json")
        let cache = TokenCache(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiryDate: Date().addingTimeInterval(Double(expiresIn))
        )
        do {
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
            print("[SharedStore] writeTokenCache: wrote token to \(url.path), expires in \(expiresIn)s")
        } catch {
            print("[SharedStore] writeTokenCache: write failed — \(error)")
        }
    }

    static func clearTokenCache() {
        guard let url = containerURL?.appendingPathComponent("tokens.json") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Liked Tracks (full info, written by widget intent)

    static func readLikedTracks() -> [LikedTrack] {
        guard let url = containerURL?.appendingPathComponent("liked_tracks.json"),
              let data = try? Data(contentsOf: url),
              let tracks = try? JSONDecoder().decode([LikedTrack].self, from: data)
        else { return [] }
        return tracks
    }

    static func appendLikedTrack(_ track: LikedTrack) {
        var tracks = readLikedTracks()
        guard !tracks.contains(where: { $0.trackId == track.trackId }) else { return }
        tracks.append(track)
        guard let url = containerURL?.appendingPathComponent("liked_tracks.json"),
              let data = try? JSONEncoder().encode(tracks)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clearLikedTracks() {
        guard let url = containerURL?.appendingPathComponent("liked_tracks.json") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Liked IDs (legacy — kept for polling loop backward compat)

    static func readLikedIds() -> Set<String> {
        guard let url = containerURL?.appendingPathComponent("liked_ids.json"),
              let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    static func addLikedId(_ id: String) {
        var ids = readLikedIds()
        guard !ids.contains(id) else { return }
        ids.insert(id)
        guard let url = containerURL?.appendingPathComponent("liked_ids.json"),
              let data = try? JSONEncoder().encode(Array(ids))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Playlist ID

    static func readPlaylistId() -> String? {
        guard let url = containerURL?.appendingPathComponent("playlist_id.txt"),
              let id = try? String(contentsOf: url, encoding: .utf8),
              id.count > 4  // guard against empty-string sentinel written on re-auth
        else { return nil }
        return id
    }

    static func writePlaylistId(_ id: String) {
        guard let url = containerURL?.appendingPathComponent("playlist_id.txt") else {
            print("[SharedStore] writePlaylistId: containerURL is nil")
            return
        }
        do {
            try id.write(to: url, atomically: true, encoding: .utf8)
            print("[SharedStore] writePlaylistId: saved \(id) to \(url.path)")
        } catch {
            print("[SharedStore] writePlaylistId: write failed — \(error)")
        }
    }

    // MARK: - Granted scopes (for diagnostics)

    static func writeGrantedScopes(_ scopes: String) {
        guard let url = containerURL?.appendingPathComponent("granted_scopes.txt") else { return }
        try? scopes.write(to: url, atomically: true, encoding: .utf8)
    }

    static func readGrantedScopes() -> String? {
        guard let url = containerURL?.appendingPathComponent("granted_scopes.txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Debug log (written by both processes, displayed in main app UI)

    static func appendDebugLog(_ message: String) {
        guard let url = containerURL?.appendingPathComponent("debug_log.txt") else { return }
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = Data("[\(ts)] \(message)\n".utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(line)
            try? fh.close()
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    static func readDebugLog() -> String {
        guard let url = containerURL?.appendingPathComponent("debug_log.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func clearDebugLog() {
        guard let url = containerURL?.appendingPathComponent("debug_log.txt") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Current Location (written by main app every poll, read by widget intent)

    static func writeCurrentLocation(_ loc: StoredLocation) {
        guard let url = containerURL?.appendingPathComponent("current_location.json"),
              let data = try? JSONEncoder().encode(loc)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readCurrentLocation() -> StoredLocation? {
        guard let url = containerURL?.appendingPathComponent("current_location.json"),
              let data = try? Data(contentsOf: url),
              let loc  = try? JSONDecoder().decode(StoredLocation.self, from: data)
        else { return nil }
        return loc
    }

    // MARK: - Track Details Cache (keyed by trackId, persisted indefinitely)

    static func readTrackDetailsCache() -> [String: TrackDetails] {
        guard let url  = containerURL?.appendingPathComponent("track_cache.json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: TrackDetails].self, from: data)
        else { return [:] }
        return dict
    }

    static func writeTrackDetailsCache(_ dict: [String: TrackDetails]) {
        guard let url  = containerURL?.appendingPathComponent("track_cache.json"),
              let data = try? JSONEncoder().encode(dict)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Audio Features Cache (keyed by trackId, persisted indefinitely)

    static func readAudioFeaturesCache() -> [String: AudioFeatures] {
        guard let url  = containerURL?.appendingPathComponent("audio_features_cache.json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: AudioFeatures].self, from: data)
        else { return [:] }
        return dict
    }

    static func writeAudioFeaturesCache(_ dict: [String: AudioFeatures]) {
        guard let url  = containerURL?.appendingPathComponent("audio_features_cache.json"),
              let data = try? JSONEncoder().encode(dict)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Reauth flag

    static var reauthNeeded: Bool {
        get {
            guard let url = containerURL?.appendingPathComponent("reauth_needed") else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    static func setReauthNeeded() {
        guard let url = containerURL?.appendingPathComponent("reauth_needed") else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    static func clearReauthNeeded() {
        guard let url = containerURL?.appendingPathComponent("reauth_needed") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
