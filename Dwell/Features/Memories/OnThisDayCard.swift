import SwiftUI

/// The large resurfacing card at the top of Memories.
///
/// Geometry from the Figma (`3013:2919`): a 213×322 card, radius 16. The
/// photograph fills the whole card, with background-coloured gradients
/// bleeding in from the top and bottom edges so the title and dates stay
/// legible over any image; the footer carries a 72×72 plan-art chip beside
/// the two dates.
struct OnThisDayCard: View {
    enum Kind {
        case onThisDay
        case noteForLater

        var title: String {
            switch self {
            case .onThisDay:    return "On this day..."
            case .noteForLater: return "A Note for Later"
            }
        }
    }

    let reflection: Reflection
    var kind: Kind = .onThisDay
    var planArt: URL?

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var photoURL: URL?

    private let cardWidth: CGFloat = 213
    private let cardHeight: CGFloat = 322

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

            // The image owns the card; these keep its edges from owning the
            // text as well.
            VStack(spacing: 0) {
                LinearGradient(colors: [t.background.opacity(0.95), t.background.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer(minLength: 0)
                LinearGradient(colors: [t.background.opacity(0), t.background.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title)
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: Space.md) {
                    chip
                    VStack(alignment: .leading, spacing: 0) {
                        Text(relative)
                            .font(.dwellSmall)
                            .foregroundStyle(t.textSecondary)
                        Text(absolute)
                            .font(.dwellSmallMd)
                            .foregroundStyle(t.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(17)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    /// The reflection's own photo where it has one, the app's sky otherwise.
    /// Deliberately not the plan art: it already sits on the chip, and as a
    /// full-card backdrop its baked-in titles fought the card's own text.
    @ViewBuilder
    private var backdrop: some View {
        Group {
            if let url = photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: generic
                    }
                }
            } else {
                generic
            }
        }
        // Outside the branch deliberately, so it runs before the photo URL
        // has been signed and the fallback is showing.
        .task { await loadPhoto() }
    }

    private var generic: some View {
        Image("SkyHero").resizable().scaledToFill()
    }

    @ViewBuilder
    private var chip: some View {
        if let planArt {
            AsyncImage(url: planArt) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: t.surfaceRaised
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func loadPhoto() async {
        guard reflection.mediaType == .photo, let path = reflection.mediaPath else { return }
        photoURL = try? await session.api.mediaURL(path: path)
    }

    private var relative: String {
        let days = Calendar.current.dateComponents([.day],
                                                   from: reflection.createdAt, to: .now).day ?? 0
        switch days {
        case ..<1:   return "Today"
        case 1:      return "1 day ago"
        case 2...6:  return "\(days) days ago"
        case 7...13: return "1 week ago"
        default:     return "\(days / 7) weeks ago"
        }
    }

    private var absolute: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: reflection.createdAt)
    }
}
