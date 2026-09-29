import SwiftUI

/// The tabbed app. Which Today-surface shows is the router's call, not the
/// tab's — Today, Waiting, Pending, Flagged and the unlocked Feed are all the
/// same tab at different points in the day.
struct MainTabs: View {
    let route: Route
    @Environment(SessionStore.self) private var session
    @State private var tab: DwellTab = .today

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .today:    todaySurface
                case .feed:     FeedView()
                case .memories: MemoriesView()
                case .you:      ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DwellTabBar(selection: $tab)
        }
        .onChange(of: route) { _, new in
            // When the day unlocks, meet the user where the content is.
            if new == .unlocked, tab == .today { tab = .feed }
        }
    }

    @ViewBuilder
    private var todaySurface: some View {
        switch route {
        case .today:              TodayView()
        case .waiting:            WaitingView()
        case .reflectionPending:  ReflectionPendingView()
        case .reflectionFlagged:  ReflectionFlaggedView()
        case .unlocked:           TodayView()
        default:                  TodayView()
        }
    }
}
