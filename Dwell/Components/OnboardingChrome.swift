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

/// Back arrow alone — Sign Up and the YouVersion screens show no progress bar.
struct OnboardingBackBar: View {
    var onBack: () -> Void
    @Environment(\.dwell) private var t

    var body: some View {
        HStack {
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
            Spacer()
        }
        .frame(height: 44)
    }
}

/// Circular avatar. Prefers a real photo, then a seeded stand-in, then a
/// monogram — so it degrades sensibly for a user with no picture.
struct PhotoAvatar: View {
    let name: String
    /// 1…6 — maps to the seeded Avatar imagesets.
    var index: Int?
    /// A real profile photo, when we have one.
    var url: URL?
    var size: CGFloat = 44
    @Environment(\.dwell) private var t

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        monogramView
                    case .empty:
                        t.surfaceRaised
                    @unknown default:
                        monogramView
                    }
                }
            } else if let index, index >= 1, index <= 6 {
                Image("Avatar\(index)")
                    .resizable()
                    .scaledToFill()
            } else {
                monogramView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    private var monogramView: some View {
        ZStack {
            t.surfaceRaised
            Text(monogram)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(t.textSecondary)
        }
    }

    private var monogram: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}
