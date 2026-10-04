import SwiftUI

/// Figma: "Recap · Weekly" and "Challenge End · Challenge Recap" — the same
/// screen with different framing, which matches the backend: one card shape
/// on `weekly_recap`, `end_summary` and `fallback_recap`.
///
/// Sections render only when their data exists. The comps also show "A line
/// that stuck" and the self-reported check-in; neither has data behind it
/// yet, so neither is drawn — the honest screen is the title, what each
/// member brought, the thread the days kept returning to, and the counts.
struct RecapView: View {
    let insight: AIInsight
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var viewerLanguage: String { session.me?.preferredLanguage ?? "en" }
    private var payload: PulsePayload? { insight.payload(in: viewerLanguage) }
    private var isWeekly: Bool { insight.type == .weeklyRecap }
    private var groupName: String { session.group.value??.name ?? "Your group" }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.25)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        Text(title)
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let members = payload?.members, !members.isEmpty {
                            broughtCard(members)
                        }

                        if let headline = payload?.headline, !headline.isEmpty {
                            threadCard(headline)
                        }

                        statRow

                        if let prose = payload?.standfirst ?? emptyToNil(insight.content) {
                            Text(prose)
                                .font(.dwellBody)
                                .foregroundStyle(t.textSecondary)
                                .lineSpacing(LineSpacing.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, TabBarMetrics.clearance)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, Space.gutter)
        }
        .dwellThemed()
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.top, Space.sm)
    }

    /// "Sunday Crew showed up 6 of the 7 days." — or a framing line when the
    /// counts are null (a weekly recap for a week where no day opened).
    private var title: String {
        if let up = payload?.daysShowedUp, let total = payload?.daysTotal {
            return "\(groupName) showed up \(up) of the \(total) days."
        }
        return isWeekly ? "This week in \(groupName)." : "What these days held."
    }

    private func broughtCard(_ members: [PulseMember]) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What each of you brought")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                Text("No scores. Just what showed up in your reflections.")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            }

            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(members) { member in
                    HStack(alignment: .center, spacing: Space.md) {
                        PhotoAvatar(name: session.name(for: member.userId),
                                    url: session.avatarURL(for: member.userId),
                                    size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.name(for: member.userId))
                                .font(.dwellBodyMd)
                                .foregroundStyle(t.textPrimary)
                            Text(member.line)
                                .font(.dwellSmall)
                                .foregroundStyle(t.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
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

    /// The headline finishes this label's sentence — the contract sends the
    /// value starting with the thing itself ("listening, both to…").
    private func threadCard(_ headline: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(isWeekly ? "This week kept coming back to..."
                          : "You kept coming back to...")
                .font(.dwellSmallMd)
                .foregroundStyle(t.textSecondary)
            Text(headline)
                .font(.dwellCardTitle)
                .foregroundStyle(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private var statRow: some View {
        let stats: [(String, String)] = [
            payload?.reflectionCount.map { ("\($0)", $0 == 1 ? "reflection" : "reflections") },
            payload?.members.map { ("\($0.count)", $0.count == 1 ? "voice" : "voices") },
            payload?.daysShowedUp.map { ("\($0)", $0 == 1 ? "day opened" : "days opened") },
        ].compactMap { $0 }

        if !stats.isEmpty {
            HStack(spacing: Space.md) {
                ForEach(stats, id: \.1) { value, label in
                    VStack(spacing: 2) {
                        Text(value)
                            .font(DwellFont.sf(28, .bold))
                            .foregroundStyle(t.accent)
                        Text(label)
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.lg)
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func emptyToNil(_ string: String) -> String? {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }
}
