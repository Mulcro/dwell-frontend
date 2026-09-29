import SwiftUI

/// The in-app nudge. MVP delivery for `daily-cron-nudge` is an `ai_insights`
/// row (type `nudge`, `target_user_id` set) rendered here rather than a push,
/// so "the app reaches out to you" is demoable without APNs.
///
/// DESIGN: invented — no Figma source. The Figma's "Late nudge" screen is a
/// lock-screen illustration of the post-hackathon push path, not this.
struct NudgeBanner: View {
    let insight: AIInsight
    var onDismiss: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            CompanionMark(size: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.content)
                    .font(.dwellFootnote)
                    .foregroundStyle(t.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onDismiss) {
                Text("✕")
                    .font(.system(size: 13))
                    .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.md)
        .background(t.accentWash)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(t.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Small "posted after your window" marker (§4.2 `is_late`).
/// DESIGN: invented — no Figma source.
struct LateBadge: View {
    @Environment(\.dwell) private var t

    var body: some View {
        Text("late")
            .font(.dwellLabel)
            .tracking(0.6)
            .foregroundStyle(t.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(t.surfaceSunken)
            .clipShape(Capsule())
    }
}
