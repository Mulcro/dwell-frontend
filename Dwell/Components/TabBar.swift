import SwiftUI

enum DwellTab: String, CaseIterable, Identifiable {
    case home, reading, memories, profile
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .reading:  return "book"
        case .memories: return "calendar"
        case .profile:  return "person.crop.circle"
        }
    }

    var label: String {
        switch self {
        case .home:     return "Home"
        case .reading:  return "Reading"
        case .memories: return "Memories"
        case .profile:  return "Profile"
        }
    }
}

/// The floating tab bar from the redesign: a white pill riding over the
/// content, with the selected tab as a filled ink capsule carrying its label.
/// Profile shows the signed-in avatar rather than a glyph.
struct DwellTabBar: View {
    @Binding var selection: DwellTab
    var avatarName: String = "You"
    var avatarURL: URL?
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(DwellTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.sm)
        .background(
            Capsule().fill(t.background)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
        )
        .overlay(Capsule().strokeBorder(t.border.opacity(0.6), lineWidth: 0.5))
        .padding(.horizontal, Space.xl)
    }

    @ViewBuilder
    private func item(_ tab: DwellTab) -> some View {
        let selected = selection == tab

        Button {
            guard !selected else { return }
            Haptics.tap()
            selection = tab
        } label: {
            HStack(spacing: Space.sm) {
                glyph(tab, selected: selected)
                if selected {
                    Text(tab.label)
                        .font(.dwellSmallMd)
                        .foregroundStyle(t.onInk)
                        .fixedSize()
                }
            }
            .padding(.horizontal, selected ? Space.lg : Space.md)
            .frame(height: 48)
            .frame(maxWidth: selected ? nil : .infinity)
            .background(selected ? t.ink : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private func glyph(_ tab: DwellTab, selected: Bool) -> some View {
        if tab == .profile {
            PhotoAvatar(name: avatarName, url: avatarURL, size: 26)
                .overlay(Circle().strokeBorder(selected ? t.onInk : .clear, lineWidth: 1.5))
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 19, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? t.onInk : t.textPrimary)
        }
    }
}
