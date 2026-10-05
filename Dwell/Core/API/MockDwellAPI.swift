import Foundation
import Observation

/// In-memory backend. Reproduces the rules that matter to the UI — the
/// reflection lock, threshold math, late-window flagging, moderation gating —
/// so screens can't drift from what Supabase will actually allow.
///
/// `Scenario` seeds a whole world at once, which is how every router state is
/// reachable without hand-driving the app there.
@MainActor
@Observable
final class MockDwellAPI: DwellAPI {

    enum Scenario: String, CaseIterable, Identifiable {
        case signedOut          = "Signed out"
        case noGroup            = "No group yet"
        case forming            = "Forming, waiting for 1 more"
        case dayOpenNotPosted   = "Day open, you haven't posted"
        case postFlagged        = "Your post, flagged"
        case postedBelow        = "Posted, group below threshold"
        case dayUnlocked        = "Day unlocked, feed"
        case postedLate         = "Posted late"
        case nudgeWaiting       = "Nudge waiting for you"
        case inactivityPrompt   = "3 silent days, Continue/Pause/End"
        case paused             = "Paused"
        case completed          = "Completed"
        case abandoned          = "Abandoned"
        case expiredIncomplete  = "Expired incomplete"

        var id: String { rawValue }
    }

    // Storage
    private(set) var me: DwellUser?
    private(set) var group: DwellGroup?
    private var membersStore: [GroupMember] = []
    private var days: [DayInstance] = []
    private var reflectionsStore: [Reflection] = []
    private var commentsStore: [Comment] = []
    private var reactionsStore: [Reaction] = []
    private var insightsStore: [AIInsight] = []
    private var continuationsStore: [Continuation] = []
    private var leaderboardStore: [LeaderboardEntry] = []
    private(set) var inactivityPromptPending = false

    private var dayContinuations: [UUID: AsyncStream<DayInstance>.Continuation] = [:]
    private var insightContinuations: [UUID: AsyncStream<AIInsight>.Continuation] = [:]

    /// Artificial latency so loading states are visible in the simulator.
    var latency: Duration = .milliseconds(180)

    init(scenario: Scenario = .dayOpenNotPosted) {
        load(scenario)
    }

    // MARK: - Scenario seeding

    func load(_ scenario: Scenario) {
        me = scenario == .signedOut ? nil : Seed.maya
        group = nil
        membersStore = []; days = []; reflectionsStore = []
        commentsStore = []; reactionsStore = []; insightsStore = []
        leaderboardStore = []; inactivityPromptPending = false
        continuationsStore = []

        guard scenario != .signedOut, scenario != .noGroup else { return }

        // A finished challenge whose crew-mate has started the next one, so
        // the invitation card shows in these scenarios' screenshots.
        if [.completed, .abandoned].contains(scenario) {
            continuationsStore = [Continuation(
                groupId: Self.crewNextId, name: "Sunday Crew",
                continuesGroupId: Seed.groupId,
                planTitle: Seed.james.title, planImagePath: Seed.james.imagePath,
                dayCount: Seed.james.dayCount, memberCount: 1,
                createdBy: Seed.priya.id, createdByName: Seed.priya.name)]
        }

        let status: ChallengeStatus
        switch scenario {
        case .forming:            status = .forming
        case .paused:             status = .paused
        case .completed:          status = .completed
        case .abandoned:          status = .abandoned
        case .expiredIncomplete:  status = .expiredIncomplete
        default:                  status = .active
        }

        group = DwellGroup(id: Seed.groupId,
                      name: "Sunday Crew",
                      planChallengeId: Seed.planId,
                      catchUpThresholdPct: 50,
                      autoSkipAfterDays: 3,
                      frequency: .fourPerWeek,
                      customDays: nil,
                      timezone: "America/New_York",
                      challengeStatus: status,
                      promptPending: scenario == .inactivityPrompt,
                      inviteToken: "4K9QRT",
                      createdBy: Seed.maya.id,
                      createdAt: .now.addingTimeInterval(-86_400 * 4))

        // Forming has only the creator — that's the whole point of the state.
        let roster = scenario == .forming ? [Seed.maya] : Seed.allUsers
        membersStore = roster.map {
            GroupMember(groupId: Seed.groupId, userId: $0.id,
                        joinedAt: .now.addingTimeInterval(-86_400 * 4))
        }

        guard status != .forming else { return }

        seedDays(scenario: scenario)
        seedReflections(scenario: scenario)
        seedInsights(scenario: scenario)
        seedLeaderboard()

        if scenario == .inactivityPrompt { inactivityPromptPending = true }
    }

