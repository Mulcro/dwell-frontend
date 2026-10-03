import SwiftUI

/// Figma: "Log In Modal" — presented as a sheet over Welcome.
struct LogInView: View {
    var onDone: () -> Void = {}
    var onYouVersion: () -> Void = {}
    var onInviteLink: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dwell) private var t
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    private var canContinue: Bool { email.contains("@") && !password.isEmpty }

    var body: some View {
        // Scrolls so the keyboard slides over the lower buttons instead of
        // compressing the stack and shoving the header off the top.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack {
                    Text("Welcome Back!")
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(t.textPrimary)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Close")
                }
                .padding(.top, Space.xl)

                DwellField(label: "Email", placeholder: "you@email.com",
                           error: error, keyboard: .emailAddress, text: $email)
                DwellField(label: "Password", placeholder: "Password",
                           secure: true, text: $password)

                if let error, !error.isEmpty {
                    Text(error).font(.dwellCaption).foregroundStyle(t.danger)
                }

                PrimaryButton(title: "Continue", enabled: canContinue, loading: working, accent: true) {
                    Task { await submit() }
                }

                HStack(spacing: Space.md) {
                    Rectangle().fill(t.border).frame(height: 1)
                    Text("or").font(.dwellSmall).foregroundStyle(t.textSecondary)
                    Rectangle().fill(t.border).frame(height: 1)
                }

                PrimaryButton(title: "Continue with YouVersion") {
                    Task { await youVersion() }
                }

                SocialButtonRow(onSignedIn: onDone,
                                onError: { message in
                                    guard !message.isEmpty else { return }
                                    error = message
                                })

                SecondaryButton(title: "I have an invite link", action: onInviteLink)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .dwellThemed()
        // Full height: at 680 the keyboard compressed the card and pushed
        // the header off screen.
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func youVersion() async {
        do {
            _ = try await session.api.signIn(provider: .youversion)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onDone()
        } catch is CancellationError {
        } catch {
            Haptics.warning()
            self.error = ProviderButtons.friendly(error)
        }
    }

    private func submit() async {
        error = nil
        working = true
        defer { working = false }
        do {
            _ = try await session.api.signIn(email: email, password: password)
            await session.syncProfileIfNeeded()
            await session.bootstrap()
            Haptics.posted()
            onDone()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}
