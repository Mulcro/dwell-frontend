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
        }
        .fullScreenCover(isPresented: $showFeed) {
            FeedView(onClose: { showFeed = false })
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

            StatusPill(text: "\(posted) of \(session.members.count) in · opens at \(needed)")

            MemberAvatarRow(members: avatarRow)

            Text("Sealed until half the crew is here")
                .font(.dwellCardTitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: nudging ? "Nudging…" : "Send the group a gentle nudge",
                          icon: "bell") {
                Task { await nudge() }
            }

            yourReflectionRow
            statsStrip
            nextOpensNote
        }
        .frame(maxWidth: .infinity)
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
            statsStrip
            nextOpensNote
        }
        .frame(maxWidth: .infinity)
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
    /// Three readings of how the challenge is going — deliberately not a
    /// scoreboard.
    ///
    /// The team chose a recap-style leaderboard over a live one precisely to
    /// keep competition out of the daily loop, so `participation_score` is
    /// saved for the weekly recap rather than shown on Home every day. These
    /// are the group's progress, your own rhythm, and what the writing has
    /// actually been about.
    private var statsStrip: some View {
        HStack(spacing: Space.md) {
            statTile("\(daysCleared)/\(session.days.count)", "Days together")
            statTile("\(session.currentStreak)", "Day streak")
            statTile(mood ?? "\(session.myReflections.count)",
                     mood == nil ? "Reflections" : "Your tone")
        }
    }

    /// Days the group got over the line, not days you personally posted —
    /// the product is about the crew arriving, and nobody is singled out.
    private var daysCleared: Int {
        session.days.filter { $0.status == .thresholdMet || $0.status == .complete }.count
    }

    /// The most frequent `sentiment_tag` across your own reflections.
    ///
    /// The backend has tagged every reflection since the start and nothing has
    /// ever displayed one. It is the most interesting number on this screen
    /// precisely because it isn't a number — "Hopeful" says more about a week
    /// of reading than a count of posts does.
    private var mood: String? {
        let tags = session.myReflections.compactMap(\.sentimentTag).filter { !$0.isEmpty }
        guard tags.count >= 2 else { return nil }
        let counts = Dictionary(tags.map { ($0, 1) }, uniquingKeysWith: +)
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return top.prefix(1).uppercased() + top.dropFirst()
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

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
                        Text(pulse.content)
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
        if let label = session.nextDayOpensLabel {
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
            return "The day is open. Add yours to read what everyone else wrote."
        }

        guard posted > 0 else {
            return stillNeeded == 1
                ? "Nobody's posted yet. One reflection opens the day — it could be yours."
                : "Nobody's posted yet. It opens once \(stillNeeded) of you have — yours could be the first."
        }

        let who = posted == 1 ? "1 friend is in" : "\(posted) friends are in"
        return stillNeeded == 1
            ? "\(who). One more opens the day — yours could be the one."
            : "\(who). \(stillNeeded) more open the day — yours could be one of them."
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

    private func nudge() async {
        nudging = true
        defer { nudging = false }
        Haptics.tap()
        // No nudge endpoint exists — the cron writes ai_insights rows. Tracked
        // in the backend request doc.
        try? await Task.sleep(for: .milliseconds(600))
    }
}
