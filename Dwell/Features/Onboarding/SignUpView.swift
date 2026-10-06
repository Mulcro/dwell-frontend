import SwiftUI

/// Figma: "Sign Up". Email + password, or straight through with YouVersion.
///
/// NOTE: email/password is not in the Client API Contract — that document only
/// covers OAuth. Supabase supports it natively, but the backend needs to
/// confirm it's enabled. `AuthProvider.email` is wired to the same code path
/// either way.
struct SignUpView: View {
    var onBack: () -> Void = {}
    var onContinue: () -> Void = {}
    var onYouVersion: () -> Void = {}
    var onSignedIn: () -> Void = {}
    var onInviteLink: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var working = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && email.contains("@") && password.count >= 8
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.2)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingBackBar(onBack: onBack)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        Text("Sign up")
                            .font(.dwellTitle)
                            .lineSpacing(LineSpacing.title)
                            .foregroundStyle(t.textPrimary)

                        // Email sign-up has no provider to take a name from,
                        // so without this the auth trigger falls back to the
                        // literal "Friend" — which is then what group-mates
                        // see on every reflection.
                        DwellField(label: "Name",
                                   placeholder: "What should we call you?",
                                   text: $name)

                        DwellField(label: "Email",
                                   placeholder: "you@email.com",
                                   error: emailError,
                                   keyboard: .emailAddress,
                                   text: $email)

                        DwellField(label: "Password",
                                   placeholder: "Password",
                                   error: passwordError,
                                   secure: true,
                                   text: $password)

                        PrimaryButton(title: "Continue",
                                      enabled: canContinue,
                                      loading: working,
                                      accent: true) {
                            Task { await submit() }
                        }

                        HStack(spacing: Space.md) {
                            line; Text("or").font(.dwellSmall).foregroundStyle(t.textSecondary); line
                        }

                        PrimaryButton(title: "Continue with YouVersion", image: "YouVersionLogo") {
                            Task { await youVersion() }
                        }

                        SocialButtonRow(onSignedIn: onContinue,
                                        onError: { message in
                                            guard !message.isEmpty else { return }
                                            emailError = message
                                        })

                        SecondaryButton(title: "I have an invite link", action: onInviteLink)
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, Space.gutter)
        }
        .dwellThemed()
    }

    private var line: some View {
        Rectangle().fill(t.border).frame(height: 1)
    }

    private func submit() async {
        emailError = nil; passwordError = nil
        guard canContinue else {
            if !email.contains("@") { emailError = "That doesn't look like an email address." }
            if password.count < 8 { passwordError = "Use at least 8 characters." }
            return
        }
        working = true
        defer { working = false }
        do {
            _ = try await session.api.signUp(email: email, password: password, name: trimmedName)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onContinue()
        } catch {
            Haptics.warning()
            emailError = Self.friendlySignUp(error)
        }
    }

    /// With `mailer_autoconfirm` off and no SMTP configured, `signUp` succeeds
    /// but no session is created — so the very next call fails on a missing
    /// session. Name that plainly instead of showing the raw error.
    private func youVersion() async {
        do {
            _ = try await session.api.signIn(provider: .youversion)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onContinue()
        } catch is CancellationError {
            // Dismissed the sheet.
        } catch {
            Haptics.warning()
            emailError = ProviderButtons.friendly(error)
        }
    }

    private static func friendlySignUp(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("session") || raw.contains("not authenticated") {
            return "Account created, but sign-in needs email confirmation, which isn't switched on yet. Use Google for now."
        }
        if raw.contains("already registered") || raw.contains("already been registered") {
            return "That email already has an account. Log in instead."
        }
        if raw.contains("password") {
            return "That password was rejected. Try a longer one."
        }
        return "Couldn't create your account. Try again, or use Google."
    }
}

#Preview { SignUpView() }
