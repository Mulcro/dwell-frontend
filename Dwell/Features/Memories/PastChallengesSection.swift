import SwiftUI

/// A challenge the group has finished, with its photographs fanned out.
///
/// Geometry from the Figma (`3013:2919`, `Frame 17`): four cards at
/// 99×136, 91×131, 96×134 and 92×132, rotated −0.11, +0.05, −0.08 and +0.05
/// radians, slightly overlapping. The last carries the "+N" overflow.
struct PastChallengeRow: View {
    struct Challenge: Identifiable {
        let id: UUID
        var title: String
        var ended: Date
        var mediaURLs: [URL]
        var coverArt: URL?
        var totalCount: Int
    }

    let challenge: Challenge
    @Environment(\.dwell) private var t

    /// Width, height and rotation per position, straight from the comp.
    private let layout: [(w: CGFloat, h: CGFloat, angle: Double)] = [
        (99, 136, -0.11), (91, 131, 0.05), (96, 134, -0.08), (92, 132, 0.05)
    ]

    /// Only as many tiles as there are pictures — padding the stack with
    /// repeats of the plan's cover art would claim memories that don't exist.
    /// With none at all, one tile shows the cover as a plain marker.
    private var visibleLayout: [(w: CGFloat, h: CGFloat, angle: Double)] {
        let available = max(challenge.mediaURLs.count, 1)
        return Array(layout.prefix(min(available, layout.count)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(challenge.title)
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(monthLabel)
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .layoutPriority(1)
            }

            HStack(spacing: -6) {
                ForEach(Array(visibleLayout.enumerated()), id: \.offset) { index, spec in
                    tile(at: index, spec: spec)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 140)
        }
    }

    @ViewBuilder
    private func tile(at index: Int, spec: (w: CGFloat, h: CGFloat, angle: Double)) -> some View {
        let isOverflow = index == visibleLayout.count - 1 && remaining > 0
        ZStack {
            image(at: index)
                .frame(width: spec.w, height: spec.h)
                .clipped()
            if isOverflow {
                Color.black.opacity(0.45)
                Text("+\(remaining)")
                    .font(.dwellSmallMd)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: spec.w, height: spec.h)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(t.background, lineWidth: 2)
        )
        // Figma stores rotation in radians.
        .rotationEffect(.radians(spec.angle))
    }

    @ViewBuilder
    private func image(at index: Int) -> some View {
        if index < challenge.mediaURLs.count {
            AsyncImage(url: challenge.mediaURLs[index]) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: t.surfaceRaised
                }
            }
        } else if let cover = challenge.coverArt {
            AsyncImage(url: cover) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: t.surfaceRaised
                }
            }
        } else {
            t.surfaceRaised
        }
    }

    /// Photographs beyond the ones on screen.
    private var remaining: Int {
        max(challenge.totalCount - challenge.mediaURLs.count, 0)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: challenge.ended)
    }
}
