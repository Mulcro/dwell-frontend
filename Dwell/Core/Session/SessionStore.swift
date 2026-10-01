import SwiftUI
import Observation

/// Owns the signed-in user and the current group, and derives the route.
/// Screens read from here; nothing reads the API directly.
@MainActor
@Observable
final class SessionStore {

    let api: DwellAPI

    var me: DwellUser?
    var group: Loadable<DwellGroup?> = .idle
    var plan: PlanChallenge?
    var members: [GroupMember] = []
    var memberProfiles: [UUID: DwellUser] = [:]

    var currentDay: DayInstance?
    var days: [DayInstance] = []
    var myReflection: Reflection?
    var inactivityPromptPending = false
    var pendingNudge: AIInsight?

    /// Set when a create/join flow is in progress, so the router can show it.
    var entryFlow: EntryFlow?

    /// Captured from a magic link (`dwell://join/CODE` or `dwell.com/CODE`) so
    /// the join screen can prefill it.
    var pendingInviteToken: String?

    /// True while the create-a-group flow is still running its tail — invite,
    /// share, notifications — which all happen *after* the group exists.
    ///
    /// Deliberately in memory rather than UserDefaults: whether someone is set
    /// up is a fact about the server (do they have a group?), not about this
    /// device. A device-local flag would push a returning user with an
    /// existing group back through onboarding on every fresh install.
    var onboardingActive = false

    func beginOnboardingTail() { onboardingActive = true }

    func finishOnboarding() { onboardingActive = false }

    func resetOnboarding() {
        onboardingActive = true
    }

    enum EntryFlow: Equatable { case create, join(prefill: String?) }

    init(api: DwellAPI) {
        self.api = api
    }

    var isSignedIn: Bool { me != nil }

    func name(for userId: UUID) -> String {
        if userId == me?.id { return "You" }
        return memberProfiles[userId]?.name.split(separator: " ").first.map(String.init)
            ?? memberProfiles[userId]?.name
            ?? "Someone"
    }

    /// Threshold math, mirrored from check_day_threshold so the UI can show
    /// "1 / 2" without a round trip.
    var requiredToUnlock: Int {
        guard let g = group.value ?? nil, let day = currentDay else { return 0 }
        let eligible = members.filter { $0.joinedAt <= day.openedAt }.count
        guard eligible > 0 else { return 0 }
        return Int(ceil(Double(eligible) * Double(g.catchUpThresholdPct) / 100.0))
    }

    var postedCount: Int { currentDay?.participationCount ?? 0 }

    // MARK: - Loading

    /// Contract rule 2: the auth trigger only seeds 'UTC' and 'en'. The real
    /// timezone drives day-window math and `preferred_language` is what
    /// group-mates' translations target, so both are pushed on first sight of
    /// a placeholder profile.
    func syncProfileIfNeeded() async {
        guard let current = me else { return }
        let deviceZone = TimeZone.current.identifier
        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let needsZone = current.timezone == "UTC" && deviceZone != "UTC"
        let needsLanguage = current.preferredLanguage == "en" && deviceLanguage != "en"
        guard needsZone || needsLanguage else { return }
        me = try? await api.updateProfile(
            name: nil,
            timezone: needsZone ? deviceZone : nil,
            preferredLanguage: needsLanguage ? deviceLanguage : nil,
            pushToken: nil)
    }

    func bootstrap() async {
        group = .loading
        do {
            me = try await api.currentUser()
            await syncProfileIfNeeded()
            let g = try await api.myGroup()
            group = .loaded(g)
            if let g { try await loadGroupDetail(g) }
        } catch DwellError.notAuthenticated {
            signedOut()
        } catch {
            group = .failed(error.localizedDescription)
        }
    }

    private func loadGroupDetail(_ g: DwellGroup) async throws {
        plan = try await api.getPlan(id: g.planChallengeId)
        members = try await api.members(groupId: g.id)
        let profiles = try await api.users(ids: members.map(\.userId))
        memberProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        guard g.challengeStatus != .forming else { return }

        days = try await api.dayInstances(groupId: g.id)
        currentDay = days.last
        if let day = currentDay {
            myReflection = try await api.reflections(dayInstanceId: day.id)
                .first { $0.userId == me?.id }
        }
        pendingNudge = try await api.insights(groupId: g.id, type: .nudge)
            .first { $0.targetUserId == me?.id }

        // Not the insight row: one is written per member and never deleted,
        // so the row's presence would strand people on that screen forever.
        inactivityPromptPending = g.promptPending
    }

    /// Wipe everything tied to the previous account. Leaving members, days or
    /// a cached reflection behind would briefly show one user's data under
    /// another's name.
    private func signedOut() {
        me = nil
        group = .loaded(nil)
        plan = nil
        members = []
        memberProfiles = [:]
        currentDay = nil
        days = []
        myReflection = nil
        pendingNudge = nil
        inactivityPromptPending = false
        onboardingActive = false
        AvatarStore.shared.clear()
    }

    func reload() async {
        guard let g = group.value ?? nil else { return await bootstrap() }
        do { try await loadGroupDetail(g) } catch {
            group = .failed(error.localizedDescription)
        }
    }

    // MARK: - Actions

    func submitReflection(mediaType: MediaType, body: String) async throws {
        guard let day = currentDay else { throw DwellError.notFound("Today") }
        _ = try await api.submitReflection(
            dayInstanceId: day.id,
            mediaType: mediaType,
            content: mediaType == .text ? body : nil,
            transcript: mediaType == .voice ? body : nil,
            language: me?.preferredLanguage ?? "en")
        await reload()
    }

    func respondToInactivity(_ action: ChallengeAction) async throws {
        guard let g = group.value ?? nil else { return }
        let status = try await api.groupChallengeAction(groupId: g.id, action: action)
        var updated = g
        updated.challengeStatus = status
        group = .loaded(updated)
        inactivityPromptPending = false
        await reload()
    }

    func dismissNudge() { pendingNudge = nil }
}
