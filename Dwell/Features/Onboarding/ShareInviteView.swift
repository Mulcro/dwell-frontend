import SwiftUI

/// Figma: "Share Group Invite" — the last step before the app proper.
struct ShareInviteView: View {
    var onHome: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var group: DwellGroup? { session.group.value ?? nil }

    private var inviteURL: URL {
        URL(string: "https://dwell.com/\(group?.inviteToken ?? "")")
            ?? URL(string: "https://dwell.com")!
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

                ShareLink(item: inviteURL,
                          message: Text("Join \(group?.name ?? "my group") on Dwell, we read together and the day opens when enough of us show up.")) {
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
