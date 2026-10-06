import SwiftUI

/// The third-party sign-in options, shared by Sign Up and Log In so the two
/// can't drift apart.
///
/// YouVersion is the primary sign-in, as the design intends. Google and
/// email/password are also live. Apple is not configured — it needs a paid
/// Apple Developer membership — so it isn't offered at all rather than shown
/// as a button that can't work.
struct ProviderButtons: View {
    var onSignedIn: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var working: AuthProvider?

    var body: some View {
        VStack(spacing: Space.sm) {
            PrimaryButton(title: working == .youversion ? "Opening YouVersion…" : "Continue with YouVersion",
                          loading: working == .youversion,
                          image: "YouVersionLogo") {
                Task { await signIn(.youversion) }
            }

            SecondaryButton(title: working == .google ? "Opening Google…" : "Continue with Google",
                            bordered: true,
                            image: "GoogleLogo") {
                Task { await signIn(.google) }
            }
        }
    }

    private func signIn(_ provider: AuthProvider) async {
        working = provider
        defer { working = nil }
        do {
            _ = try await session.api.signIn(provider: provider)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onSignedIn()
        } catch is CancellationError {
            // User dismissed the browser sheet — not a failure worth shouting about.
        } catch {
            Haptics.warning()
            onError(Self.friendly(error))
        }
    }

    /// OAuth misconfiguration surfaces as opaque text. Say something useful
    /// instead of showing the raw error during a demo.
    static func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("redirect_uri_mismatch") || raw.contains("invalid_client") {
            return "That sign-in isn't configured correctly yet. Try another way for now."
        }
        // The bridge's 422 — genuine token, no email claim. Already actionable.
        if raw.contains("email address") { return error.localizedDescription }
        if raw.contains("cancel") {
            return ""
        }
        if let dwell = error as? DwellError, case .notImplemented = dwell {
            return "That sign-in option isn't available yet."
        }
        return "Couldn't sign you in. Try again, or use your email."
    }
}
