import SwiftUI

/// Share button styled to match `DwellButton`, wrapping the system share
/// sheet. The invite link is the app's main growth surface, so it hands over
/// a real URL rather than bare text.
struct ShareInviteButton: View {
    let token: String
    var groupName: String?
    var kind: DwellButtonStyleKind = .primary
    @Environment(\.dwell) private var t

    private var url: URL {
        URL(string: "https://dwell.to/\(token)") ?? URL(string: "https://dwell.to")!
    }

    private var message: String {
        if let groupName {
            return "Join \(groupName) on Dwell — we read together and the day opens when enough of us show up."
        }
        return "Join me on Dwell — we read together and the day opens when enough of us show up."
    }

    var body: some View {
        ShareLink(item: url, message: Text(message)) {
            Text("Share link")
                .font(.dwellButton)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .foregroundStyle(kind == .primary ? t.onAccent : t.textPrimary)
                .background(kind == .primary ? t.accent : t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(kind == .primary ? .clear : t.border, lineWidth: 1)
                )
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}
