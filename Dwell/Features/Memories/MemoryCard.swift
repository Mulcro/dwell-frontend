import SwiftUI

/// One past reflection in the timeline.
struct MemoryCard: View {
    let reflection: Reflection
    var dayIndex: Int?
    var planTitle: String = ""

    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(t.accent)
                Text(dayIndex.map { "Day \($0)" } ?? planTitle)
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
                Spacer()
                Text(relative)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }

            Text(reflection.displayBody)
                .font(.dwellBody)
                .foregroundStyle(t.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.lg)
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

    private var icon: String {
        switch reflection.mediaType {
        case .voice: return "waveform"
        case .photo: return "photo"
        case .text:  return "text.alignleft"
        }
    }

    private var relative: String {
        let days = Calendar.current.dateComponents([.day],
                                                   from: reflection.createdAt,
                                                   to: .now).day ?? 0
        switch days {
        case ..<1:  return "Today"
        case 1:     return "Yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "1 week ago"
        default:    return "\(days / 7) weeks ago"
        }
    }
}
