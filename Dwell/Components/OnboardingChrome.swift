import SwiftUI

/// Back arrow + linear progress, the header on every stepped onboarding screen.
struct OnboardingHeader: View {
    /// 0…1
    let progress: Double
    var onBack: (() -> Void)?
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: Space.lg) {
            if let onBack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(t.textPrimary)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Back")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.ink.opacity(0.12))
                    Capsule()
                        .fill(t.ink)
                        .frame(width: max(geo.size.width * progress, 8))
                }
            }
            .frame(height: 5)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: progress)
            .accessibilityLabel("Step progress")
            .accessibilityValue("\(Int(progress * 100)) percent")
        }
        .frame(height: 44)
    }
}

/// Circular photo avatar, with a monogram fallback.
struct PhotoAvatar: View {
    let name: String
    /// 1…6 — maps to the seeded Avatar imagesets.
    var index: Int?
    var size: CGFloat = 44
    @Environment(\.dwell) private var t

    var body: some View {
        Group {
            if let index, index >= 1, index <= 6 {
                Image("Avatar\(index)")
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    t.surfaceRaised
                    Text(monogram)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(t.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    private var monogram: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}