    private func seedDays(scenario: Scenario) {
        let finished = [Scenario.completed, .abandoned, .expiredIncomplete].contains(scenario)
        let upTo = finished ? 7 : 3

        for index in 1...upTo {
            let plan = Seed.anchoredDays.first { $0.dayIndex == index }!
            let isCurrent = index == upTo && !finished
            let opened = Date.now.addingTimeInterval(-86_400 * Double(upTo - index) - 3_600 * 5)

            var status: DayStatus = isCurrent ? .open : .complete
            if isCurrent {
                switch scenario {
                case .dayUnlocked, .postedLate: status = .thresholdMet
                default:                        status = .open
                }
            }

            days.append(DayInstance(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D\(index)")!,
                groupId: Seed.groupId,
                dayIndex: index,
                date: opened,
                passageRef: plan.passageRef,
                openedAt: scenario == .postedLate ? opened.addingTimeInterval(-86_400) : opened,
                status: status,
                participationCount: isCurrent ? currentCount(scenario) : 4,
                consecutiveBelowThresholdCount: scenario == .inactivityPrompt ? 3 : 0))
        }
    }

    private func currentCount(_ scenario: Scenario) -> Int {
        switch scenario {
        case .dayUnlocked, .postedLate: return 3
        case .postedBelow:              return 1
        case .postFlagged:              return 1
        case .inactivityPrompt:         return 0
        default:                        return 1
        }
    }

    private func seedReflections(scenario: Scenario) {
        guard let today = days.last else { return }

        // Past days: everyone posted, so history reads as complete.
        for day in days.dropLast() {
            for user in Seed.allUsers {
                reflectionsStore.append(makeReflection(user: user, day: day, status: .approved))
            }
        }

        switch scenario {
        case .dayOpenNotPosted, .inactivityPrompt, .nudgeWaiting:
            if scenario != .inactivityPrompt {
                reflectionsStore.append(makeReflection(user: Seed.priya, day: today, status: .approved))
            }

        case .postFlagged:
            reflectionsStore.append(makeReflection(user: Seed.maya, day: today, status: .flagged))
            reflectionsStore.append(makeReflection(user: Seed.priya, day: today, status: .approved))

        case .postedBelow:
            reflectionsStore.append(makeReflection(user: Seed.maya, day: today, status: .approved))

        case .dayUnlocked, .postedLate:
            for user in [Seed.maya, Seed.priya, Seed.jordan] {
                var r = makeReflection(user: user, day: today, status: .approved)
                if user.id == Seed.maya.id, scenario == .postedLate { r.isLate = true }
                reflectionsStore.append(r)
            }
            seedEngagement(today: today)

        default:
            break
        }
    }

    private func makeReflection(user: DwellUser, day: DayInstance, status: ModerationStatus) -> Reflection {
        let voice = user.id == Seed.jordan.id
        let body = Self.bodies[user.id] ?? "Sitting with this one today."
        return Reflection(
            id: UUID(),
            userId: user.id,
            dayInstanceId: day.id,
            mediaType: voice ? .voice : .text,
            content: voice ? nil : body,
            transcript: voice ? body : nil,
            translatedText: user.preferredLanguage == "en" ? nil : ["en": body],
            language: user.preferredLanguage,
            sentimentTag: status == .approved ? "hopeful" : nil,
            moderationStatus: status,
            isLate: false,
            createdAt: day.openedAt.addingTimeInterval(3_600 * 2),
            aiResponse: status == .approved ? (Self.aiResponses[user.id] ?? nil) : nil)
    }

    private static let bodies: [UUID: String] = [
        Seed.maya.id:   "I keep reading \u{201C}anchor\u{201D} and thinking about how much of this week I spent drifting. I called my mother back today instead of letting it sit.",
        Seed.priya.id:  "I was slow to listen today. My mother called twice and I answered like I was in a hurry. I called her back and just let her talk.",
        Seed.jordan.id: "\u{2026}honestly I didn't want to talk to anyone this week, but I keep coming back to this one line.",
        Seed.daniel.id: "Hope feels like a stretch this week. Reading it anyway."
    ]

