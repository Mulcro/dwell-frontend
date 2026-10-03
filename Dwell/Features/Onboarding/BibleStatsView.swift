import SwiftUI

/// Figma: "Bible Engagement Stats" — the DAU-4 research, in-product.
/// This is the pitch's central claim, so it gets a real chart rather than a
/// screenshot.
struct BibleStatsView: View {
    /// nil hides the arrow — a signed-in user has no sign-up form to return
    /// to, and this is then the first screen of their walk.
    var onBack: (() -> Void)?
    var onContinue: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.15)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeader(progress: 0.3, onBack: onBack)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        Text("Every day in the Bible counts. 4 days a week is where change happens.")
                            .font(.dwellTitle)
                            .lineSpacing(LineSpacing.title)
                            .foregroundStyle(t.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("50%")
                                .font(DwellFont.sf(48, .bold))
                                .foregroundStyle(t.accent)
                            Text("lower odds of harmful habits for people in the Bible 4+ days a week")
                                .font(.dwellBody)
                                .lineSpacing(LineSpacing.body)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        EngagementChart()

                        HStack(alignment: .top, spacing: Space.md) {
                            CBEMark()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Center for Bible Engagement")
                                    .font(.dwellSmall)
                                    .foregroundStyle(t.textSecondary)
                                Text("**40,000 people surveyed**, ages 8-80.")
                                    .font(.dwellSmall)
                                    .foregroundStyle(t.textSecondary)
                            }
                        }
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)

                PrimaryButton(title: "Continue", action: onContinue)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }
}

/// Days-in-scripture vs life change.
///
/// One series, so no legend — the surrounding copy names it. The split at 4 is
/// an emphasis encoding, not a categorical one, so it carries redundant
/// non-colour cues: the "4" tick is bold and the dashed annotation labels the
/// threshold directly.
private struct EngagementChart: View {
    @Environment(\.dwell) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    /// Relative life-change index per day-count. Shape follows the CBE finding:
    /// little movement below 4, a step change at 4, then steady gains.
    private let values: [Double] = [0.06, 0.07, 0.13, 0.62, 0.70, 0.76, 0.84]
    private let threshold = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .bottom, spacing: Space.sm) {
                Text("Life change")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 90)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        bars
                        annotation
                    }
                    .frame(height: 190)

                    Rectangle().fill(t.textPrimary).frame(height: 1.5)
                    ticks
                }
            }

            Text("Days in Scripture per week")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { grown = true; return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.85).delay(0.15)) {
                grown = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chart: life change by days in Scripture per week")
        .accessibilityValue("Little change at one to three days. A sharp rise at four days, continuing to seven.")
    }

    private var bars: some View {
        // 2px of surface between adjacent fills keeps the bars legible.
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let emphasised = index + 1 >= threshold
                UnevenRoundedRectangle(
                    topLeadingRadius: Radius.xs,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Radius.xs,
                    style: .continuous)
                    .fill(emphasised ? t.textPrimary : t.ink.opacity(0.10))
                    .frame(height: max((grown ? value : 0.02) * 190, 6))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var annotation: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Path { path in
                path.move(to: CGPoint(x: w * 0.45, y: geo.size.height * 0.30))
                path.addLine(to: CGPoint(x: w * 0.99, y: geo.size.height * 0.10))
            }
            .stroke(t.textSecondary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
            .opacity(grown ? 1 : 0)

            Text("4+ days: real change")
                .font(.dwellCaptionMd)
                .foregroundStyle(t.textSecondary)
                .rotationEffect(.degrees(-6))
                .position(x: w * 0.72, y: geo.size.height * 0.10)
                .opacity(grown ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.4).delay(0.5), value: grown)
        .accessibilityHidden(true)
    }

    private var ticks: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                Text("\(day)")
                    .font(day == threshold ? .dwellCaptionMd : .dwellCaption)
                    .foregroundStyle(day >= threshold ? t.textPrimary : t.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Small stand-in for the CBE logo until the asset is exported.
private struct CBEMark: View {
    @Environment(\.dwell) private var t
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(t.surfaceRaised)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(t.textSecondary)
            )
            .accessibilityHidden(true)
    }
}

#Preview { BibleStatsView() }
