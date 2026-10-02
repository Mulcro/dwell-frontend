import SwiftUI

/// The onboarding sequence, in the order the Figma lays it out.
/// Every screen is a plain view; this is the only thing that knows the order.
struct OnboardingFlow: View {
    @Environment(SessionStore.self) private var session

    enum Step: Equatable {
        case welcome
        case signUp
        case youVersion
        case stats
        case startOrJoin
        case buildGroup
        case frequency(name: String, plan: PlanChallenge)
        case invite
        case share
        case notifications
    }

    @State private var step: Step = OnboardingFlow.initialStep

    /// DWELL_STEP=<name> opens straight onto a step, for screenshots.
    static var initialStep: Step {
        switch ProcessInfo.processInfo.environment["DWELL_STEP"] {
        case "signUp":       return .signUp
        case "youVersion":   return .youVersion
        case "stats":        return .stats
        case "startOrJoin":  return .startOrJoin
        case "buildGroup":   return .buildGroup
        case "invite":       return .invite
        case "share":        return .share
        case "notifications": return .notifications
        default:             return .welcome
        }
    }
    /// Guards the one-time entry correction below.
    @State private var resolvedEntry = false
    /// True when the flow opened straight onto `.startOrJoin` because the user
    /// was already signed in — there is then no earlier step to go back to.
    @State private var enteredAtStartOrJoin = false
    @State private var showLogIn = false
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        content
            // The router sends "signed in, but no group" here, and the flow's
            // first step is the signed-out entry — so without this a user who
            // already has an account is asked to create one. Their account is
            // fine; what they're missing is a group.
            .task {
                guard !resolvedEntry else { return }
                resolvedEntry = true
                guard ProcessInfo.processInfo.environment["DWELL_STEP"] == nil,
                      session.isSignedIn, step == .welcome else { return }
                enteredAtStartOrJoin = true
                step = .startOrJoin
            }
            .sheet(isPresented: $showLogIn) {
                LogInView(
                    // Signing in doesn't mean "done" — it means we now know
                    // whether they have a group. If they do, the router takes
                    // them home on its own; if not, they need one.
                    onDone: { showLogIn = false; step = .startOrJoin },
                    onYouVersion: { showLogIn = false; step = .youVersion },
                    onInviteLink: { showLogIn = false; step = .startOrJoin })
            }
            .overlay(alignment: .bottom) {
                if let error {
                    Text(error)
                        .font(.dwellCaption)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 90)
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { self.error = nil }
                        }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeView(onGetStarted: { step = .signUp },
                        onLogIn: { showLogIn = true })

        case .signUp:
            SignUpView(onBack: { step = .welcome },
                       onContinue: { step = .stats },
                       onYouVersion: { step = .youVersion },
                       onInviteLink: { step = .startOrJoin })

        case .youVersion:
            YouVersionSignInView(onBack: { step = .signUp },
                                 onSignedIn: { step = .stats })

        case .stats:
            BibleStatsView(onBack: { step = .signUp },
                           onContinue: { step = .startOrJoin })

        case .startOrJoin:
            StartOrJoinView(onBack: enteredAtStartOrJoin ? nil : { step = .stats },
                            onCreate: { step = .buildGroup },
                            onJoined: {
                                // Order matters: hold the flow open *before*
                                // the group loads, or the router briefly
                                // routes home and rebuilds this view with its
                                // step reset. Then load, then advance.
                                session.beginOnboardingTail()
                                step = .notifications
                                Task { await session.bootstrap() }
                            })

        case .buildGroup:
            BuildGroupView(onBack: { step = .startOrJoin },
                           onNext: { name, plan in step = .frequency(name: name, plan: plan) })

        case let .frequency(name, plan):
            FrequencyThresholdView(
                onBack: { step = .buildGroup },
                onNext: { frequency, customDays, threshold, moveOn in
                    Task { await create(name: name, plan: plan,
                                        frequency: frequency,
                                        customDays: customDays,
                                        threshold: threshold,
                                        moveOn: moveOn) }
                })

        case .invite:
            InviteFriendsView(onBack: { step = .startOrJoin },
                              onNext: { step = .share })

        case .share:
            ShareInviteView(onHome: { step = .notifications })

        case .notifications:
            EnableNotificationsView(onDone: { session.finishOnboarding() })
        }
    }

    private func create(name: String, plan: PlanChallenge,
                        frequency: Frequency, customDays: [Int]?,
                        threshold: Int, moveOn: Int) async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            _ = try await session.api.createGroup(
                name: name,
                planChallengeId: plan.id,
                frequency: frequency,
                customDays: customDays,
                timezone: TimeZone.current.identifier,
                catchUpThresholdPct: threshold,
                autoSkipAfterDays: moveOn)
            session.beginOnboardingTail()
            await session.bootstrap()
            Haptics.posted()
            step = .invite
        } catch {
            Haptics.warning()
            withAnimation { self.error = error.localizedDescription }
        }
    }
}
