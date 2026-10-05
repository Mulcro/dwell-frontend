import SwiftUI

/// A crew-mate's "same crew, new plan" invitation (KAN-50): who started it,
/// the plan, and one tap to join. Shown on a finished group's Home and on
/// What's Next.
struct ContinuationCard: View {
    let invite: Continuation
    /// Called after a successful join; the session has already reloaded onto
    /// the new group.
    var onJoined: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var joining = false
    @State private var message: String?

    private var starter: String {
        invite.createdByName?.split(separator: " ").first.map(String.init) ?? "Someone in your group"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("\(starter) started a new plan with this crew")
                .font(.dwellBodyMd)
                .foregroundStyle(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.md) {
                PlanCoverThumb(title: invite.planTitle,
                               imageURL: invite.planImagePath.flatMap { session.api.planImageURL(path: $0) },
                               size: 56,
                               corner: Radius.md)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.planTitle)
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(invite.dayCount) days · \(invite.memberCount) joined")
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if let message {
                Text(message)
                    .font(.dwellSmall)
                    .foregroundStyle(t.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.md) {
                PrimaryButton(title: joining ? "Joining…" : "Join",
                              enabled: !joining, loading: joining, accent: true, compact: true) {
                    Task { await join() }
                }
                SecondaryButton(title: "Not this time", bordered: true, compact: true) {
                    withAnimation { session.dismissContinuation(invite) }
                }
                .disabled(joining)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func join() async {
        joining = true
        message = nil
        defer { joining = false }
        do {
            try await session.acceptContinuation(invite)
            onJoined()
        } catch {
            // The 409s ("still going", "full", "already ended") are written
            // for the screen.
            Haptics.warning()
            message = error.localizedDescription
        }
    }
}
