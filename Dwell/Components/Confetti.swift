import SwiftUI

/// The celebration layer on "Challenge End · Complete".
///
/// Deterministic pieces falling once over a few seconds, drawn in a Canvas so
/// sixty-odd shapes don't become sixty-odd views. Non-interactive by nature;
/// place it in an overlay and it never eats a tap.
struct ConfettiView: View {
    var pieceCount: Int = 56
    @Environment(\.dwell) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date = .now

    private struct Piece {
        let x: CGFloat        // 0…1 across the width
        let delay: Double
        let speed: Double     // fraction of height per second
        let drift: CGFloat    // horizontal sway amplitude
        let spin: Double
        let size: CGFloat
        let round: Bool
        let colorIndex: Int
    }

    private var pieces: [Piece] {
        // Seeded, not random: the burst looks the same on every appearance
        // and in every preview.
        (0..<pieceCount).map { i in
            let r = { (k: Int) -> Double in
                abs(sin(Double((i + 1) * (k + 3)) * 12.9898) * 43_758.5453)
                    .truncatingRemainder(dividingBy: 1)
            }
            return Piece(x: r(1),
                         delay: r(2) * 1.6,
                         speed: 0.25 + r(3) * 0.3,
                         drift: 14 + r(4) * 26,
                         spin: (r(5) - 0.5) * 10,
                         size: 6 + r(6) * 6,
                         round: r(7) > 0.5,
                         colorIndex: i % 4)
        }
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startedAt)
                    let colors: [Color] = [t.accent, t.ink,
                                           t.accent.opacity(0.5),
                                           Color(red: 0.98, green: 0.74, blue: 0.3)]
                    for piece in pieces {
                        let life = elapsed - piece.delay
                        guard life > 0 else { continue }
                        let progress = life * piece.speed
                        guard progress < 1.2 else { continue }

                        let y = progress * (size.height + 40) - 20
                        let x = piece.x * size.width
                            + sin(life * 2.2 + Double(piece.colorIndex)) * piece.drift
                        let fade = max(0, min(1, 1.4 - progress))

                        var ctx = context
                        ctx.opacity = fade
                        ctx.translateBy(x: x, y: y)
                        ctx.rotate(by: .radians(life * piece.spin))

                        let rect = CGRect(x: -piece.size / 2,
                                          y: -piece.size / 2,
                                          width: piece.size,
                                          height: piece.round ? piece.size : piece.size * 0.55)
                        let path = piece.round
                            ? Path(ellipseIn: rect)
                            : Path(roundedRect: rect, cornerRadius: 1.5)
                        ctx.fill(path, with: .color(colors[piece.colorIndex]))
                    }
                }
            }
            .allowsHitTesting(false)
            .onAppear { startedAt = .now }
        }
    }
}
