import Foundation
import CryptoKit
import AuthenticationServices

private let kAppGroup   = "group.com.drivelike.app"
private let kClientId   = "b9d717af8d1549f58667611f6f0b2254"
private let kRedirectUri = "drivelike://callback"
private let kScopes     = "user-read-playback-state user-read-currently-playing playlist-modify-private playlist-modify-public"

@MainActor
final class SpotifyAuthManager: NSObject, ObservableObject {
    static let shared = SpotifyAuthManager()

    @Published var isAuthenticated = false
    @Published var spotifyUserId: String?

    let defaults = UserDefaults(suiteName: kAppGroup)!
    private var codeVerifier = ""
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        // Restore cached Spotify user ID so Supabase sync works without a new network call
        spotifyUserId = UserDefaults.standard.string(forKey: "drivelike_spotify_user_id")
        if let expiry = defaults.object(forKey: "spotify_token_expiry") as? Date,
           expiry > Date(),
           let token = defaults.string(forKey: "spotify_access_token") {
            isAuthenticated = true
            let remaining = max(60, Int(expiry.timeIntervalSince(Date())))
            print("🟢 [Auth] App launched — existing token found, expires in \(remaining)s. Seeding SharedStore.")
            SharedStore.writeTokenCache(
                accessToken: token,
                refreshToken: defaults.string(forKey: "spotify_refresh_token"),
                expiresIn: remaining
            )
            let grantedScopes = SharedStore.readGrantedScopes() ?? "(no scope record)"
            let hasPlaylistScope = grantedScopes.contains("playlist-modify-private")
            print("🟢 [Auth] Granted scopes on disk: \(grantedScopes)")
            print(hasPlaylistScope
                ? "✅ [Auth] playlist-modify-private IS present — playlist writes will work"
                : "❌ [Auth] playlist-modify-private MISSING — you must Disconnect and reconnect!")
        } else {
            print("🔴 [Auth] App launched — no valid token found. User needs to connect.")
        }
    }

    // MARK: - Public

    func startAuthentication() {
        codeVerifier = makeVerifier()
        let challenge = makeChallenge(from: codeVerifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id",            value: kClientId),
            .init(name: "response_type",         value: "code"),
            .init(name: "redirect_uri",          value: kRedirectUri),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "scope",                 value: kScopes),
            .init(name: "show_dialog",           value: "true"),
        ]

        let session = ASWebAuthenticationSession(
            url: comps.url!,
            callbackURLScheme: "drivelike"
        ) { [weak self] callbackURL, error in
            guard let self,
                  let url = callbackURL,
                  error == nil,
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                               .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            Task { await self.exchangeCode(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        session.start()
        authSession = session
    }

    func refreshIfNeeded() async {
        guard let expiry = defaults.object(forKey: "spotify_token_expiry") as? Date,
              let token = defaults.string(forKey: "spotify_access_token")
        else {
            print("🔴 [Auth] refreshIfNeeded: no token in UserDefaults")
            return
        }

        let remaining = max(0, Int(expiry.timeIntervalSince(Date())))
        SharedStore.writeTokenCache(
            accessToken: token,
            refreshToken: defaults.string(forKey: "spotify_refresh_token"),
            expiresIn: max(60, remaining)
        )

        // Seed Spotify user ID for Supabase (fetches once, then cached in UserDefaults)
        if spotifyUserId == nil {
            if let cached = UserDefaults.standard.string(forKey: "drivelike_spotify_user_id") {
                spotifyUserId = cached
            } else if let uid = try? await SpotifyAPIManager.shared.getCurrentUserId() {
                spotifyUserId = uid
                UserDefaults.standard.set(uid, forKey: "drivelike_spotify_user_id")
            }
        }

        guard expiry < Date().addingTimeInterval(60),
              let refresh = defaults.string(forKey: "spotify_refresh_token")
        else { return }
        print("🔄 [Auth] Token expiring in \(remaining)s — refreshing now")
        await doRefresh(refresh)
    }

    // MARK: - Private

    private func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeChallenge(from verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func exchangeCode(_ code: String) async {
        await postToken(params: [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": kRedirectUri,
            "client_id":    kClientId,
            "code_verifier": codeVerifier,
        ])
    }

    private func doRefresh(_ token: String) async {
        await postToken(params: [
            "grant_type":    "refresh_token",
            "refresh_token": token,
            "client_id":     kClientId,
        ])
    }

    func logout() {
        defaults.removeObject(forKey: "spotify_access_token")
        defaults.removeObject(forKey: "spotify_refresh_token")
        defaults.removeObject(forKey: "spotify_token_expiry")
        UserDefaults.standard.removeObject(forKey: "drivelike_spotify_user_id")
        SharedStore.clearTokenCache()
        SharedStore.clearReauthNeeded()
        isAuthenticated = false
        spotifyUserId = nil
    }

    private func postToken(params: [String: String]) async {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
            defaults.set(tr.access_token, forKey: "spotify_access_token")
            if let newRefresh = tr.refresh_token {
                defaults.set(newRefresh, forKey: "spotify_refresh_token")
            }
            defaults.set(
                Date().addingTimeInterval(Double(tr.expires_in)),
                forKey: "spotify_token_expiry"
            )
            // Write to shared file so the widget extension can reliably read the token.
            SharedStore.writeTokenCache(
                accessToken: tr.access_token,
                refreshToken: tr.refresh_token,
                expiresIn: tr.expires_in
            )
            SharedStore.clearReauthNeeded()
            if let scope = tr.scope {
                SharedStore.writeGrantedScopes(scope)
            }
            isAuthenticated = true
            let scopes = tr.scope ?? "(none returned)"
            let hasPlaylistScope = scopes.contains("playlist-modify-private")
            SharedStore.clearDebugLog()
            SharedStore.writePlaylistId("") // force a fresh playlist on next poll
            SharedStore.appendDebugLog("=== NEW TOKEN GRANTED ===")
            SharedStore.appendDebugLog("Scopes: \(scopes)")
            SharedStore.appendDebugLog(hasPlaylistScope
                ? "playlist-modify-private: YES ✓"
                : "playlist-modify-private: MISSING ✗ — must Disconnect and reconnect!")
            SharedStore.appendDebugLog(scopes.contains("playlist-modify-public")
                ? "playlist-modify-public: YES ✓"
                : "playlist-modify-public: MISSING ✗")
            print("🎉 [Auth] NEW TOKEN — scopes: \(scopes) | hasPlaylistScope=\(hasPlaylistScope)")
        } catch {
            print("[SpotifyAuth] Token error: \(error)")
        }
    }
}

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    // Called by the system on the main thread; @MainActor class satisfies the requirement.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String?
}
