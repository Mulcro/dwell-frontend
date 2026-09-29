import SwiftUI

/// `challenge_status = forming`. The group exists but Day 1 hasn't fired —
/// it triggers automatically the moment a second member joins (§4.1). This is
/// the creator's first screen and the one state the Figma never covered.
///
/// DESIGN: invented — no Figma source.
struct FormingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var copied = false

    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow(group?.name ?? "Your group")
                        Text("One more person\nand you begin.")
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)
                            .lineSpacing(2)
                        Text("Day 1 opens the moment someone joins you. Nothing starts while you're here alone — that's the point.")
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(5)
                    }

                    roster

                    Panel {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Eyebrow("Magic link")
                            Text(group?.inviteURL ?? "dwell.to/——————")
                                .font(.dwellCode)
                                .foregroundStyle(t.textPrimary)
                            Text("Opens in their browser — they can see the group and join before installing anything.")
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                                .lineSpacing(3)

                            HStack(spacing: Space.sm) {
                                ShareInviteButton(token: group?.inviteToken ?? "",
                                                  groupName: group?.name)
                                DwellButton(title: copied ? "Copied" : "Copy code", kind: .secondary) {
                                    UIPasteboard.general.string = group?.inviteToken
                                    Haptics.tap()
                                    copied = true
                                }
                            }
                        }
                    }

                    Panel {
                        HStack(alignment: .top, spacing: Space.md) {
                            CompanionMark(size: 22)
                            Text("While you wait — the plan's first day is Hebrews 6:19, hope as an anchor. Worth reading before anyone else shows up.")
                                .font(.dwellFootnote)
                                .foregroundStyle(t.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Eyebrow("Who's here")
            ForEach(session.members, id: \.id) { member in
                HStack(spacing: Space.md) {
                    Avatar(size: 34)
                    Text(session.memberProfiles[member.userId]?.name ?? "Member")
                        .font(.dwellBody)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Text(member.userId == session.me?.id ? "you" : "in")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                }
            }

            HStack(spacing: Space.md) {
                ZStack {
                    Circle().strokeBorder(t.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("+").foregroundStyle(t.textTertiary)
                }
                .frame(width: 34, height: 34)
                Text("Waiting for one more")
                    .font(.dwellBody)
                    .foregroundStyle(t.textTertiary)
                Spacer()
            }
        }
    }
}
