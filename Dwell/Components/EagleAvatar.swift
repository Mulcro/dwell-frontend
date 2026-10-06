import SwiftUI

/// Eagle's mark: the dove from the app icon on a blurred sky, in a circle.
/// Figma 12 · Brand & Assets, "Sky Icon" (44pt).
///
/// Active, with a cyan ring and glow, when Eagle has something the viewer
/// hasn't seen yet; resting otherwise.
struct EagleAvatar: View {
    enum Mood { case resting, active }

    var mood: Mood = .resting
    var size: CGFloat = 44

    @Environment(\.dwell) private var t

    /// Every measurement in the comp is at 44pt.
    private var k: CGFloat { size / 44 }

    var body: some View {
        ZStack {
            Image("EagleSky")
                .resizable()
                .blur(radius: 4.3 * k, opaque: true)

            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.76)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.8)

            Image("EagleDove")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 26.75 * k, height: 24 * k)
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color(red: 0.878, green: 0.938, blue: 0.978).opacity(0.78)],
                    startPoint: .leading, endPoint: .trailing))
                .shadow(color: Color(red: 0.18, green: 0.31, blue: 0.4).opacity(0.32),
                        radius: 1.4 * k, y: 1.2 * k)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(.white.opacity(0.65), lineWidth: 0.6 * k)
                .blendMode(.plusLighter)
        )
        .overlay {
            if mood == .active {
                Circle().strokeBorder(t.accent, lineWidth: max(1, k))
            }
        }
        .shadow(color: mood == .active ? t.accent.opacity(0.4) : .clear, radius: 10 * k)
        .accessibilityLabel("Eagle")
    }
}

#Preview {
    HStack(spacing: 32) {
        EagleAvatar(mood: .resting)
        EagleAvatar(mood: .active)
        EagleAvatar(mood: .active, size: 88)
    }
    .padding(40)
    .dwellThemed()
}
