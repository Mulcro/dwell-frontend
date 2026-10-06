import SwiftUI

/// The bar waveform on the reflection card.
///
/// Live levels while recording; a stable pseudo-random shape once recorded,
/// so a saved note looks the same every time it's drawn.
struct VoiceWaveform: View {
    var levels: [CGFloat] = []
    var seed: Int = 1
    var barCount: Int = 34
    var height: CGFloat = 44
    var tint: Color?
    /// A trace still being recorded: right-aligned, newest sample last. A
    /// saved recording is instead sampled across its whole length.
    var live: Bool = false
    @Environment(\.dwell) private var t

    /// 3pt bars on a 6pt pitch.
    private static let pitch: CGFloat = 6

    /// Draws as many bars as fit, up to `barCount`. A fixed row of bars can't
    /// shrink, so on a narrow card it took the whole width and squeezed the
    /// duration beside it into one character per line.
    var body: some View {
        GeometryReader { geo in
            let count = max(1, min(barCount, Int((geo.size.width + 3) / Self.pitch)))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(tint ?? t.border)
                        .frame(width: 3, height: max(height * value(at: index, of: count), 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: CGFloat(barCount) * Self.pitch - 3)
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: levels.count)
        .accessibilityHidden(true)
    }

    private func value(at index: Int, of count: Int) -> CGFloat {
        // A saved recording with more peaks than bars: each bar takes the
        // loudest peak in its share, so a narrow card still shows the whole
        // recording rather than only its end.
        if !live, levels.count > count {
            let start = index * levels.count / count
            let end = max(start + 1, (index + 1) * levels.count / count)
            return levels[start..<min(end, levels.count)].max() ?? 0.12
        }
        if !levels.isEmpty {
            // Right-align the live trace so the newest sample is at the end.
            let offset = levels.count - count
            let i = index + offset
            return i >= 0 && i < levels.count ? levels[i] : 0.12
        }
        let v = abs(sin(Double((index + 1) * (seed + 7)) * 12.9898) * 43_758.5453)
        return 0.2 + CGFloat(v.truncatingRemainder(dividingBy: 1)) * 0.8
    }
}

/// Play button + waveform + duration, with optional transcript beneath — the
/// card used on both the record and review screens, and in the feed.
struct VoiceNoteCard<Footer: View>: View {
    var levels: [CGFloat] = []
    var seed: Int = 1
    let duration: String
    var isPlaying: Bool = false
    var onPlay: (() -> Void)?
    /// A text reflection has no audio, so it gets no trace. Drawing one is a
    /// picture of a recording that doesn't exist.
    var showsWaveform: Bool = true
    @ViewBuilder var footer: Footer
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if showsWaveform {
            HStack(spacing: Space.lg) {
                if let onPlay {
                    Button(action: onPlay) {
                        ZStack {
                            Circle().fill(t.surfaceRaised)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(t.textPrimary)
                        }
                        .frame(width: 56, height: 56)
                    }
                    .buttonStyle(PressScale())
                }
                VoiceWaveform(levels: levels, seed: seed)
                Spacer(minLength: 0)
            }
            }
            footer
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }
}
