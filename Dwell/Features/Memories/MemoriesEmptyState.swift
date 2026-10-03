import SwiftUI

/// The first-run Memories screen, from `Memories · Overview (Empty State)`:
/// a fan of blank cards where the memories will be, "No memories yet!", and
/// a Keep Reflecting button that sends you back to today.
struct MemoriesEmptyState: View {
    var onKeepReflecting: () -> Void = {}
    @Environment(\.dwell) private var t

    /// Rotation per placeholder, echoing the fanned Past Challenges stack.
    private let angles: [Double] = [-0.10, -0.03, 0.04, 0.11]

    var body: some View {
        VStack(spacing: Space.xl) {
            fan
                .padding(.top, Space.xxxl)

            VStack(spacing: Space.md) {
                Text("No memories yet!")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Keep reflecting on what God is doing in your life and those memories will show up here.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(LineSpacing.body)
            }
            .padding(.horizontal, Space.xl)

            PrimaryButton(title: "Keep Reflecting",
                          accent: true,
                          action: onKeepReflecting)
                .padding(.horizontal, Space.xxl)
        }
        .frame(maxWidth: .infinity)
    }

    private var fan: some View {
        HStack(spacing: -14) {
            ForEach(Array(angles.enumerated()), id: \.offset) { index, angle in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(t.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )
                    .frame(width: 76, height: 116)
                    .rotationEffect(.radians(angle))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    .zIndex(Double(index))
            }
        }
        .frame(height: 132)
    }
}
