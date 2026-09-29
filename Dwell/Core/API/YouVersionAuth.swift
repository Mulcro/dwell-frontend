import Foundation
import CryptoKit
import AuthenticationServices

/// YouVersion sign-in.
///
/// Not a Supabase OAuth provider — YouVersion is a PKCE public client with no
/// client secret, which Supabase's own provider flow can't complete. So the
/// app drives their flow and hands the resulting `id_token` to a bridge
/// function, which returns a magic-link hash we redeem for a normal session.
///
/// Four steps, per the Client API Contract:
///   1. authorize in ASWebAuthenticationSession → `dwell://auth-callback?code=`
///   2. exchange the code for an `id_token` (PKCE, no secret)
///   3. POST the token to `/functions/v1/youversion-signin`
///   4. redeem the returned `token_hash` via `verifyOTP`
@MainActor
final class YouVersionAuth: NSObject {

    struct BridgeResponse: Decodable {
        let email: String
        let tokenHash: String
        let isNewUser: Bool

        enum CodingKeys: String, CodingKey {
            case email
            case tokenHash = "token_hash"
            case isNewUser = "is_new_user"
        }
    }

    /// Registered with YouVersion. Their side rejects custom schemes, so the
    /// callback goes to a Supabase relay which then bounces to `dwell://`.
    private let relayURL: String
    private let appKey: String
    private let authorizeURL = URL(string: "https://api.youversion.com/auth/authorize")!
    private let tokenURL = URL(string: "https://api.youversion.com/auth/token")!

    private var session: ASWebAuthenticationSession?
    /// Captured on the main actor before the session starts. Resolving the
    /// window inside `presentationAnchor` would mean asserting main-actor
    /// isolation from a nonisolated callback, which traps if AuthenticationServices
    /// ever calls it off the main thread.
    private var anchor: ASPresentationAnchor?

    init(supabaseURL: URL, appKey: String) {
        self.relayURL = supabaseURL.appendingPathComponent("functions/v1/yv-callback").absoluteString
        self.appKey = appKey
    }

    /// Runs steps 1–3 and returns what the bridge gave back.
    func authenticate(supabaseURL: URL, publishableKey: String) async throws -> BridgeResponse {
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let nonce = Self.randomURLSafeString(length: 32)
        let state = Self.randomURLSafeString(length: 32)

        let code = try await authorize(challenge: challenge, nonce: nonce, state: state)
        let idToken = try await exchange(code: code, verifier: verifier)
        return try await bridge(idToken: idToken, nonce: nonce,
                                supabaseURL: supabaseURL, publishableKey: publishableKey)
    }

    // MARK: - 1. Authorize

    private func authorize(challenge: String, nonce: String, state: String) async throws -> String {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: appKey),
            .init(name: "redirect_uri", value: relayURL),
            .init(name: "scope", value: "openid profile email"),
            .init(name: "nonce", value: nonce),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "require_user_interaction", value: "true")
        ]

        anchor = Self.currentWindow()

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "dwell"
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? DwellError.network("Sign-in was interrupted."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let failure = items.first(where: { $0.name == "error" })?.value {
            throw DwellError.network("YouVersion declined: \(failure)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw DwellError.network("YouVersion didn't return a sign-in code.")
        }
        return code
    }

    // MARK: - 2. Exchange (PKCE, no client secret)

    private func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: relayURL),
            .init(name: "client_id", value: appKey),
            .init(name: "code_verifier", value: verifier)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DwellError.network(DwellError.message(from: data)
                ?? "YouVersion wouldn't exchange the sign-in code.")
        }

        struct TokenResponse: Decodable { let id_token: String }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw DwellError.network("YouVersion's response didn't include an identity token.")
        }
        return token.id_token
    }

    // MARK: - 3. Bridge

    private func bridge(idToken: String, nonce: String,
                        supabaseURL: URL, publishableKey: String) async throws -> BridgeResponse {
        var request = URLRequest(url: supabaseURL.appendingPathComponent("functions/v1/youversion-signin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["id_token": idToken, "nonce": nonce])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200..<300:
            return try JSONDecoder().decode(BridgeResponse.self, from: data)
        case 401:
            throw DwellError.network("We couldn't verify that YouVersion sign-in. Try again.")
        case 422:
            // Genuine token, no email claim — actionable, so say what to do.
            throw DwellError.network("Your YouVersion account didn't share an email address. Allow email access and try again.")
        case 502:
            throw DwellError.aiUnavailable
        default:
            throw DwellError.fromStatus(status, message: DwellError.message(from: data))
        }
    }

    // MARK: - PKCE

    static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }
}

extension YouVersionAuth {
    @MainActor
    static func currentWindow() -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
    }
}

extension YouVersionAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Read the value captured before the session started — no isolation
        // assumption, so this is safe on whatever thread it arrives on.
        MainActor.assumeIsolated { anchor } ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// base64url, unpadded — what PKCE expects.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
