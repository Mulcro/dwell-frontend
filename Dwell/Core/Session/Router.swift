import SwiftUI

/// What the app shows.
///
/// The redesign is mid-migration: onboarding is fully specced, the daily loop
/// isn't yet. So this is deliberately small — onboarding, or home. The richer
/// state machine (forming / waiting / unlocked / paused / ended) lives in
/// Archive/LegacyUI and comes back when those screens are redesigned.
enum Route: Equatable {
    case loading
    case failed(String)
    case onboarding
    case home

    @MainActor
    static func resolve(_ session: SessionStore) -> Route {
        switch session.group {
        case .idle, .loading:
            return .loading
        case .failed(let message):
            return .failed(message)
        case .loaded(let group):
            // Signed in with a group is the definition of "set up" — it's a
            // fact about the account, so a returning user on a new device goes
            // straight home. `onboardingActive` only holds the flow open for
            // the steps that follow group creation.
            guard session.isSignedIn, group != nil else { return .onboarding }
            return session.onboardingActive ? .onboarding : .home
        }
    }
}
