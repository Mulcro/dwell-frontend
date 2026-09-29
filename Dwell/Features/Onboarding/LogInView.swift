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
        VStack(alignment: .leading, spacing: Space.xl) {
            Capsule()
                .fill(t.borderStrong)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.md)

            Text("Welcome Back!")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)

            DwellField(label: "Email", placeholder: "you@email.com",
                       error: error, keyboard: .emailAddress, text: $email)
            DwellField(label: "Password", placeholder: "Password",
                       secure: true, text: $password)

            if let error, !error.isEmpty {
                Text(error).font(.dwellCaption).foregroundStyle(t.danger)
            }

            PrimaryButton(title: "Continue", enabled: canContinue, loading: working) {
                Task { await submit() }
            }

            HStack(spacing: Space.md) {
                Rectangle().fill(t.border).frame(height: 1)
                Text("or").font(.dwellSmall).foregroundStyle(t.textSecondary)
                Rectangle().fill(t.border).frame(height: 1)
            }

            ProviderButtons(onSignedIn: onDone,
                            onError: { message in
                                guard !message.isEmpty else { return }
                                error = message
                            })

            SecondaryButton(title: "I have an invite link", action: onInviteLink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .presentationDetents([.height(620)])
        .presentationDragIndicator(.hidden)
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
