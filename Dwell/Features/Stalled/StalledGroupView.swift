import SwiftUI

/// The Continue / Pause / End question, when the group has gone quiet.
///
/// Any member may answer and the answer binds the group — so the copy says so
/// plainly rather than letting someone discover it after the fact.
struct StalledGroupView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var submitting: ChallengeAction?
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    EagleAvatar(size: 56)

                    VStack(alignment: .leading, spacing: Space.lg) {
                        Text(title)
                            .font(.dwellHero)
                            .foregroundStyle(t.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(.dwellBody)
                            .lineSpacing(LineSpacing.body)
                            .foregroundStyle(t.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: Space.md) {
                        option(.continue,
                               title: "Keep Going",
                               detail: dayLabel,
                               filled: true)
                        option(.pause,
                               title: "Pause for now",
                               detail: "No new days. No nudges.",
                               filled: false)
                        option(.end,
                               title: "End the challenge.",
                               detail: endDetail,
                               filled: false)
                    }

                    if let error {
                        Text(error)
                            .font(.dwellSmall)
                            .foregroundStyle(t.danger)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xxl)
                .padding(.bottom, TabBarMetrics.clearance)
            }
            .scrollIndicators(.hidden)
        }
        .dwellThemed()
    }

    // MARK: - Copy

    /// Prefers what the companion actually wrote; the derived line is a
    /// fallback for when generation failed, since the question still has to be
    /// answerable.
    private var title: String {
        let quiet = session.days.last?.consecutiveBelowThresholdCount ?? 0
        guard quiet > 1 else { return "The group's gone quiet." }
        return "Nobody's posted in \(spelled(quiet)) days."
    }

    private var message: String {
        if let written = session.inactivityPrompt?.content, !written.isEmpty { return written }
        return "Life gets loud, but that doesn't mean anyone's done. "
             + "The first person to answer decides for the group."
    }

    private var dayLabel: String {
        guard let index = session.currentDay?.dayIndex else { return "The challenge stays open." }
        return "Day \(index) stays open."
    }

    private var endDetail: String {
        let name = session.plan?.title ?? "the challenge"
        return "Close \(name) for everyone. Every reflection stays in memories."
    }

    private func spelled(_ n: Int) -> String {
        ["zero", "one", "two", "three", "four", "five", "six", "seven"]
            .indices.contains(n) ? ["zero", "one", "two", "three", "four", "five", "six", "seven"][n]
            : "\(n)"
    }

    // MARK: - Options

    private func option(_ action: ChallengeAction,
                        title: String,
                        detail: String,
                        filled: Bool) -> some View {
        AsyncButton {
            await answer(action)
        } label: {
            HStack(alignment: .center, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.dwellCardTitleStrong)
                        .foregroundStyle(filled ? t.onInk : t.textPrimary)
                    Text(detail)
                        .font(.dwellBody)
                        .foregroundStyle(filled ? t.onInk.opacity(0.75) : t.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if submitting == action { ProgressView().tint(filled ? t.onInk : t.textPrimary) }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(filled ? t.ink : t.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(filled ? .clear : t.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
        .disabled(submitting != nil)
    }

    private func answer(_ action: ChallengeAction) async {
        submitting = action
        defer { submitting = nil }
        do {
            try await session.respondToInactivity(action)
            Haptics.posted()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}
