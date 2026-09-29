import SwiftUI

struct AuthFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var step: Step = .welcome
    @State private var inviteToken: String?

    enum Step: Equatable { case welcome, signIn, invitePreview(String) }

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(
                onContinue: { step = .signIn },
                onInvite: { step = .invitePreview(Seed.groupId.uuidString.isEmpty ? "" : "4K9QRT") })

        case .signIn:
            SignInView(onBack: { step = .welcome })

        case .invitePreview(let token):
            InviteLandingView(inviteToken: token, onBack: { step = .welcome })
        }
    }
}

/// MVP auth: Apple / Google. YouVersion is shown but disabled — it's the
/// documented fast-follow (Backend Design Doc §2, decided 9/20), and the
/// design's YouVersion-first button would promise something that isn't live.
struct SignInView: View {
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var working: AuthProvider?
    @State private var error: String?

    private let terms: [(String, String)] = [
        ("✓", "Your reflections stay inside your group"),
        ("✓", "We never post anywhere on your behalf"),
        ("✕", "No public profile, no follower count")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(onLeading: onBack)

            Text("Sign in to Dwell")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .padding(.top, Space.sm)

            Text("One account, one group at a time. Your group is the only place your reflections go.")
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(4)
                .padding(.top, Space.md)

            VStack(spacing: 0) {
                ForEach(Array(terms.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Space.md) {
                        Text(item.0)
                            .font(.dwellFootnoteMd)
                            .foregroundStyle(item.0 == "✓" ? t.success : t.textTertiary)
                            .frame(width: 16)
                        Text(item.1)
                            .font(.dwellBody)
                            .foregroundStyle(t.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Space.md)
                    if index < terms.count - 1 {
                        Rectangle().fill(t.border).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .padding(.top, Space.xl)

            Spacer()

            if let error {
                Text(error)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
                    .padding(.bottom, Space.sm)
            }

            VStack(spacing: Space.sm) {
                ForEach(AuthProvider.allCases) { provider in
                    providerButton(provider)
                }
            }

            Text("YouVersion sign-in is coming — your plans and highlights will come with you.")
                .font(.dwellCaption)
                .foregroundStyle(t.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.md)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
    }

    @ViewBuilder
    private func providerButton(_ provider: AuthProvider) -> some View {
        let available = provider.isAvailableInMVP
        Button {
            guard available else { return }
            Task { await signIn(provider) }
        } label: {
            HStack(spacing: Space.sm) {
                if working == provider { ProgressView().tint(t.onAccent) }
                Text(provider.label)
                if !available {
                    Text("soon")
                        .font(.dwellLabel)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(t.surfaceSunken)
                        .clipShape(Capsule())
                }
            }
            .font(.dwellButton)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(available ? (provider == .apple ? t.onAccent : t.textPrimary) : t.textTertiary)
            .background(provider == .apple && available ? t.accent : t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .strokeBorder(provider == .apple && available ? .clear : t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!available || working != nil)
    }

    private func signIn(_ provider: AuthProvider) async {
        working = provider
        defer { working = nil }
        do {
            _ = try await session.api.signIn(provider: provider)
            await session.bootstrap()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview { SignInView().dwellThemed() }
