import SwiftUI

/// The diagonal-stripe fill the Figma file uses wherever real imagery will go.
struct HatchPattern: View {
    var spacing: CGFloat = 11
    var lineWidth: CGFloat = 7
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// A hatched image slot with the monospaced bracket label from the design,
/// e.g. `[ day image — quiet morning ]`.
struct ImagePlaceholder: View {
    let label: String?
    var radius: CGFloat = Radius.lg
    var alignment: Alignment = .topLeading
    @Environment(\.dwell) private var t

    init(_ label: String? = nil, radius: CGFloat = Radius.lg, alignment: Alignment = .topLeading) {
        self.label = label
        self.radius = radius
        self.alignment = alignment
    }

    var body: some View {
        ZStack(alignment: alignment) {
            t.surface
            HatchPattern(color: t.surfaceSunken)
            if let label {
                Text("[ \(label) ]")
                    .font(.dwellMonoSm)
                    .foregroundStyle(t.textTertiary)
                    .padding(Space.lg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Hatched circle used for every avatar in the design.
struct Avatar: View {
    var size: CGFloat = 32
    var tinted: Bool = true
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            (tinted ? t.accentWash : t.surface)
            HatchPattern(spacing: 7, lineWidth: 4,
                         color: tinted ? t.accentSoft : t.surfaceSunken)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
