import SwiftUI

/// The first thing anyone sees. The static launch screen paints the paper
/// background so there's no white flash; this picks it up and holds the
/// wordmark while `bootstrap()` runs, then hands over.
///
/// DESIGN: invented — no Figma source.
struct SplashView: View {
    @Environment(\.dwell) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markIn = false
    @State private var wordIn = false

    var body: some View {
        ZStack {
            t.background.ignoresSafeArea()

            VStack(spacing: Space.xl) {
                AnchorMark(progress: markIn ? 1 : 0)
                    .frame(width: 76, height: 76)

                Text("Dwell")
                    .font(DwellFont.serif(38))
                    .foregroundStyle(t.textPrimary)
                    .opacity(wordIn ? 1 : 0)
                    .offset(y: wordIn ? 0 : 6)
            }
        }
        .onAppear {
            guard !reduceMotion else { markIn = true; wordIn = true; return }
            withAnimation(.easeOut(duration: 0.75)) { markIn = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { wordIn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dwell")
    }
}

/// The icon's anchor, drawn as a stroke that traces itself in. Proportions
/// match `Tools/make-icon.swift` so the splash and the home screen agree.
struct AnchorMark: View {
    /// 0…1 — how much of the stroke is drawn.
    var progress: CGFloat = 1
    @Environment(\.dwell) private var t

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2
            let line = d * 0.058
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            let eyeR = d * 0.072

            ZStack {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(t.accent, style: stroke)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .rotationEffect(.degrees(-90))
                    .position(x: cx, y: d * 0.155)

                Path { p in
                    p.move(to: CGPoint(x: cx, y: d * 0.225))
                    p.addLine(to: CGPoint(x: cx, y: d * 0.765))
                }
                .trim(from: 0, to: progress)
                .stroke(t.accent, style: stroke)

                Path { p in
                    p.move(to: CGPoint(x: d * 0.30, y: d * 0.305))
                    p.addLine(to: CGPoint(x: d * 0.70, y: d * 0.305))
                }
                .trim(from: 0, to: progress)
                .stroke(t.accent, style: stroke)

                Path { p in
                    p.move(to: CGPoint(x: d * 0.225, y: d * 0.585))
                    p.addCurve(to: CGPoint(x: cx, y: d * 0.825),
                               control1: CGPoint(x: d * 0.225, y: d * 0.765),
                               control2: CGPoint(x: d * 0.355, y: d * 0.825))
                    p.addCurve(to: CGPoint(x: d * 0.775, y: d * 0.585),
                               control1: CGPoint(x: d * 0.645, y: d * 0.825),
                               control2: CGPoint(x: d * 0.775, y: d * 0.765))
                }
                .trim(from: 0, to: progress)
                .stroke(t.accent, style: stroke)
            }
        }
    }
}

#Preview { SplashView().dwellThemed() }