    private static let aiResponses: [UUID: String?] = [
        Seed.maya.id:  "Calling her back was the anchor holding, not slipping. You noticed the drift and did something small and concrete about it, that's the verse doing its work, not just being read.",
        Seed.priya.id: "Calling back was the whole verse, right there. You didn't just hear her, you made room for her.",
        Seed.jordan.id: "Not wanting to talk and showing up anyway is its own kind of steadfast. You keep returning to the line; let it keep returning to you."
    ]

    private func seedEngagement(today: DayInstance) {
        guard let priya = reflectionsStore.first(where: { $0.userId == Seed.priya.id && $0.dayInstanceId == today.id }) else { return }
        commentsStore = [
            Comment(id: UUID(), reflectionId: priya.id, userId: Seed.maya.id,
                    content: "okay this one got me. Calling back counts.",
                    createdAt: .now.addingTimeInterval(-14_400)),
            Comment(id: UUID(), reflectionId: priya.id, userId: Seed.daniel.id,
                    content: "My mum does the same thing. Going to try this tonight.",
                    createdAt: .now.addingTimeInterval(-3_600))
        ]
        reactionsStore = [
            Reaction(id: UUID(), reflectionId: priya.id, userId: Seed.jordan.id, emoji: "♡", createdAt: .now),
            Reaction(id: UUID(), reflectionId: priya.id, userId: Seed.daniel.id, emoji: "Amen", createdAt: .now)
        ]
    }

    private func seedInsights(scenario: Scenario) {
        insightsStore.append(AIInsight(
            id: UUID(), groupId: Self.soulRestId, dayInstanceId: nil, targetUserId: nil,
            scope: .groupChallenge, type: .endSummary,
            content: "Seven days of the Psalms, and the thread was rest you had to choose.",
            createdAt: .now.addingTimeInterval(-86_400 * 30),
            payload: PulsePayload(
                headline: "rest as something you practise, not something you wait for",
                members: [
                    PulseMember(userId: Seed.maya.id, line: "Kept the group chat honest"),
                    PulseMember(userId: Seed.priya.id, line: "Prayed in three languages"),
                    PulseMember(userId: Seed.daniel.id, line: "Never missed a morning")
                ],
                reflectionCount: 97,
                daysShowedUp: 7,
                daysTotal: 7)))

        guard let today = days.last else { return }

        if scenario == .dayUnlocked || scenario == .postedLate {
            insightsStore.append(AIInsight(
                id: UUID(), groupId: Seed.groupId, dayInstanceId: today.id, targetUserId: nil,
                scope: .dayInstance, type: .groupPulse,
                content: "Everyone wrote about someone they'd stopped hearing. Priya's mother. Jordan's silence. Maya's drift. Nobody mentioned strangers, this is all about people already close.\n\nOne question for tonight: who in this group would tell you if you'd stopped listening to them?",
                createdAt: .now))
        }

        if scenario == .nudgeWaiting || scenario == .dayOpenNotPosted {
            insightsStore.append(AIInsight(
                id: UUID(), groupId: Seed.groupId, dayInstanceId: today.id, targetUserId: Seed.maya.id,
                scope: .dayInstance, type: .nudge,
                content: "Your day's still open for 5 more hours. Hebrews calls hope an anchor, you've been the one holding steady all week. Say one line?",
                createdAt: .now))
        }

        if scenario == .inactivityPrompt {
            insightsStore.append(AIInsight(
                id: UUID(), groupId: Seed.groupId, dayInstanceId: today.id,
                targetUserId: Seed.maya.id,   // one row per member, never deleted
                scope: .groupChallenge, type: .inactivityPrompt,
                content: "It's been quiet for a few days. No pressure and no catching up needed. Today's page is open whenever one of you is ready.",
                createdAt: .now))
        }

        if scenario == .completed {
            insightsStore.append(AIInsight(
                id: UUID(), groupId: Seed.groupId, dayInstanceId: nil, targetUserId: nil,
                scope: .groupChallenge, type: .endSummary,
                content: "You came in wanting to be consistent. You left talking about people.\n\nWeek 1 was showing up, short entries, mostly about the reading itself. By the middle it was hope as something you had to choose on a Tuesday. Three separate entries end with you calling someone back. That's the application you kept choosing, not more reading.\n\nAcross the group, \u{201C}anchor\u{201D} landed in four languages on the same four phone calls home.",
                createdAt: .now,
                // The recap card (contract, 2026-10-03), so the completed
                // scenario demos the full screen.
                payload: PulsePayload(
                    headline: "hope as something you choose, then act on",
                    members: [
                        PulseMember(userId: Seed.maya.id, line: "Asked the questions that got replies"),
                        PulseMember(userId: Seed.priya.id, line: "Wrote in two languages, always about home"),
                        PulseMember(userId: Seed.jordan.id, line: "Shared a voice note for the first time"),
                        PulseMember(userId: Seed.daniel.id, line: "Kept coming back to rest")
                    ],
                    reflectionCount: 22,
                    daysShowedUp: 6,
                    daysTotal: 7)))
        }

        if scenario == .abandoned || scenario == .expiredIncomplete {
            insightsStore.append(AIInsight(
                id: UUID(), groupId: Seed.groupId, dayInstanceId: nil, targetUserId: nil,
                scope: .groupChallenge, type: .fallbackRecap,
                content: "You got three days into Anchored together. That's three mornings you chose to open it, Hebrews, Isaiah, and Romans, with eleven reflections between you. It stalled, and that's allowed. The door's still here when you want it.",
                createdAt: .now))
        }
    }

