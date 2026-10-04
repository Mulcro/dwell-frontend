import SwiftUI

/// The tabbed app. The floating tab bar rides over the content, so each tab's
/// scroll view keeps its own bottom inset rather than the bar eating content.
struct AppShell: View {
    @Environment(SessionStore.self) private var session
    /// DWELL_TAB=<home|reading|memories|profile> opens straight onto a tab,
    /// for screenshots. Same pattern as DWELL_STEP in onboarding.
    @State private var tab: DwellTab = DwellTab(
        rawValue: ProcessInfo.processInfo.environment["DWELL_TAB"] ?? "") ?? .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                // The stalled-group question replaces Home rather than
                // sitting inside it: any member's answer binds the group, so
                // it shouldn't be scrollable past.
                case .home:
                    if session.showsStalledPrompt {
                        StalledGroupView()
                    } else {
                        HomeView()
                    }
                case .reading:  ReadingView()
                case .memories:
                    MemoriesView(onKeepReflecting: {
                        withAnimation(.easeInOut(duration: 0.18)) { tab = .home }
                    })
                case .profile:  ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DwellTabBar(selection: $tab,
                        avatarName: session.me?.name ?? "You",
                        avatarURL: session.me.map { session.avatarURL(for: $0.id) } ?? nil)
                .padding(.bottom, Space.sm)
        }
        .dwellThemed()
    }
}

/// Height the floating tab bar occupies, for scroll-view bottom padding.
enum TabBarMetrics {
    static let clearance: CGFloat = 96
}


