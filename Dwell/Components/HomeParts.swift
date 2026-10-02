import SwiftUI

/// The stack of cards standing in for the group's reflections.
///
/// Blurred and featureless while the day is sealed; crisp once it opens. It's
/// deliberately not real content — the whole point of the sealed state is that
/// nothing leaks before the threshold clears.
struct ReflectionCardStack: View {
    var sealed: Bool
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            card(rotation: -6, offset: CGSize(width: -26, height: -10), scale: 0.93, opacity: 0.55)
            card(rotation: 4, offset: CGSize(width: 14, height: 4), scale: 0.97, opacity: 0.8)
            card(rotation: -1, offset: .zero, scale: 1, opacity: 1)
        }
        .frame(height: 190)
        .blur(radius: sealed ? 5 : 0)
        .accessibilityHidden(true)
    }

    private func card(rotation: Double, offset: CGSize, scale: CGFloat, opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Circle()
                .fill(t.border)
                .frame(width: 26, height: 26)
                .padding(.bottom, Space.xs)
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(t.border)
                    .frame(height: 9)
                    .padding(.trailing, index == 2 ? 70 : 0)
            }
        }
        .padding(Space.lg)
        .frame(width: 250, height: 150, alignment: .topLeading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
        .opacity(opacity)
    }
}

/// Overlapping member avatars; a tick badge marks everyone who has posted.
/// Order is stable, and no one is singled out as missing.
struct MemberAvatarRow: View {
    let members: [(name: String, url: URL?, posted: Bool)]
    var size: CGFloat = 48
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: -size * 0.22) {
            ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                PhotoAvatar(name: member.name, url: member.url, size: size)
                    .overlay(Circle().strokeBorder(t.background, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if member.posted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: size * 0.3))
                                .foregroundStyle(t.ink)
                                .background(Circle().fill(t.background).padding(2))
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(members.filter(\.posted).count) of \(members.count) have posted")
    }
}

/// "2 of 5 in · opens at 3"
struct StatusPill: View {
    let text: String
    @Environment(\.dwell) private var t

    var body: some View {
        Text(text)
            .font(.dwellSmall)
            .foregroundStyle(t.textSecondary)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm + 2)
            .background(Capsule().fill(t.surfaceRaised))
    }
}

/// The "Your Reflection · Posted 1 hour ago · View" row.
struct YourReflectionRow: View {
    let postedAgo: String
    var planTitle: String = ""
    var planArt: URL?
    var isLate: Bool = false
    var onView: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button(action: onView) {
            HStack(spacing: Space.md) {
                PlanCoverThumb(title: planTitle, imageURL: planArt, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Reflection")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    HStack(spacing: Space.sm) {
                        Text("Posted \(postedAgo)")
                            .font(.dwellSmall)
                            .foregroundStyle(t.textSecondary)
                        if isLate {
                            Text("late")
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(t.surfaceRaised))
                        }
                    }
                }

                Spacer()

                Text("View")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
            }
            .padding(Space.md)
            .background(t.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
    }
}

/// Plan cover art.
///
/// `plan_challenges` has no image column, so there is nothing to fetch — this
/// draws a stand-in keyed off the plan title so each plan at least looks like
/// itself. Swap for `AsyncImage` once `cover_url` exists (see the backend
/// request doc).
struct PlanCoverThumb: View {
    var title: String = "When Life Gets Hard"
    var imageURL: URL?
    var size: CGFloat = 52
    var corner: CGFloat = Radius.sm

    var body: some View {
        PlanCover(title: title, imageURL: imageURL)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct PlanCover: View {
    let title: String
    /// Real artwork from the public `plan-images` bucket, when the plan has
    /// any. The gradient below is the fallback, not the intent.
    var imageURL: URL?

    private var palette: [Color] {
        // Deterministic: Swift seeds `hashValue` per process, so using it here
        // would repaint the cover a different colour on every launch.
        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let options: [[Color]] = [
            [Color(red: 0.98, green: 0.74, blue: 0.62), Color(red: 0.95, green: 0.42, blue: 0.33)],
            [Color(red: 0.72, green: 0.85, blue: 0.95), Color(red: 0.35, green: 0.56, blue: 0.83)],
            [Color(red: 0.86, green: 0.90, blue: 0.76), Color(red: 0.45, green: 0.62, blue: 0.45)],
            [Color(red: 0.92, green: 0.84, blue: 0.95), Color(red: 0.55, green: 0.42, blue: 0.78)]
        ]
        return options[seed % options.count]
    }

    var body: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: gradient
                }
            }
        } else {
            gradient
        }
    }

    private var gradient: some View {
        LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .center) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .padding(6)
            }
    }
}
