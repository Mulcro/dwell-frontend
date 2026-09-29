import SwiftUI

/// Recap-style, weekly cadence — deliberately not a live leaderboard
/// (MVP Spec §7).
struct WeekRecapView: View {
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var entries: Loadable<[LeaderboardEntry]> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(title: "Week 1 · recap", onLeading: onBack)

            LoadableView(state: entries, retry: { Task { await load() } }) { list in
                if list.isEmpty {
                    EmptyStateView(
                        title: "Your first recap lands Monday",
                        message: "We gather the week once, at the end — no live standings.")
                } else {
                    content(list)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .task { await load() }
    }

    private func content(_ list: [LeaderboardEntry]) -> some View {
        let mine = list.first { $0.userId == session.me?.id }
        let sorted = list.sorted { $0.participationScore > $1.participationScore }
        let maxScore = sorted.first?.participationScore ?? 7

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("You showed up \(mine?.participationScore ?? 0) of 7 days")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)

                VStack(alignment: .leading, spacing: Space.md) {
                    Eyebrow("The group, this week")
                    VStack(spacing: Space.sm) {
                        ForEach(sorted) { entry in
                            HStack(spacing: Space.md) {
                                Avatar(size: 28)
                                Text(session.name(for: entry.userId))
                                    .font(.dwellBody)
                                    .foregroundStyle(t.textPrimary)
                                Spacer()
                                Capsule()
                                    .fill(t.accentSoft)
                                    .frame(width: max(CGFloat(entry.participationScore) / CGFloat(max(maxScore, 1)) * 110, 8),
                                           height: 6)
                                Text("\(entry.participationScore)")
                                    .font(.dwellFootnoteMd)
                                    .foregroundStyle(t.textSecondary)
                                    .frame(width: 16, alignment: .trailing)
                            }
                        }
                    }
                    Text("Shown once a week — not a live leaderboard, no rank numbers.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textTertiary)
                        .lineSpacing(3)
                }

                HStack(spacing: Space.md) {
                    Stat(value: "\(list.reduce(0) { $0 + $1.participationScore })", label: "reflections")
                    Stat(value: "\(Set(session.memberProfiles.values.map(\.preferredLanguage)).count)", label: "languages")
                    Stat(value: "\(session.currentDay?.dayIndex ?? 0)/7", label: "days opened")
                }
            }
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard let g = session.group.value ?? nil else { return }
        entries = .loading
        do { entries = .loaded(try await session.api.leaderboard(groupId: g.id, weekStart: nil)) }
        catch { entries = .failed(error.localizedDescription) }
    }
}
