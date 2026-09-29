import SwiftUI

/// The destination behind Profile's "Group management" row — members, invite
/// link, and the Pause/End controls that the inactivity prompt also reaches.
///
/// DESIGN: invented — no Figma source.
struct GroupManagementView: View {
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var confirming: ChallengeAction?
    @State private var copied = false

    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(title: "Group", onLeading: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Eyebrow("\(session.members.count) of 10")
                        ForEach(session.members, id: \.id) { member in
                            HStack(spacing: Space.md) {
                                Avatar(size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.memberProfiles[member.userId]?.name ?? "Member")
                                        .font(.dwellBody)
                                        .foregroundStyle(t.textPrimary)
                                    Text(joinedLabel(member))
                                        .font(.dwellCaption)
                                        .foregroundStyle(t.textSecondary)
                                }
                                Spacer()
                                if member.userId == group?.createdBy {
                                    Text("created it")
                                        .font(.dwellCaption)
                                        .foregroundStyle(t.textTertiary)
                                }
                            }
                        }
                    }

                    Panel {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Eyebrow("Invite someone")
                            Text(group?.inviteURL ?? "—")
                                .font(.dwellCode)
                                .foregroundStyle(t.textPrimary)
                            Text("They'll start from the day you're on. Nothing is backfilled and nothing counts as missed for them.")
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

                    VStack(alignment: .leading, spacing: Space.md) {
                        Eyebrow("This challenge")
                        actionRow(.pause, "Pause the challenge",
                                  "Everything freezes until someone resumes.")
                        actionRow(.end, "End the challenge",
                                  "Archives it. Everyone keeps what they wrote.")
                    }

                    Text("Archived groups stay readable forever. Nobody can post into them again.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textTertiary)
                        .lineSpacing(3)
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .alert("End this challenge?", isPresented: .constant(confirming == .end)) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button("End it", role: .destructive) {
                Task { try? await session.respondToInactivity(.end); confirming = nil; onBack() }
            }
        } message: {
            Text("Everyone keeps what they wrote, but nobody can post into it again.")
        }
    }

    private func joinedLabel(_ member: GroupMember) -> String {
        member.userId == session.me?.id ? "You" : "Joined \(member.joinedAt.formatted(.dateTime.month().day()))"
    }

    private func actionRow(_ action: ChallengeAction, _ title: String, _ detail: String) -> some View {
        Button {
            if action == .end { confirming = .end }
            else { Task { try? await session.respondToInactivity(action) } }
        } label: {
            Panel {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.dwellBodyMd).foregroundStyle(t.textPrimary)
                        Text(detail)
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Text("›").foregroundStyle(t.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
