import SwiftUI

/// Figma: "YouVersion Sign In - Disclaimers". The OAuth consent sheet that
/// follows it in the file is the system dialog, so it isn't rebuilt here —
/// ASWebAuthenticationSession presents it.
struct YouVersionSignInView: View {
    var onBack: () -> Void = {}
    var onSignedIn: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var working = false
    @State private var error: String?

    private let terms: [(String, String, Bool)] = [
        ("checkmark", "Read your saved plans and highlights", true),
        ("checkmark", "Sync the passages you're on each day", true),
        ("xmark", "Never share your reflections outside your group", false)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.25)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeader(progress: 0.16, onBack: onBack)

                Text("Sign in with YouVersion")
                    .font(.dwellTitle)
                    .lineSpacing(LineSpacing.title)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.lg)

                Text("Your plans, highlights, and reading history come with you. Dwell never posts for you.")
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(t.textSecondary)
                    .padding(.top, Space.md)

                VStack(spacing: 0) {
                    ForEach(Array(terms.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: Space.md) {
                            Image(systemName: item.0)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(item.2 ? t.success : t.textTertiary)
                                .frame(width: 20, height: 20)
                            Text(item.1)
                                .font(.dwellBody)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.lg)

                        if index < terms.count - 1 {
                            Rectangle().fill(t.border).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.top, Space.xl)

                Spacer()

                if let error {
                    Text(error)
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                        .padding(.bottom, Space.sm)
                }

                PrimaryButton(title: "Sign in with YouVersion", loading: working) {
                    Task { await signIn() }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    private func signIn() async {
        working = true
        defer { working = false }
        do {
            _ = try await session.api.signIn(provider: .youversion)
            await session.bootstrap()
            onSignedIn()
        } catch {
            // Expected until the Custom OIDC provider exists — see §2.
            self.error = "YouVersion sign-in isn't live yet. Use email for now."
        }
    }
}
