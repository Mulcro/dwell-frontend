import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var postedNames: [String] = []
    @State private var showReflect = false
    @State private var reflectStart: DayFlow.Stage = .reading
    @State private var showFeed = false
    @State private var showPulse = false
    @State private var nudging = false
    @State private var nudgedMarker: String?
    /// The recap being read full screen — weekly from its card, or the
    /// challenge recap from inside the celebration.
    @State private var openRecap: AIInsight?
    @State private var showComplete = false

    private var group: DwellGroup? { session.group.value ?? nil }
    private var state: HomeState { HomeState.resolve(session) }

    /// Cover art for the current plan, if the catalogue has any.
    private var planArt: URL? {
        guard let path = session.plan?.imagePath else { return nil }
        return session.api.planImageURL(path: path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(greeting)
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                        .padding(.top, Space.xxl)

                    WeekStrip(days: session.days)
                        .padding(.top, Space.xl)

                    nudgeBanner
                        .padding(.top, Space.lg)

                    pulseCard
                        .padding(.top, Space.lg)

                    weeklyRecapCard
                        .padding(.top, Space.lg)

                    body(for: state)
                        .padding(.top, Space.xl)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, TabBarMetrics.clearance)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: session.currentDay?.id) { await loadPosters() }
        .refreshable { await session.reload() }
        .fullScreenCover(isPresented: $showPulse) {
            if let pulse = session.visiblePulse {
                GroupPulseView(insight: pulse,
                               onClose: { showPulse = false },
                               onOpenFeed: {
                                   showPulse = false
                                   // Two full-screen covers can't swap in the
                                   // same frame — the second is dropped — so
                                   // the feed waits for the dismissal.
                                   Task {
                                       try? await Task.sleep(for: .milliseconds(350))
                                       showFeed = true
                                   }
                               })
            }
        }
        // DWELL_REFLECT=1 opens the composer straight away, for screenshots.
        .task {
            if ProcessInfo.processInfo.environment["DWELL_REFLECT"] == "1" { showReflect = true }
            if ProcessInfo.processInfo.environment["DWELL_FEED"] == "1" { showFeed = true }
            if ProcessInfo.processInfo.environment["DWELL_WHATSNEXT"] == "1" { startNewPlan() }
        }
        // Screenshot hooks, keyed to the insight because it loads after
        // boot: DWELL_COMPLETE=1 opens the celebration, DWELL_RECAP=1 the
        // recap itself.
        .task(id: session.endRecap) {
            if ProcessInfo.processInfo.environment["DWELL_COMPLETE"] == "1",
               session.endRecap != nil { showComplete = true }
            if ProcessInfo.processInfo.environment["DWELL_RECAP"] == "1",
               let recap = session.endRecap { openRecap = recap }
        }
        .fullScreenCover(isPresented: $showFeed) {
            FeedView(onClose: { showFeed = false })
        }
        .fullScreenCover(item: $openRecap) { recap in
            RecapView(insight: recap, onClose: { openRecap = nil })
        }
        .fullScreenCover(isPresented: $showComplete) {
            ChallengeCompleteView(onClose: { showComplete = false })
        }
        .fullScreenCover(isPresented: $showReflect) {
            DayFlow(startAt: reflectStart, onClose: {
                showReflect = false
                // The day's participation count and your own reflection both
                // change on post, and the router reads them.
                Task { await session.reload() }
            })
        }
    }

    // MARK: - States

    @ViewBuilder
    private func body(for state: HomeState) -> some View {
        switch state {
        case .readyToReflect:
            readyCard
            sealedNotice.padding(.top, Space.lg)

        case let .waitingOnGroup(_, posted, needed):
            waiting(posted: posted, needed: needed)

        case let .dayOpen(_, posted, total):
            open(posted: posted, total: total)

        case .completed:
            completedCard

        case .endedEarly:
            endedCard

        default:
            // forming / paused / completed / ended / noOpenDay / noGroup all
            // have a real headline and detail on HomeState; none of them
            // should offer "Start Reflection".
            genericCard
        }
    }

    /// Day open, nothing posted yet — the plan is the subject.
    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanCover(title: session.plan?.title ?? "Your plan", imageURL: planArt)
                .frame(height: 210)
                .clipped()

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text(group?.name ?? "Your group")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Text(dayLabel)
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.accent)
                }

                Text(session.plan?.title ?? "")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Skips the reading for someone who has already read today.
                Button {
                    reflectStart = .reflecting
                    showReflect = true
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(t.textSecondary)
                        Text("Add to today's reflection")
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                        Spacer()
                    }
                }
                .buttonStyle(PressScale())
                .padding(.top, Space.xs)

                PrimaryButton(title: "Start Reflection", accent: true) {
                    reflectStart = .reading
                    showReflect = true
                }
                .padding(.top, Space.md)
            }
            .padding(Space.lg)
        }
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private var sealedNotice: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(sealedTitle)
                .font(.dwellBodyMd)
                .foregroundStyle(t.textPrimary)
            Text(sealedDetail)
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    /// You posted; the group hasn't cleared the threshold.
    private func waiting(posted: Int, needed: Int) -> some View {
        VStack(spacing: Space.lg) {
            ReflectionCardStack(sealed: true)

            StatusPill(text: "\(posted) of \(session.members.count) in")

            MemberAvatarRow(members: avatarRow)

            // Not "sealed": you've posted, so nothing is being withheld from
            // you as a consequence of anything you did. The day simply hasn't
            // opened for the group yet, and until someone else posts there is
            // nothing behind the seal to withhold.
            Text(waitingTitle(posted: posted, needed: needed))
                .font(.dwellCardTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: nudgeTitle,
                          enabled: !hasNudgedToday && !nudging,
                          icon: hasNudgedToday ? "checkmark" : "bell") {
                Task { await nudge() }
            }

            yourReflectionRow
            nextOpensNote
        }
        .frame(maxWidth: .infinity)
    }

    /// Reads as waiting on the group, not as a lock on you.
    private func waitingTitle(posted: Int, needed: Int) -> String {
        let remaining = max(needed - posted, 0)
        if posted <= 1 {
            return remaining == 1
                ? "You're first in. One more post unlocks today's reflections."
                : "You're first in. \(remaining) more posts unlock today's reflections."
        }
        return remaining == 1
            ? "\(posted) of you are in. One more post unlocks today's reflections."
            : "\(posted) of you are in. \(remaining) more posts unlock today's reflections."
    }

    /// Threshold cleared — the day is readable.
    private func open(posted: Int, total: Int) -> some View {
        VStack(spacing: Space.lg) {
            // No card stack here. Sealed, it stands for reflections you can't
            // read yet; open, it's a skeleton of content that exists and is
            // one tap away — which reads as something failing to load.
            Text("Today's reflections are open")
                .font(.dwellCardTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)

            Text(openDetail(posted: posted, total: total))
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Read reflections", accent: true) { showFeed = true }

            yourReflectionRow
            nextOpensNote
        }
        .frame(maxWidth: .infinity)
    }

    /// The finished state on Home: the celebration (confetti and all) is a
    /// tap away, and so is starting the next thing — create or join.
    private var completedCard: some View {
        VStack(spacing: Space.lg) {
            PlanCoverThumb(title: session.plan?.title ?? "Your plan",
                           imageURL: planArt,
                           size: 132,
                           corner: Radius.lg)

            Text("You finished it")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)

            Text("You cleared the last day together.")
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)

            PrimaryButton(title: "See what these \(session.plan?.dayCount ?? session.days.count) days held",
                          accent: true) {
                showComplete = true
            }

            SecondaryButton(title: "Start a new plan", action: startNewPlan)
        }
        .frame(maxWidth: .infinity)
    }

    /// Abandoned or expired: no celebration, but the lighter recap
    /// (fallback_recap) and the way on are both still here.
    private var endedCard: some View {
        VStack(spacing: Space.lg) {
            PlanCoverThumb(title: session.plan?.title ?? "Your plan",
                           imageURL: planArt,
                           size: 132,
                           corner: Radius.lg)

            Text(state.headline)
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)

            Text(state.detail)
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let recap = session.endRecap {
                PrimaryButton(title: "Look back on it", accent: true) {
                    openRecap = recap
                }
            }

            SecondaryButton(title: "Start a new plan", action: startNewPlan)
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens What's Next: same crew, make a group, join with a code, and the
    /// archive.
    private func startNewPlan() {
        session.startingNewPlan = true
        session.onboardingStep = .startOrJoin
        session.resetOnboarding()
    }

    /// Entry to the Monday recap, styled like the pulse card.
    @ViewBuilder
    private var weeklyRecapCard: some View {
        if let recap = session.weeklyRecap {
            Button { openRecap = recap } label: {
                HStack(spacing: Space.md) {
                    ZStack {
                        Circle().fill(t.accent.opacity(0.15))
                        Image(systemName: "calendar")
                            .font(.system(size: 15))
                            .foregroundStyle(t.accent)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your week in review")
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                        Text(recap.payload(in: session.me?.preferredLanguage ?? "en")?.headline
                             ?? "What the week kept coming back to")
                            .font(.dwellSmall)
                            .foregroundStyle(t.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.textSecondary)
                }
                .padding(Space.lg)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            }
            .buttonStyle(PressScale())
        }
    }

    private var genericCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(state.headline)
                .font(.dwellCardTitleStrong)
                .foregroundStyle(t.textPrimary)
            Text(state.detail)
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)
            if let action = state.action {
                PrimaryButton(title: action, accent: true) { }
                    .padding(.top, Space.md)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var yourReflectionRow: some View {
        if let mine = session.myReflection {
            YourReflectionRow(postedAgo: relativeAge(mine.createdAt),
                              planTitle: session.plan?.title ?? "",
                              planArt: planArt,
                              isLate: mine.isLate,
                              onView: { showFeed = true })
        }
    }

    // MARK: - Copy

    private var greeting: String {
        guard let name = session.me?.name,
              !name.isEmpty,
              name.caseInsensitiveCompare("Friend") != .orderedSame,
              let first = name.split(separator: " ").first
        else { return "Hi there" }
        return "Hi, \(first)"
    }

    private var dayLabel: String {
        guard let day = session.currentDay?.dayIndex else { return "" }
        return "Day \(day) of \(session.plan?.dayCount ?? day)"
    }

    /// How many more approved reflections the day still needs. Zero means the
    /// group has already cleared it — the day is only locked for *you*,
    /// because you haven't posted.
    private var stillNeeded: Int {
        max(session.requiredToUnlock - session.postedCount, 0)
    }

    /// Deliberately not "Everyone's waiting on you" — the product never
    /// surfaces anyone as holding the group up, and an invitation reads better
    /// than an obligation.
    private var sealedTitle: String {
        stillNeeded == 0
            ? "Don't miss out!"
            : "Today's reflections are sealed"
    }

    /// Unlocking takes both halves: the group clears the threshold *and* you
    /// post. The old copy only ever described the first, so once the group had
    /// cleared it the sentence contradicted itself — "4 friends are in, it
    /// opens once 1 have responded".
    /// Entry point to the day's synthesis. Only exists once the day has
    /// opened — before that there is nothing to synthesise.
    @ViewBuilder
    private var pulseCard: some View {
        if let pulse = session.visiblePulse {
            Button { showPulse = true } label: {
                HStack(spacing: Space.md) {
                    ZStack {
                        Circle().fill(t.accent.opacity(0.15))
                        Image(systemName: "sparkle")
                            .font(.system(size: 15))
                            .foregroundStyle(t.accent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group Pulse")
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.accent)
                        Text(pulsePreview(pulse))
                            .font(.dwellBody)
                            .foregroundStyle(t.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                }
                .padding(Space.lg)
                .background(t.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(PressScale())
        }
    }

    /// The headline where one exists, otherwise the summary — both in the
    /// reader's language. Reading `content` directly showed the original to
    /// someone whose full pulse would have been translated.
    private func pulsePreview(_ pulse: AIInsight) -> String {
        let language = session.me?.preferredLanguage ?? "en"
        if let headline = pulse.payload(in: language)?.headline, !headline.isEmpty {
            return headline
        }
        return pulse.summary(in: language)
    }

    /// The companion's nudge, which until now was written to the database
    /// every time and shown nowhere.
    @ViewBuilder
    private var nudgeBanner: some View {
        if let nudge = session.visibleNudge {
            HStack(alignment: .top, spacing: Space.md) {
                ZStack {
                    Circle().fill(t.accent.opacity(0.15))
                    Image(systemName: "sparkle")
                        .font(.system(size: 14))
                        .foregroundStyle(t.accent)
                }
                .frame(width: 30, height: 30)

                Text(nudge.content)
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.small)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button { session.dismissNudge() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.textSecondary)
                }
                .buttonStyle(PressScale())
            }
            .padding(Space.lg)
            .background(t.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Quiet line telling you when the next reading lands.
    ///
    /// Shown in the group's timezone, not the reader's, so everyone in the
    /// crew sees the same moment — a group spanning timezones would otherwise
    /// each be told a different answer to the same question.
    @ViewBuilder
    private var nextOpensNote: some View {
        if session.nextDayIsDue {
            HStack(spacing: Space.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                Text("The next reading is opening shortly.")
                    .font(.dwellCaption)
            }
            .foregroundStyle(t.textSecondary)
            .padding(.top, Space.sm)
        } else if let label = session.nextDayOpensLabel {
            HStack(spacing: Space.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                Text("Next reading opens \(label)")
                    .font(.dwellCaption)
            }
            .foregroundStyle(t.textSecondary)
            .padding(.top, Space.sm)
        }
    }

    private var sealedDetail: String {
        let posted = session.postedCount

        guard stillNeeded > 0 else {
            return "Today's reflections are unlocked. Add yours to read what everyone else wrote."
        }

        guard posted > 0 else {
            return stillNeeded == 1
                ? "Nobody's posted yet. One post unlocks today's reflections, and it could be yours."
                : "Nobody's posted yet. They unlock once \(stillNeeded) of you have posted. Yours could be the first."
        }

        let who = posted == 1 ? "1 friend is in" : "\(posted) friends are in"
        return stillNeeded == 1
            ? "\(who). One more post unlocks today's reflections, and yours could be the one."
            : "\(who). \(stillNeeded) more posts unlock today's reflections, and yours could be one of them."
    }

    private func openDetail(posted: Int, total: Int) -> String {
        let remaining = max(total - posted, 0)
        let who = postedNames.isEmpty ? "You're" : "\(listed(postedNames)) are"
        guard remaining > 0 else { return "\(who) all in for today." }
        return "\(who) in. \(remaining) more can still add theirs today."
    }

    /// Names two people and counts the rest.
    ///
    /// A full list grew with the group and pushed the sentence onto three
    /// lines at seven members — and the names after the first couple carry no
    /// information the count doesn't.
    private func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return "You"
        case 1: return "\(names[0]) and you"
        case 2: return "\(names[0]), \(names[1]) and you"
        default:
            let others = names.count - 2
            return "\(names[0]), \(names[1]) and \(others) other\(others == 1 ? "" : "s")"
        }
    }

    /// Avatars in stable member order.
    ///
    /// The tick can only be shown for people we can *prove* posted. Before the
    /// day unlocks RLS hides everyone else's reflection rows, and
    /// `participation_count` is a bare number with no identities — so marking
    /// specific friends as done would be a guess. Only your own tick is real
    /// until the day opens; the count in the pill carries the rest.
    private var avatarRow: [(name: String, url: URL?, posted: Bool)] {
        session.members.map { member in
            let name = session.memberProfiles[member.userId]?.name ?? "Member"
            let isMe = member.userId == session.me?.id
            let posted = isMe
                ? session.myReflection?.moderationStatus == .approved
                : postedNames.contains(where: { name.hasPrefix($0) })
            return (name, session.avatarURL(for: member.userId), posted)
        }
    }

    private func relativeAge(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 3_600 { return "\(max(Int(seconds / 60), 1)) minutes ago" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        let days = Int(seconds / 86_400)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    // MARK: - Data

    /// Who posted — only knowable once the day has unlocked.
    private func loadPosters() async {
        guard let day = session.currentDay, day.isUnlocked else {
            postedNames = []
            return
        }
        let rows = (try? await session.api.reflections(dayInstanceId: day.id)) ?? []
        postedNames = rows
            .filter { $0.userId != session.me?.id }
            .compactMap { session.memberProfiles[$0.userId]?.name.split(separator: " ").first.map(String.init) }
    }

    /// One nudge per day. Being able to send it repeatedly turns a gentle
    /// reminder into pestering, which is the opposite of what it is for.
    /// The marker names the account as well as the day, so one member's
    /// nudge doesn't disable the button for a group-mate who signs in on the
    /// same device.
    private var nudgeMarker: String? {
        guard let dayId = session.currentDay?.id, let me = session.me?.id else { return nil }
        return "\(me.uuidString):\(dayId.uuidString)"
    }

    private var hasNudgedToday: Bool {
        guard let marker = nudgeMarker else { return false }
        if nudgedMarker == marker { return true }
        return UserDefaults.standard.string(forKey: Self.nudgeKey) == marker
    }

    private var nudgeTitle: String {
        if nudging { return "Nudging…" }
        return hasNudgedToday ? "You've nudged the group today"
                              : "Send the group a gentle nudge"
    }

    private static let nudgeKey = "home.lastNudgedDay"

    private func nudge() async {
        guard !hasNudgedToday, let marker = nudgeMarker else { return }
        nudging = true
        defer { nudging = false }
        Haptics.tap()
        // No nudge endpoint exists. The cron writes ai_insights rows. Tracked
        // in the backend request doc.
        try? await Task.sleep(for: .milliseconds(600))
        nudgedMarker = marker
        // Survives a relaunch, so the limit isn't reset by closing the app.
        UserDefaults.standard.set(marker, forKey: Self.nudgeKey)
    }
}