    private func seedLeaderboard() {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let scores: [(DwellUser, Int)] = [(Seed.priya, 7), (Seed.maya, 6), (Seed.jordan, 5), (Seed.daniel, 4)]
        leaderboardStore = scores.map { user, score in
            LeaderboardEntry(id: UUID(), groupId: Seed.groupId, weekStart: weekStart,
                             userId: user.id, participationScore: score)
        }
    }

    // MARK: - Auth

    func signIn(provider: AuthProvider) async throws -> DwellUser {
        try await tick()
        me = Seed.maya
        return Seed.maya
    }

    func signIn(email: String, password: String) async throws -> DwellUser {
        try await tick()
        me = Seed.maya
        return Seed.maya
    }

    func signUp(email: String, password: String, name: String?) async throws -> DwellUser {
        try await tick()
        var user = Seed.maya
        if let name, !name.isEmpty { user.name = name }
        me = user
        return user
    }

    func setAvatar(fileURL: URL, mime: String) async throws -> String {
        try await tick()
        throw DwellError.notImplemented("Avatars")
    }

    func avatarURL(path: String) async throws -> URL {
        throw DwellError.notFound("Avatar")
    }

    func deleteAccount() async throws {
        try await tick()
        load(.signedOut)
    }

    func signOut() async throws {
        try await tick()
        load(.signedOut)
    }

    // MARK: - Edge Functions

    func createGroup(name: String, planChallengeId: UUID,
                     frequency: Frequency, customDays: [Int]?, timezone: String,
                     autoSkipAfterDays: Int?,
                     continuesGroupId: UUID?) async throws -> CreateGroupResponse {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
        let new = DwellGroup(id: UUID(), name: name, planChallengeId: planChallengeId,
                        catchUpThresholdPct: 50,
                        autoSkipAfterDays: autoSkipAfterDays ?? 3,
                        frequency: frequency, customDays: customDays, timezone: timezone,
                        challengeStatus: .forming, promptPending: false, inviteToken: token,
                        createdBy: me.id, createdAt: .now)
        group = new
        membersStore = [GroupMember(groupId: new.id, userId: me.id, joinedAt: .now)]
        days = []; reflectionsStore = []
        return CreateGroupResponse(groupId: new.id, inviteToken: token)
    }

    static let crewNextId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B9")!

    func myContinuations() async throws -> [Continuation] {
        try await tick(); return continuationsStore
    }

