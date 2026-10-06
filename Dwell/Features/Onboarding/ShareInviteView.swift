import SwiftUI

/// Figma: "Share Group Invite" — the last step before the app proper.
struct ShareInviteView: View {
    var onHome: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var group: DwellGroup? { session.group.value ?? nil }

    /// The code as plain text, not a link: there's no tested invite link
    /// yet, and the dwell.com domain isn't ours.
    private var inviteMessage: String {
        let name = group?.name ?? "my group"
        guard let code = group?.inviteToken else { return "Join \(name) on Dwell." }
        return "Join \(name) on Dwell with the code \(code). We read together, and each day unlocks once half of us have posted."
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 420, fadeFrom: 0.4)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Invite your friends to join")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)

                Text(group?.name ?? "your group")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.xs)

                planCard.padding(.top, Space.xl)

                Spacer()

                ShareLink(item: inviteMessage) {
                    Text("Share Invite")
                        .font(.dwellButton)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .foregroundStyle(t.onInk)
                        .background(t.ink)
                        .clipShape(Capsule())
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })

                SecondaryButton(title: "Take me home", action: onHome)
                    .padding(.top, Space.xs)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    private var planCard: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(session.plan?.dayCount ?? 7) Days")
                    .font(.dwellCaptionMd)
                    .foregroundStyle(t.textSecondary)
                Text(session.plan?.title ?? "Your plan")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
            }
            Spacer()
            if let code = group?.inviteToken {
                Text(code)
                    .font(.dwellCode)
                    .foregroundStyle(t.textPrimary)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(t.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }
}
