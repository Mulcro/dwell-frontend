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
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(tint ?? t.border)
                    .frame(width: 3, height: max(height * value(at: index), 4))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: levels.count)
        .accessibilityHidden(true)
    }

    private func value(at index: Int) -> CGFloat {
        if !levels.isEmpty {
            // Right-align the live trace so the newest sample is at the end.
            let offset = levels.count - barCount
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
    @ViewBuilder var footer: Footer
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
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
