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

    /// Signed URLs for `avatar_path`, resolved once per load and cached. The
    /// bucket is private, so each needs signing; `avatar_url` is an external
    /// provider URL and needs none.
    private var signedAvatars: [UUID: URL] = [:]

    /// Order the contract specifies: a chosen picture (`avatar_path`, signed)
    /// beats an inherited one (`avatar_url`), and initials are the fallback.
    func avatarURL(for userId: UUID) -> URL? {
        if let signed = signedAvatars[userId] { return signed }
        let profile = userId == me?.id ? me : memberProfiles[userId]
        if let url = profile?.avatarUrl { return url }
        if userId == me?.id { return AvatarStore.shared.url }
        return nil
    }

    /// Signs every `avatar_path` in the current roster.
    ///
    /// Cached URLs are applied first and synchronously, so a cold start draws
    /// faces immediately instead of showing initials and swapping them a
    /// moment later. Anything not cached is signed in the background and
    /// merged in as it arrives — never clearing what's already on screen.
    func refreshAvatars() async {
        // `me` must win over the roster's copy of the same row. The roster is
        // loaded with the group and goes stale the moment you change your own
        // picture — reading your path from it meant the new avatar only
        // appeared after a later reload refreshed the roster, which looked
        // like needing to upload twice (and showed the *previous* picture).
        var people = memberProfiles
        if let me { people[me.id] = me }
        let paths = people.values.compactMap { person in
            person.avatarPath.flatMap { $0.isEmpty ? nil : (person.id, $0) }
        }

        for (id, path) in paths {
            if let cached = AvatarStore.shared.signed(for: path) { signedAvatars[id] = cached }
        }

        for (id, path) in paths where AvatarStore.shared.signed(for: path) == nil {
            guard let url = try? await api.avatarURL(path: path) else { continue }
            AvatarStore.shared.remember(url, for: path)
            signedAvatars[id] = url
        }

        // Drop anyone who no longer has a picture, so a removed avatar doesn't
        // linger from the previous roster.
        let live = Set(paths.map(\.0))
        signedAvatars = signedAvatars.filter { live.contains($0.key) }
    }

    /// Uploads a new profile picture. Throws `.moderationRefused` if declined.
    func setAvatar(fileURL: URL, mime: String) async throws {
        _ = try await api.setAvatar(fileURL: fileURL, mime: mime)
        me = try? await api.currentUser()
        // Keep the roster's copy in step, so every view reading
        // `memberProfiles` sees the new picture without waiting for a reload.
        if let me { memberProfiles[me.id] = me }
        await refreshAvatars()
    }

    var currentDay: DayInstance?
    var days: [DayInstance] = []
    var myReflection: Reflection?
    /// Day instances you've posted an approved reflection on — what the
    /// reading screen ticks off.
    var completedDayIds: Set<UUID> = []
    /// Your own reflections across the challenge, newest last. Memories is
    /// built from these; the reading ticks come from the set above.
    var myReflections: [Reflection] = []
    /// This week's leaderboard. Scored server-side, so it's the one
    /// participation number the client isn't guessing at.
    var leaderboard: [LeaderboardEntry] = []
    var inactivityPromptPending = false
    var pendingNudge: AIInsight?
    /// The companion's own wording for the stalled-group question, when it
    /// wrote one. The boolean below is what decides whether to *ask*; this is
    /// only the copy.
    var inactivityPrompt: AIInsight?
    /// The companion's synthesis of the day, written once the day unlocks.
    var groupPulse: AIInsight?

    #if DEBUG
    /// Preview switches for the two states that only occur after days of real
    /// inactivity, so they can be seen and demoed without waiting for them.
    /// Debug builds only — these never ship.
    var previewStalled = false
    var previewNudge = false
    var previewPulse = false
    #endif

    /// The day's discussion question. No backend field carries one yet, so
    /// this is nil in production — the card is hidden rather than inventing a
    /// question the companion never asked. See item 45 in Notion.
    var pulseQuestion: String? {
        #if DEBUG
        if previewPulse {
            return "Who in the group would tell you if you stopped listening to them?"
        }
        #endif
        return nil
    }

    /// The pulse to show, real or previewed.
    var visiblePulse: AIInsight? {
        #if DEBUG
        if previewPulse, groupPulse == nil, let g = group.value ?? nil {
            return AIInsight(
                id: UUID(), groupId: g.id, dayInstanceId: currentDay?.id,
                targetUserId: nil, scope: .dayInstance, type: .groupPulse,
                content: "Everyone wrote about someone they'd stopped hearing.",
                createdAt: .now)
        }
        #endif
        return groupPulse
    }

    /// Whether to ask the Continue / Pause / End question.
    var showsStalledPrompt: Bool {
        #if DEBUG
        if previewStalled { return true }
        #endif
        return inactivityPromptPending
    }

    /// The nudge to show on Home, real or previewed.
    var visibleNudge: AIInsight? {
        #if DEBUG
        if previewNudge, pendingNudge == nil, let g = group.value ?? nil {
            return AIInsight(
                id: UUID(), groupId: g.id, dayInstanceId: currentDay?.id,
                targetUserId: me?.id, scope: .dayInstance, type: .nudge,
                content: "Yesterday you wrote about wanting to slow down. "
                       + "Today's passage is short. Five minutes is enough.",
                createdAt: .now)
        }
        #endif
        return pendingNudge
    }

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

    func finishOnboarding() {
        onboardingActive = false
        onboardingStep = .welcome
    }

    /// Where the onboarding flow currently is. Lives here, not in the view:
    /// signing up flips the auth state, the router rebuilds OnboardingFlow,
    /// and @State progress died with the old view — a brand-new account then
    /// re-entered as "already signed in" and was bounced past Bible Stats
    /// and the explainer with no way back.
    var onboardingStep: OnboardingFlow.Step = .welcome

    func resetOnboarding() {
        onboardingActive = true
    }

    enum EntryFlow: Equatable { case create, join(prefill: String?) }

    /// Live subscriptions for the current group. Cancelled and restarted when
    /// the group changes, and torn down on sign-out.
    private var realtime: Task<Void, Never>?
    /// Which group the live subscription is for, so a reload doesn't tear the
    /// socket down and rebuild it every time.
    private var realtimeGroupId: UUID?

    init(api: DwellAPI) {
        self.api = api
    }

    /// `day_instances` and `ai_insights` are the two tables in the realtime
    /// publication (Backend Design Doc §1.4). A day's `participation_count`
    /// moving is how "X of Y posted" updates without exposing anyone's
    /// reflection, and insight inserts are how a nudge arrives.
    private func startRealtime(groupId: UUID) {
        guard realtimeGroupId != groupId || realtime == nil else { return }
        realtime?.cancel()
        realtimeGroupId = groupId
        realtime = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await day in await self.api.dayInstanceUpdates(groupId: groupId) {
                        await self.apply(day)
                    }
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await insight in await self.api.insightInserts(groupId: groupId) {
                        await self.apply(insight)
                    }
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    // Re-read rather than increment: the contract notes a
                    // single insert can be delivered twice, so counting events
                    // would drift.
                    for await _ in await self.api.membershipChanges(groupId: groupId) {
                        await self.reload()
                    }
                }
            }
        }
    }

    private func apply(_ day: DayInstance) {
        if let index = days.firstIndex(where: { $0.id == day.id }) {
            days[index] = day
        } else {
            days.append(day)
            days.sort { $0.dayIndex < $1.dayIndex }
        }
        if currentDay?.id == day.id || day.dayIndex >= (currentDay?.dayIndex ?? 0) {
            currentDay = day
        }
        // A day flipping to threshold_met unlocks everyone else's reflections,
        // which the feed can only see on a re-read.
        if day.isUnlocked { Task { await reload() } }
    }

    private func apply(_ insight: AIInsight) {
        switch insight.type {
        case .nudge:
            guard insight.targetUserId == me?.id else { return }
            pendingNudge = insight

        case .groupPulse:
            // The pulse is rewritten each time someone posts past the
            // threshold, so the row arrives again as an update. Taking the
            // later one keeps the card from freezing on whoever happened to
            // have posted when the day flipped.
            guard insight.dayInstanceId == currentDay?.id else { return }
            if let existing = groupPulse, existing.createdAt > insight.createdAt { return }
            groupPulse = insight

        case .inactivityPrompt:
            inactivityPrompt = insight

        default:
            break
        }
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

    /// When the next reading appears.
    ///
    /// **Not local midnight.** A day opens 24 hours after the *previous day
    /// opened*, and only once that day is `threshold_met`. So whatever hour a
    /// group's Day 1 opened becomes that group's boundary for the whole
    /// challenge — which is deliberate: it guarantees every member a full 24
    /// hours wherever they are, and stops a group racing through a 7-day plan
    /// in an evening.
    ///
    /// Nil while the current day hasn't cleared its threshold, because then it
    /// is waiting on people rather than on the clock and naming a time would be
    /// the same class of wrong as the midnight assumption was.
    var nextDayOpensAt: Date? {
        guard let g = group.value ?? nil, g.challengeStatus == .active,
              let current = currentDay,
              current.status == .thresholdMet || current.status == .complete
        else { return nil }

        let due = current.openedAt.addingTimeInterval(24 * 60 * 60)

        // The rhythm still has to allow the day it lands on.
        let weekdays = g.frequency == .custom ? (g.customDays ?? []) : g.frequency.impliedDays
        guard !weekdays.isEmpty else { return due }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: g.timezone ?? "UTC") ?? .current
        var candidate = due
        for _ in 0...7 {
            // Calendar weekdays are Sunday = 1; the contract uses ISO, Monday = 1.
            let iso = (calendar.component(.weekday, from: candidate) + 5) % 7 + 1
            if weekdays.contains(iso) { return candidate }
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }
        return due
    }

    /// Past due. A job sweeps every 15 minutes, so the day arrives shortly
    /// rather than on the second.
    var nextDayIsDue: Bool {
        guard let due = nextDayOpensAt else { return false }
        return due <= .now
    }

    /// "Tomorrow, 2:00 AM" — the group's moment, told in the reader's time.
    ///
    /// The *instant* comes from the group's timezone, because that is when the
    /// backend actually opens the day and it is the same instant for everyone
    /// in the crew. The *rendering* is the phone's, because the only useful
    /// answer to "when does it open" is when it opens where you are standing.
    ///
    /// For a crew in one timezone these are identical. For one spread across
    /// timezones, a member in New York sees 2:00 AM for a Denver group's
    /// midnight — the same moment, correctly labelled for them, rather than a
    /// wall-clock time that is nobody's but the group's.
    var nextDayOpensLabel: String? {
        guard let date = nextDayOpensAt else { return nil }

        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.locale = .current
        // Day-relative wording has to use the reader's calendar too, or an
        // instant that is "tomorrow" for the group could be labelled tomorrow
        // while falling today for them.
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if Calendar.current.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow,' h:mm a"
        } else {
            formatter.dateFormat = "EEEE, h:mm a"
        }
        return formatter.string(from: date)
    }

    // MARK: - Loading

    /// Contract rule 2: the auth trigger only seeds 'UTC' and 'en'. The real
    /// timezone drives day-window math and `preferred_language` is what
    /// group-mates' translations target, so both are pushed on first sight of
    /// a placeholder profile.
    func syncProfileIfNeeded() async {
        guard let current = me else { return }

        // Only ever once per account. "Still 'en'" is indistinguishable from
        // "deliberately set to English in Settings", so re-running this would
        // overwrite that choice with the device language on the next launch —
        // and the user would have no way to make English stick on a French
        // phone.
        let seal = "profile.synced.\(current.id.uuidString)"
        guard !UserDefaults.standard.bool(forKey: seal) else { return }

        let deviceZone = TimeZone.current.identifier
        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let needsZone = current.timezone == "UTC" && deviceZone != "UTC"
        let needsLanguage = current.preferredLanguage == "en" && deviceLanguage != "en"
        guard needsZone || needsLanguage else {
            // Nothing to push — seal it so a later Settings choice is safe.
            UserDefaults.standard.set(true, forKey: seal)
            return
        }
        // Sealed only on success: sealing first meant one failed request left
        // the device's timezone and language unapplied forever.
        guard let updated = try? await api.updateProfile(
            name: nil,
            timezone: needsZone ? deviceZone : nil,
            preferredLanguage: needsLanguage ? deviceLanguage : nil,
            pushToken: nil) else { return }
        me = updated
        UserDefaults.standard.set(true, forKey: seal)
    }

    func bootstrap() async {
        // Blank the route only when nothing is resolved yet (first boot, or
        // retry after a failure). Sign-up, sign-in and the onboarding tail
        // all re-bootstrap mid-flow, and flipping to .loading there tore
        // down OnboardingFlow and rebuilt it with its state reset — which is
        // how a brand-new account kept landing on Start-or-Join with the
        // earlier steps skipped and Back dead.
        if case .loaded = group {} else { group = .loading }
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
        await refreshAvatars()
        if let mine = try? await api.myReflections(groupId: g.id) {
            let approved = mine.filter { $0.moderationStatus == .approved }
            completedDayIds = Set(approved.map(\.dayInstanceId))
            myReflections = approved.sorted { $0.createdAt < $1.createdAt }
        }
        // Empty until the first Monday 00:00 UTC, per the contract — the
        // tiles fall back to what they can derive until then.
        if let rows = try? await api.leaderboard(groupId: g.id, weekStart: nil) {
            let latest = rows.map(\.weekStart).max()
            leaderboard = rows.filter { $0.weekStart == latest }
                              .sorted { $0.participationScore > $1.participationScore }
        }

        startRealtime(groupId: g.id)

        guard g.challengeStatus != .forming else { return }

        days = try await api.dayInstances(groupId: g.id)
        currentDay = days.last
        if let day = currentDay {
            myReflection = try await api.reflections(dayInstanceId: day.id)
                .first { $0.userId == me?.id }
        }
        pendingNudge = try await api.insights(groupId: g.id, type: .nudge)
            .first { $0.targetUserId == me?.id }
        // Scoped to the current day — an older day's pulse resurfacing on
        // today's home would read as today's.
        groupPulse = try? await api.insights(groupId: g.id, type: .groupPulse)
            .last { $0.dayInstanceId == currentDay?.id }

        // Not the insight row: one is written per member and never deleted,
        // so the row's presence would strand people on that screen forever.
        inactivityPromptPending = g.promptPending
        inactivityPrompt = g.promptPending
            ? try? await api.insights(groupId: g.id, type: .inactivityPrompt).last
            : nil
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
        completedDayIds = []
        myReflections = []
        leaderboard = []
        currentDay = nil
        days = []
        myReflection = nil
        pendingNudge = nil
        inactivityPrompt = nil
        groupPulse = nil
        inactivityPromptPending = false
        onboardingActive = false
        realtime?.cancel()
        realtime = nil
        realtimeGroupId = nil
        AvatarStore.shared.clear()
    }

    /// Re-reads the group itself, not just its contents.
    ///
    /// The group row is where `challenge_status` and `prompt_pending` live, so
    /// reusing a cached copy meant a group that went forming → active (because
    /// someone joined on another device) never updated here. `groups` and
    /// `group_members` are not in the realtime publication — only
    /// `day_instances` and `ai_insights` are — so this refresh *is* the
    /// mechanism for noticing membership changes.
    func reload() async {
        do {
            me = try await api.currentUser()
            let g = try await api.myGroup()
            group = .loaded(g)
            if let g { try await loadGroupDetail(g) } else { clearGroupDetail() }
        } catch DwellError.notAuthenticated {
            signedOut()
        } catch {
            // Keep showing what we have rather than blanking the screen on a
            // failed refresh — a pull-to-refresh that wipes the page is worse
            // than one that quietly fails.
            if group.value == nil { group = .failed(error.localizedDescription) }
        }
    }

    private func clearGroupDetail() {
        plan = nil
        members = []
        memberProfiles = [:]
        completedDayIds = []
        myReflections = []
        leaderboard = []
        currentDay = nil
        days = []
        myReflection = nil
        pendingNudge = nil
        inactivityPrompt = nil
        groupPulse = nil
        inactivityPromptPending = false
    }

    // MARK: - Actions

    func submitReflection(mediaType: MediaType,
                          body: String,
                          attachment: MediaAttachment? = nil) async throws {
        guard let day = currentDay else { throw DwellError.notFound("Today") }
        _ = try await api.submitReflection(
            dayInstanceId: day.id,
            mediaType: mediaType,
            // A photo's caption is `content`, like a text reflection; only
            // voice uses `transcript`.
            content: mediaType == .voice ? nil : body,
            transcript: mediaType == .voice ? body : nil,
            // Detected from the words, spoken or typed — the recogniser's
            // locale only says what it was listening for.
            language: LanguageDetect.dominant(of: body,
                                              fallback: me?.preferredLanguage ?? "en"),
            attachment: attachment)
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

    /// Your score this week, straight from `leaderboard_entries`.
    var myScore: Int? {
        leaderboard.first { $0.userId == me?.id }?.participationScore
    }

    /// Your place in the group this week. Nil until the leaderboard exists.
    var myRank: Int? {
        guard let index = leaderboard.firstIndex(where: { $0.userId == me?.id }) else { return nil }
        return index + 1
    }

    /// Consecutive days posted, counting back. A day that is still open does
    /// not break it — you may simply not have posted yet.
    var currentStreak: Int {
        var count = 0
        for day in days.sorted(by: { $0.dayIndex > $1.dayIndex }) {
            if completedDayIds.contains(day.id) {
                count += 1
            } else if day.status == .complete || day.status == .missed {
                break
            }
        }
        return count
    }

    func dismissNudge() {
        pendingNudge = nil
        #if DEBUG
        previewNudge = false
        #endif
    }
}
