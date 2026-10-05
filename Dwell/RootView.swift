import SwiftUI
import UIKit

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSplash = true

    private var route: Route { Route.resolve(session) }

    var body: some View {
        ZStack {
            content.dwellThemed()

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task { await boot() }
        .onReceive(NotificationCenter.default.publisher(for: .dwellPushToken)) { note in
            guard let token = note.object as? String else { return }
            Task { await session.savePushToken(token) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !showSplash { Task { await session.reload() } }
        }
        // Midnight, a timezone change, or the clock being set. Returning to
        // the foreground already reloads, but an app left open across midnight
        // never did — so every screen reading `session.days` kept yesterday's
        // dates while Home, which derives the marker from `Date.now`, moved on.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await session.reload() }
        }
        .onOpenURL { url in
            if let token = InviteLink.token(from: url) {
                session.pendingInviteToken = token
                Haptics.tap()
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88),
                   value: route)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .loading:
            LoadingView(label: "One moment")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await session.bootstrap() } }
        case .onboarding:
            OnboardingFlow()
        case .home:
            AppShell()
        }
    }

    /// Hold the splash for a beat even on a fast boot, so it reads as a
    /// deliberate opening rather than a flicker.
    private func boot() async {
        #if DEBUG
        if SelfTest.isEnabled {
            await SelfTest.run(api: session.api)
        }
        #endif

        let started = Date()
        await session.bootstrap()

        let minimumOnScreen: TimeInterval = 1.1
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < minimumOnScreen {
            try? await Task.sleep(for: .seconds(minimumOnScreen - elapsed))
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
            showSplash = false
        }
    }
}

/// Parses an invite code out of the custom scheme or the magic link.
///   dwell://join/4K9QRT   ·   https://dwell.com/4K9QRT
enum InviteLink {
    static func token(from url: URL) -> String? {
        let candidate: String?
        switch url.scheme {
        case "dwell":
            candidate = url.pathComponents.last
        case "https", "http":
            guard url.host?.contains("dwell.") == true else { return nil }
            candidate = url.pathComponents.last
        default:
            candidate = nil
        }
        guard let token = candidate?.uppercased(),
              token.count == 6,
              token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return token
    }
}