    /// Accepting moves you into the crew-mate's new group as its second
    /// member, which starts it, the same as join-group does by code.
    func joinGroup(groupId: UUID) async throws -> JoinGroupResponse {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        guard let invite = continuationsStore.first(where: { $0.groupId == groupId }),
              let previous = group else {
            throw DwellError.notFound("That invite")
        }
        if let current = group, !current.challengeStatus.isEnded {
            throw DwellError.conflict("Your group's challenge is still going. Finish it or leave the group first.")
        }
        let next = DwellGroup(id: invite.groupId, name: invite.name, planChallengeId: Seed.james.id,
                          catchUpThresholdPct: 50, autoSkipAfterDays: previous.autoSkipAfterDays,
                          frequency: previous.frequency, customDays: previous.customDays,
                          timezone: previous.timezone, challengeStatus: .active,
                          promptPending: false, inviteToken: "CRW2NX",
                          createdBy: invite.createdBy ?? Seed.priya.id, createdAt: .now)
        group = next
        membersStore = [GroupMember(groupId: next.id, userId: invite.createdBy ?? Seed.priya.id, joinedAt: .now),
                        GroupMember(groupId: next.id, userId: me.id, joinedAt: .now)]
        days = []; reflectionsStore = []; commentsStore = []; reactionsStore = []
        leaderboardStore = []
        openDay(index: 1)
        continuationsStore.removeAll { $0.groupId == groupId }
        return JoinGroupResponse(groupId: next.id, challengeStatus: .active)
    }

    func joinGroup(inviteToken: String) async throws -> JoinGroupResponse {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        guard var g = group, g.inviteToken.caseInsensitiveCompare(inviteToken) == .orderedSame else {
            throw DwellError.notFound("That invite")
        }
        if !membersStore.contains(where: { $0.userId == me.id }) {
            membersStore.append(GroupMember(groupId: g.id, userId: me.id, joinedAt: .now))
        }
        // Second member flips forming → active and opens Day 1.
        if membersStore.count >= 2, g.challengeStatus == .forming {
            g.challengeStatus = .active
            group = g
            openDay(index: 1)
        }
        return JoinGroupResponse(groupId: g.id, challengeStatus: g.challengeStatus)
    }

    func previewGroup(inviteToken: String) async throws -> GroupPreview? {
        try await tick()
        guard let g = group, g.inviteToken.caseInsensitiveCompare(inviteToken) == .orderedSame else {
            return nil   // empty array from the RPC — a normal answer
        }
        let plan = try await getPlan(id: g.planChallengeId)
        return GroupPreview(name: g.name, planTitle: plan.title)
    }

    func submitReflection(dayInstanceId: UUID, mediaType: MediaType,
                          content: String?, transcript: String?,
                          language: String,
                          attachment: MediaAttachment?) async throws -> SubmitReflectionResponse {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        guard let dayIdx = days.firstIndex(where: { $0.id == dayInstanceId }) else {
            throw DwellError.notFound("That day")
        }
        if reflectionsStore.contains(where: { $0.userId == me.id && $0.dayInstanceId == dayInstanceId }) {
            throw DwellError.conflict("You've already reflected today.")
        }

        let day = days[dayIdx]
        let joined = membersStore.first { $0.userId == me.id }?.joinedAt
        let late = Date.now > day.windowCloses(joinedAt: joined)

        // Moderation: mock flags anything obviously abusive, approves the rest.
        let body = (transcript ?? content ?? "")
        let flagged = Self.moderationBlocklist.contains { body.lowercased().contains($0) }
        let status: ModerationStatus = flagged ? .flagged : .approved

        reflectionsStore.append(Reflection(
            id: UUID(), userId: me.id, dayInstanceId: dayInstanceId,
            mediaType: mediaType, content: content, transcript: transcript,
            translatedText: nil, language: language,
            sentimentTag: flagged ? nil : "hopeful",
            moderationStatus: status, isLate: late, createdAt: .now,
            aiResponse: flagged ? nil : "That's a real thing to notice, and naming it is most of the work. Carry that one line into tomorrow and see if it holds."))

        if status == .approved { recomputeThreshold(dayIndex: dayIdx) }
        return SubmitReflectionResponse(reflectionId: reflectionsStore.last!.id,
                                        moderationStatus: status,
                                        isLate: late)
    }

    private static let moderationBlocklist = ["hate you", "kill", "worthless"]

