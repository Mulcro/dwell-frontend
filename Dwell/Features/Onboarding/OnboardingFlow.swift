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
        case howItWorks
        case startOrJoin
        case buildGroup
        case frequency(name: String, plan: PlanChallenge)
        case invite
        case share
        case notifications
    }

    /// Backed by the session so a router rebuild mid-flow resumes here
    /// rather than restarting; see `SessionStore.onboardingStep`.
    private var step: Step {
        get { session.onboardingStep }
        nonmutating set { session.onboardingStep = newValue }
    }

    /// DWELL_STEP=<name> opens straight onto a step, for screenshots.
    static var initialStep: Step {
        switch ProcessInfo.processInfo.environment["DWELL_STEP"] {
        case "signUp":       return .signUp
        case "youVersion":   return .youVersion
        case "stats":        return .stats
        case "howItWorks":   return .howItWorks
        case "startOrJoin":  return .startOrJoin
        case "buildGroup":   return .buildGroup
        case "frequency":    return .frequency(name: "Sunday Crew", plan: Seed.anchored)
        case "invite":       return .invite
        case "share":        return .share
        case "notifications": return .notifications
        default:             return .welcome
        }
    }
    /// Guards the one-time entry correction below.
    @State private var resolvedEntry = false
    /// The finished group's name, carried into Build Group by "Same crew,
    /// new plan". Empty for an ordinary create.
    @State private var newGroupName = ""
    /// Which page the explainer opens on: 0 going forward from Stats,
    /// the last page when Back from Start-or-Join re-enters it.
    @State private var explainerStart = 0
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
                if ProcessInfo.processInfo.environment["DWELL_STEP"] != nil {
                    step = OnboardingFlow.initialStep
                    return
                }
                // A user arriving signed in at the very start skips the
                // account screens but keeps the walk: stats, the explainer,
                // then Start-or-Join, with Back working throughout. A rebuild
                // mid-flow finds the step already moved and leaves it alone.
                guard session.isSignedIn, step == .welcome else { return }
                step = .stats
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
            BibleStatsView(onBack: session.isSignedIn ? { backToLogIn() } : { step = .signUp },
                           onContinue: { explainerStart = 0; step = .howItWorks })

        case .howItWorks:
            HowDwellWorksView(startPage: explainerStart,
                              onBack: { step = .stats },
                              onDone: { step = .startOrJoin })

        case .startOrJoin:
            StartOrJoinView(standalone: (session.group.value ?? nil) != nil,
                            onBack: {
                                // Decided at tap time, not body time, so the
                                // answer is always current. With a group —
                                // "Start a new plan" from a finished one —
                                // back means Home; without one it re-enters
                                // the explainer on its last page.
                                if (session.group.value ?? nil) != nil {
                                    session.finishOnboarding()
                                } else {
                                    explainerStart = 3
                                    step = .howItWorks
                                }
                            },
                            onCreate: { newGroupName = ""; step = .buildGroup },
                            onSameCrew: {
                                newGroupName = session.group.value??.name ?? ""
                                step = .buildGroup
                            },
                            onJoined: {
                                // Order matters: hold the flow open *before*
                                // the group loads, or the router briefly
                                // routes home and rebuilds this view with its
                                // step reset. Then load, then advance.
                                session.beginOnboardingTail()
                                if session.startingNewPlan {
                                    Task {
                                        await session.bootstrap()
                                        session.finishOnboarding()
                                    }
                                } else {
                                    step = .notifications
                                    Task { await session.bootstrap() }
                                }
                            })

        case .buildGroup:
            BuildGroupView(initialName: newGroupName,
                           onBack: { step = .startOrJoin },
                           onNext: { name, plan in step = .frequency(name: name, plan: plan) })

        case let .frequency(name, plan):
            FrequencyThresholdView(
                onBack: { step = .buildGroup },
                onNext: { frequency, customDays, moveOn in
                    Task { await create(name: name, plan: plan,
                                        frequency: frequency,
                                        customDays: customDays,
                                        moveOn: moveOn) }
                })

        case .invite:
            InviteFriendsView(onBack: { step = .startOrJoin },
                              onNext: { step = .share })

        case .share:
            ShareInviteView(onHome: {
                if session.startingNewPlan { session.finishOnboarding() }
                else { step = .notifications }
            })

        case .notifications:
            EnableNotificationsView(onDone: { session.finishOnboarding() })
        }
    }

    /// Stats is the first screen of a signed-in user's walk, so its Back
    /// can't return to the sign-up form. It signs out and lands on Log In,
    /// which is also the only way off the wrong account before a group
    /// exists. Logging into an account that has a group routes straight
    /// Home from there — the router sends a loaded group home on its own.
    private func backToLogIn() {
        Task {
            try? await session.api.signOut()
            session.finishOnboarding()
            await session.bootstrap()
            showLogIn = true
        }
    }

    private func create(name: String, plan: PlanChallenge,
                        frequency: Frequency, customDays: [Int]?,
                        moveOn: Int) async {
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
