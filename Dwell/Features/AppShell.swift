import SwiftUI

/// The tabbed app. The floating tab bar rides over the content, so each tab's
/// scroll view keeps its own bottom inset rather than the bar eating content.
struct AppShell: View {
    @Environment(SessionStore.self) private var session
    @State private var tab: DwellTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:     HomeView()
                case .reading:  ReadingPlaceholder()
                case .memories: MemoriesPlaceholder()
                case .profile:  ProfilePlaceholder()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DwellTabBar(selection: $tab,
                        avatarName: session.me?.name ?? "You",
                        avatarURL: AvatarStore.shared.url)
                .padding(.bottom, Space.sm)
        }
        .dwellThemed()
    }
}

/// Height the floating tab bar occupies, for scroll-view bottom padding.
enum TabBarMetrics {
    static let clearance: CGFloat = 96
}

// MARK: - Placeholders for tabs landing in later phases

private struct ReadingPlaceholder: View {
    var body: some View {
        EmptyStateView(title: "Reading",
                       message: "Plan overview, devotional and passage land in Phase 2.")
    }
}

private struct MemoriesPlaceholder: View {
    var body: some View {
        EmptyStateView(title: "Memories",
                       message: "Overview and calendar land in Phase 8.")
    }
}

private struct ProfilePlaceholder: View {
    @Environment(SessionStore.self) private var session
    var body: some View {
        VStack(spacing: Space.lg) {
            EmptyStateView(title: "Profile",
                           message: "Profile and settings land in Phase 8.")
            SecondaryButton(title: "Sign out") {
                Task {
                    try? await session.api.signOut()
                    session.finishOnboarding()
                    await session.bootstrap()
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, TabBarMetrics.clearance)
        }
    }
}
