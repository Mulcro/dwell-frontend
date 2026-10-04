import SwiftUI

/// Figma: "Challenge End · Complete" — the celebration takeover. Confetti
/// falls here, not on Home; Continue leads into the challenge recap.
struct ChallengeCompleteView: View {
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var openRecap: AIInsight?

    private var planDays: Int { session.plan?.dayCount ?? session.days.count }

    private var planArt: URL? {
        guard let path = session.plan?.imagePath else { return nil }
        return session.api.planImageURL(path: path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 500, fadeFrom: 0.5)

            VStack(spacing: 0) {
                header

                Spacer(minLength: Space.lg)

                card

                Spacer(minLength: Space.xxl)
            }
            .padding(.horizontal, Space.gutter)
        }
        .overlay { ConfettiView() }
        .dwellThemed()
        .fullScreenCover(item: $openRecap) { recap in
            RecapView(insight: recap, onClose: { openRecap = nil })
        }
    }

    private var header: some View {
        HStack {
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

    private var card: some View {
        VStack(spacing: Space.lg) {
            PlanCover(title: session.plan?.title ?? "Your plan", imageURL: planArt)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            StatusPill(text: "Day \(planDays) of \(planDays) Complete")

            Text("Congratulations!\nYou finished together.")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)

            MemberAvatarRow(members: session.members.map { member in
                (session.memberProfiles[member.userId]?.name ?? "Member",
                 session.avatarURL(for: member.userId),
                 false)
            })

            PrimaryButton(title: "Continue", accent: true) {
                if let recap = session.endRecap { openRecap = recap }
                else { onClose() }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
    }

    /// "All five of you posted on the last day. 5 of 7 days opened as a
    /// group." — both halves computed, neither generated.
    private var detail: String {
        let total = session.members.count
        let lastDayPosted = session.days.last?.participationCount ?? 0
        let opened = session.days.filter { $0.status != .missed }.count
        let first = lastDayPosted >= total && total > 0
            ? "All \(spelled(total)) of you posted on the last day."
            : "\(lastDayPosted) of \(total) posted on the last day."
        return "\(first) \(opened) of \(planDays) days opened as a group."
    }

    private func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
        return n < words.count ? words[n] : "\(n)"
    }
}
