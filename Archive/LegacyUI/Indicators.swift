import SwiftUI

/// The M T W T F S S strip on the Today screen.
struct DayStrip: View {
    struct Day: Identifiable {
        let id = UUID()
        let letter: String
        let state: State
        enum State { case done, missed, today, upcoming }
    }

    let days: [Day]
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    Text(day.letter)
                        .font(.dwellCaptionMd)
                        .foregroundStyle(letterColor(day.state))
                    Text(glyph(day.state))
                        .font(.dwellCaption)
                        .foregroundStyle(letterColor(day.state))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(day.state == .today ? t.accent : t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func glyph(_ s: Day.State) -> String {
        switch s {
        case .done: return "✓"
        case .missed: return "–"
        case .today: return "●"
        case .upcoming: return "·"
        }
    }

    private func letterColor(_ s: Day.State) -> Color {
        switch s {
        case .done: return t.success
        case .missed: return t.textTertiary
        case .today: return t.onAccent
        case .upcoming: return t.textTertiary
        }
    }
}

/// Segmented progress used for "The day is closed — 1/2".
struct SegmentedProgress: View {
    let total: Int
    let filled: Int
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < filled ? t.accent : t.surfaceSunken)
                    .frame(height: 3)
            }
        }
    }
}

/// Static voice-note waveform. `seed` keeps each note's shape stable.
struct Waveform: View {
    var seed: Int = 1
    var barCount: Int = 11
    var height: CGFloat = 34
    var playable: Bool = true
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<barCount, id: \.self) { i in
                let h = barHeight(i)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(t.accentSoft)
                    .frame(width: 13, height: h)
            }
        }
        .frame(height: height, alignment: .center)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        // Deterministic pseudo-random so a note looks the same on every render.
        let v = abs(sin(Double((i + 1) * (seed + 3)) * 12.9898) * 43758.5453)
        return height * (0.32 + CGFloat(v.truncatingRemainder(dividingBy: 1)) * 0.68)
    }
}

/// Live recording meter — the tall accent bars on the compose screen.
struct RecordingMeter: View {
    var barCount: Int = 9
    @Environment(\.dwell) private var t
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(t.accent)
                    .frame(width: 5, height: 14 + 44 * amplitude(i))
            }
        }
        .frame(height: 64)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func amplitude(_ i: Int) -> CGFloat {
        let base = abs(sin(Double(i) * 1.7))
        return CGFloat(base) * (0.45 + phase * 0.55)
    }
}

/// Number-over-label stat, as used on the profile screen.
struct Stat: View {
    let value: String
    let label: String
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.dwellTitleSm)
                .foregroundStyle(t.textPrimary)
            Text(label)
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Filled wedge, for the day dial.
struct Pie: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center,
                    radius: rect.width / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * fraction),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Small circular "day progress" dial in the feed header.
struct DayDial: View {
    let fraction: Double
    var size: CGFloat = 20
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            Circle().strokeBorder(t.textSecondary, lineWidth: 1.5)
            Pie(fraction: fraction)
                .fill(t.textSecondary)
                .padding(3)
        }
        .frame(width: size, height: size)
    }
}
