import SwiftUI

/// The three icon-only provider buttons under "Continue with YouVersion".
///
/// Only **Google** is configured on the project. Apple needs a paid developer
/// membership and Facebook isn't set up at all — both are drawn as designed
/// but say so on tap rather than failing silently.
struct SocialButtonRow: View {
    var onSignedIn: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var working: AuthProvider?

    var body: some View {
        HStack(spacing: Space.md) {
            button(.apple) { AppleMark() }
            button(.google) { GoogleMark() }
            button(.facebook) { FacebookMark() }
        }
    }

    private func button<Mark: View>(_ provider: AuthProvider,
                                    @ViewBuilder mark: () -> Mark) -> some View {
        Button {
            Task { await tap(provider) }
        } label: {
            Group {
                if working == provider {
                    ProgressView().tint(t.textPrimary)
                } else {
                    mark()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.borderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Continue with \(provider.rawValue.capitalized)")
    }

    private func tap(_ provider: AuthProvider) async {
        guard provider == .google else {
            Haptics.warning()
            onError(provider == .apple
                    ? "Sign in with Apple isn't set up yet. Use YouVersion or Google."
                    : "Facebook sign-in isn't set up yet. Use YouVersion or Google.")
            return
        }
        working = provider
        defer { working = nil }
        do {
            _ = try await session.api.signIn(provider: provider)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onSignedIn()
        } catch is CancellationError {
            // Sheet dismissed — not a failure.
        } catch {
            Haptics.warning()
            onError(ProviderButtons.friendly(error))
        }
    }
}

// MARK: - Marks
//
// Drawn rather than bundled: the comp uses monochrome glyphs, and shipping
// real brand assets means honouring each brand's usage rules.

private struct AppleMark: View {
    @Environment(\.dwell) private var t
    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 22))
            .foregroundStyle(t.textPrimary)
    }
}

private struct GoogleMark: View {
    @Environment(\.dwell) private var t
    var body: some View {
        Text("G")
            .font(.system(size: 24, weight: .medium, design: .rounded))
            .foregroundStyle(t.textPrimary)
    }
}

private struct FacebookMark: View {
    @Environment(\.dwell) private var t
    var body: some View {
        Text("f")
            .font(.system(size: 26, weight: .bold, design: .serif))
            .foregroundStyle(t.textPrimary)
    }
}