    func groupChallengeAction(groupId: UUID, action: ChallengeAction) async throws -> ChallengeStatus {
        try await tick()
        guard var g = group else { throw DwellError.notFound("Group") }
        switch action {
        case .continue: g.challengeStatus = .active
        case .pause:    g.challengeStatus = .paused
        case .end:      g.challengeStatus = .abandoned
        }
        g.promptPending = false
        group = g
        inactivityPromptPending = false
        group = g
        return g.challengeStatus
    }

    // MARK: - Threshold + advancement (mirrors check_day_threshold)

    private func recomputeThreshold(dayIndex: Int) {
        var day = days[dayIndex]
        let eligible = membersStore.filter { $0.joinedAt <= day.openedAt }.count
        let posted = reflectionsStore.filter {
            $0.dayInstanceId == day.id && $0.moderationStatus == .approved
        }.count

        day.participationCount = posted
        if eligible > 0,
           Double(posted) / Double(eligible) * 100 >= Double(group?.catchUpThresholdPct ?? 50),
           day.status == .open {
            day.status = .thresholdMet
        }
        days[dayIndex] = day
        dayContinuations[day.groupId]?.yield(day)
    }

    private func openDay(index: Int) {
        guard let g = group,
              let plan = Seed.anchoredDays.first(where: { $0.dayIndex == index }) else { return }
        days.append(DayInstance(id: UUID(), groupId: g.id, dayIndex: index, date: .now,
                                passageRef: plan.passageRef, openedAt: .now, status: .open,
                                participationCount: 0, consecutiveBelowThresholdCount: 0))
    }

    // MARK: - PostgREST reads

    func currentUser() async throws -> DwellUser {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        return me
    }

    func updateProfile(name: String?, timezone: String?, preferredLanguage: String?, pushToken: String?) async throws -> DwellUser {
        try await tick()
        guard var u = me else { throw DwellError.notAuthenticated }
        if let name { u.name = name }
        if let timezone { u.timezone = timezone }
        if let preferredLanguage { u.preferredLanguage = preferredLanguage }
        if let pushToken { u.pushToken = pushToken }
        me = u
        return u
    }

    func myGroup() async throws -> DwellGroup? { try await tick(); return group }

    /// Two finished challenges sit behind the current group, so What's Next
    /// has an archive to show. Soul Rest carries a recap card; Lent with
    /// Roomies has none, which is the case View has to handle.
    static let soulRestId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B7")!
    static let lentId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B8")!

    func myGroups() async throws -> [GroupSummary] {
        try await tick()
        guard let g = group else { return [] }
        let plan = Seed.plans.first { $0.id == g.planChallengeId }
        let current = GroupSummary(
            id: g.id, name: g.name, challengeStatus: g.challengeStatus,
            planChallengeId: g.planChallengeId, planTitle: plan?.title ?? "",
            planImagePath: plan?.imagePath, dayCount: plan?.dayCount ?? 7,
            memberCount: membersStore.count, reflectionCount: 11)
        let archived = [
            GroupSummary(id: Self.soulRestId, name: "Soul Rest", challengeStatus: .completed,
                         planChallengeId: Seed.james.id, planTitle: Seed.james.title,
                         planImagePath: nil, dayCount: 7, memberCount: 5, reflectionCount: 97),
            GroupSummary(id: Self.lentId, name: "Lent with Roomies", challengeStatus: .abandoned,
                         planChallengeId: Seed.anchored.id, planTitle: Seed.anchored.title,
                         planImagePath: nil, dayCount: 7, memberCount: 3, reflectionCount: 12)
        ]
        // The current group leads either way: if it's still going it wins
        // outright, and if it's finished it's the most recently active.
        return [current] + archived
    }
    func members(groupId: UUID) async throws -> [GroupMember] { try await tick(); return membersStore }
    func users(ids: [UUID]) async throws -> [DwellUser] {
        try await tick(); return Seed.allUsers.filter { ids.contains($0.id) }
    }
    func dayInstances(groupId: UUID) async throws -> [DayInstance] { try await tick(); return days }
    func currentDay(groupId: UUID) async throws -> DayInstance? { try await tick(); return days.last }

    /// Enforces the reflection lock: your own always; everyone else's only once
    /// you've posted an approved reflection AND the day has met threshold
    /// (MVP Spec §4).
    func reflections(dayInstanceId: UUID) async throws -> [Reflection] {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        let all = reflectionsStore.filter { $0.dayInstanceId == dayInstanceId }
        let mine = all.filter { $0.userId == me.id }
        let iPosted = mine.contains { $0.moderationStatus == .approved }
        let unlocked = days.first { $0.id == dayInstanceId }?.isUnlocked ?? false

        guard iPosted && unlocked else { return mine }
        return all.filter { $0.moderationStatus == .approved }
    }

