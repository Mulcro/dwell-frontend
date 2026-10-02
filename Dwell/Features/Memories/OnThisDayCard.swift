import SwiftUI

/// The large resurfacing card at the top of Memories.
///
/// The design's version reaches back across previous challenges; nothing
/// outlives a single challenge yet (item 46 in Notion), so this reaches back
/// within the current one. Same shape, shorter memory.
struct OnThisDayCard: View {
    let reflection: Reflection
    var planArt: URL?

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var photoURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On this day…")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .padding(Space.lg)

            backdrop
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()

            HStack(spacing: Space.md) {
                art
                VStack(alignment: .leading, spacing: 2) {
                    Text(relative)
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                    Text(absolute)
                        .font(.dwellSmallMd)
                        .foregroundStyle(t.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.lg)
        }
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    /// The reflection's own photo where there is one; the plan's cover art
    /// otherwise, so the card is never a grey box.
    @ViewBuilder
    private var backdrop: some View {
        if let url = photoURL ?? planArt {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: t.surfaceRaised
                }
            }
        } else {
            ZStack {
                t.surfaceRaised
                Image(systemName: reflection.mediaType == .voice ? "waveform" : "text.alignleft")
                    .font(.system(size: 28))
                    .foregroundStyle(t.textSecondary)
            }
            .task { await loadPhoto() }
        }
    }

    @ViewBuilder
    private var art: some View {
        if let planArt {
            AsyncImage(url: planArt) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: t.surfaceRaised
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
        case 1:      return "Yesterday"
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
