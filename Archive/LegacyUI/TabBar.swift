import SwiftUI

enum DwellTab: String, CaseIterable, Identifiable {
    case today = "Today", feed = "Feed", memories = "Memories", you = "You"
    var id: String { rawValue }
}

/// Text-only tab bar from the design — no icons, hairline top rule.
struct DwellTabBar: View {
    @Binding var selection: DwellTab
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.border)
                .frame(height: 1)
            HStack {
                ForEach(DwellTab.allCases) { tab in
                    Button {
                        guard selection != tab else { return }
                        Haptics.select()
                        selection = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(selection == tab ? .dwellFootnoteMd : .dwellFootnote)
                            .foregroundStyle(selection == tab ? t.textPrimary : t.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, Space.sm)
        }
        .background(t.background)
    }
}
