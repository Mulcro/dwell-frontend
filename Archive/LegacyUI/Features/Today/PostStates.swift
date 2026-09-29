import SwiftUI

/// `moderation_status = pending`. The reflection is in, but the moderation
/// pass hasn't returned — so it does not yet count toward the threshold
/// (§4.2: the gate fires on approval, not insert).
///
/// DESIGN: invented — no Figma source.
struct ReflectionPendingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header

            Panel {
                HStack(alignment: .top, spacing: Space.md) {
                    ProgressView().tint(t.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Just checking it over")
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                        Text("Every reflection gets a quick safety pass before the group sees it. This usually takes a moment.")
                            .font(.dwellFootnote)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(4)
                    }
                }
            }

            if let mine = session.myReflection {
                Panel {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("What you wrote")
                        Text(mine.displayBody)
                            .font(.dwellBody)
                            .foregroundStyle(t.textPrimary)
                            .lineSpacing(5)
                    }
                }
            }

            Text("It'll count toward today the moment it clears.")
                .font(.dwellCaption)
                .foregroundStyle(t.textTertiary)

            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .task {
            // The real app gets this via the day_instances realtime channel.
            try? await Task.sleep(for: .seconds(2))
            await session.reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(session.group.value??.name ?? "Your group")
            Text("Day \(session.currentDay?.dayIndex ?? 1)")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
        }
    }
}

/// `moderation_status = flagged`. The post stays hidden and never counts
/// toward the threshold. Written to be honest without being punitive.
///
/// DESIGN: invented — no Figma source.
struct ReflectionFlaggedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Eyebrow("Day \(session.currentDay?.dayIndex ?? 1)")
                Text("This one didn't go through")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                Text("Our safety check held it back, so it hasn't been shared and doesn't count toward today. That check isn't always right — if this looks wrong, it probably is.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .lineSpacing(5)
            }

            if let mine = session.myReflection {
                Panel {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("What you wrote")
                        Text(mine.displayBody)
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(5)
                    }
                }
            }

            VStack(spacing: Space.sm) {
                DwellButton(title: "Write it again")
                DwellButton(title: "Ask us to take another look", kind: .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }
}

/// Posted and approved, group still short of the threshold. The three Figma
/// treatments are one state with different emphasis; this keeps the sealed
/// framing, which is the strongest of the three.
struct WaitingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var needed: Int { session.requiredToUnlock }
    private var posted: Int { session.postedCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack {
                    Text("Day \(session.currentDay?.dayIndex ?? 1)")
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    HStack(spacing: Space.sm) {
                        if session.myReflection?.isLate == true { LateBadge() }
                        Text("You're in ✓")
                            .font(.dwellFootnoteMd)
                            .foregroundStyle(t.success)
                    }
                }

                ZStack(alignment: .topTrailing) {
                    ImagePlaceholder("sealed — \(posted) reflection\(posted == 1 ? "" : "s") inside")
                    Text("\(posted)/\(max(needed, 1))")
                        .font(.dwellCaptionMd)
                        .foregroundStyle(t.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(t.background.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(Space.md)
                }
                .frame(height: 200)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Sealed until the\ngroup's here")
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                    Text(bodyLine)
                        .font(.dwellBody)
                        .foregroundStyle(t.textSecondary)
                        .lineSpacing(5)
                }

                // Names deliberately withheld — the content-free count comes
                // off day_instances.participation_count, never a reflections
                // subscription (§1.4).
                VStack(spacing: Space.sm) {
                    ForEach(0..<max(posted, 1), id: \.self) { _ in
                        HStack(spacing: Space.md) {
                            Avatar(size: 30)
                            Text("·····")
                                .font(.dwellBody)
                                .foregroundStyle(t.textTertiary)
                            Spacer()
                        }
                        .padding(Space.md)
                        .background(t.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }

                VStack(spacing: Space.sm) {
                    DwellButton(title: "Nudge the group — kindly", kind: .secondary)
                    Text("Late posts still open it — just for them.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textTertiary)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var bodyLine: String {
        let remaining = max(needed - posted, 1)
        return "\(posted) reflection\(posted == 1 ? " is" : "s are") inside, yours among them. It breaks open at \(needed) — \(remaining) more to go. No names, no ranking."
    }
}