    func commentMediaSupported() async -> Bool { true }

    func myReflections(groupId: UUID) async throws -> [Reflection] {
        try await tick()
        return reflectionsStore.filter { $0.userId == me?.id }
    }

    func comments(reflectionId: UUID) async throws -> [Comment] {
        try await tick(); return commentsStore.filter { $0.reflectionId == reflectionId }
    }

    func addComment(reflectionId: UUID, content: String,
                    attachment: MediaAttachment?, transcript: String?,
                    language: String) async throws {
        try await tick()
        let mediaType: MediaType? = attachment.map {
            if case .voice = $0 { return .voice } else { return .photo }
        }
        commentsStore.append(Comment(id: UUID(),
                                     reflectionId: reflectionId,
                                     userId: me?.id ?? UUID(),
                                     content: content,
                                     createdAt: .now,
                                     mediaType: mediaType,
                                     transcript: transcript,
                                     language: language))
    }

    func reactions(reflectionId: UUID) async throws -> [Reaction] {
        try await tick(); return reactionsStore.filter { $0.reflectionId == reflectionId }
    }

    func addReaction(reflectionId: UUID, emoji: String) async throws -> Reaction {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        let r = Reaction(id: UUID(), reflectionId: reflectionId, userId: me.id,
                         emoji: emoji, createdAt: .now)
        reactionsStore.removeAll { $0.reflectionId == reflectionId && $0.userId == me.id && $0.emoji == emoji }
        reactionsStore.append(r)
        return r
    }

    func removeReaction(reflectionId: UUID, emoji: String) async throws {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        reactionsStore.removeAll { $0.reflectionId == reflectionId && $0.userId == me.id && $0.emoji == emoji }
    }

    func insights(groupId: UUID, type: InsightType?) async throws -> [AIInsight] {
        try await tick()
        guard let me else { throw DwellError.notAuthenticated }
        // Newest first, like the real query: callers take .first, and an
        // oldest-first mock hid a .last that picked stale rows on prod.
        return insightsStore.filter { insight in
            insight.groupId == groupId
            && (type == nil || insight.type == type)
            && (insight.targetUserId == nil || insight.targetUserId == me.id)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func leaderboard(groupId: UUID, weekStart: Date?) async throws -> [LeaderboardEntry] {
        try await tick(); return leaderboardStore
    }

    // MARK: - Realtime

    func dayInstanceUpdates(groupId: UUID) -> AsyncStream<DayInstance> {
        AsyncStream { continuation in
            dayContinuations[groupId] = continuation
            continuation.onTermination = { _ in }
        }
    }

    func membershipChanges(groupId: UUID) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func insightInserts(groupId: UUID) -> AsyncStream<AIInsight> {
        AsyncStream { continuation in
            insightContinuations[groupId] = continuation
            continuation.onTermination = { _ in }
        }
    }

    // MARK: - PlanService + passages

    func planImageURL(path: String) -> URL? { nil }

    func mediaURL(path: String) async throws -> URL {
        throw DwellError.notFound("Media")
    }

    func listPlans() async throws -> [PlanChallenge] { try await tick(); return Seed.plans }

    func getPlan(id: UUID) async throws -> PlanChallenge {
        try await tick()
        guard let p = Seed.plans.first(where: { $0.id == id }) else { throw DwellError.notFound("Plan") }
        return p
    }

    func getPlanDays(planId: UUID) async throws -> [PlanDay] {
        try await tick()
        return (Seed.anchoredDays + Seed.jamesDays).filter { $0.planChallengeId == planId }
    }

    func debugDay(groupId: UUID, action: String) async throws -> Int {
        try await tick()
        throw DwellError.notImplemented("Day control talks to the live backend; the mock's days are fixed per scenario.")
    }

    func passage(ref: String) async throws -> Passage {
        try await tick()
        guard let p = Seed.passages[ref] else { throw DwellError.notFound("Passage \(ref)") }
        return p
    }

    private func tick() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
    }
}
