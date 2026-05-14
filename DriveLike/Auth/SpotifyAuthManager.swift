import Foundation
import CryptoKit
import AuthenticationServices

private let kAppGroup   = "group.com.drivelike.app"
private let kClientId   = "b9d717af8d1549f58667611f6f0b2254"
private let kRedirectUri = "drivelike://callback"
private let kScopes     = "user-read-playback-state user-library-modify user-read-currently-playing"

@MainActor
final class SpotifyAuthManager: NSObject, ObservableObject {
    static let shared = SpotifyAuthManager()

    @Published var isAuthenticated = false

    let defaults = UserDefaults(suiteName: kAppGroup)!
    private var codeVerifier = ""
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        if let expiry = defaults.object(forKey: "spotify_token_expiry") as? Date,
           expiry > Date(),
           defaults.string(forKey: "spotify_access_token") != nil {
            isAuthenticated = true
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
        session.prefersEphemeralWebBrowserSession = false
        session.start()
        authSession = session
    }

    func refreshIfNeeded() async {
        guard let expiry = defaults.object(forKey: "spotify_token_expiry") as? Date,
              expiry < Date().addingTimeInterval(60),
              let refresh = defaults.string(forKey: "spotify_refresh_token")
        else { return }
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
            isAuthenticated = true
        } catch {
            print("[SpotifyAuth] Token error: \(error)")
        }
    }
}

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}
