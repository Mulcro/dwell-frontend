import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var postedNames: [String] = []
    @State private var showReflect = false
    @State private var nudging = false

    private var group: DwellGroup? { session.group.value ?? nil }
    private var state: HomeState { HomeState.resolve(session) }

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
            PlanCover(title: session.plan?.title ?? "Your plan")
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

                HStack(spacing: Space.sm) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(t.textSecondary)
                    Text("Add to today's reflection")
                        .font(.dwellBody)
                        .foregroundStyle(t.textSecondary)
                }
                .padding(.top, Space.xs)

                PrimaryButton(title: "Start Reflection", accent: true) {
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
            Text("Today's reflections are sealed")
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
        }
        .frame(maxWidth: .infinity)
    }

    /// Threshold cleared — the day is readable.
    private func open(posted: Int, total: Int) -> some View {
        VStack(spacing: Space.lg) {
            ReflectionCardStack(sealed: false)

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

            PrimaryButton(title: "Read reflections", accent: true) { }

            yourReflectionRow
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
                              isLate: mine.isLate)
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

    private var sealedDetail: String {
        let posted = session.postedCount
        let needed = max(session.requiredToUnlock, 1)
        guard posted > 0 else {
            return "Nobody's posted yet. It opens once \(needed) have responded — yours could be the first."
        }
        return "\(posted) \(posted == 1 ? "friend is" : "friends are") in. It opens once \(needed) have responded. Yours could be the one."
    }

    private func openDetail(posted: Int, total: Int) -> String {
        let remaining = max(total - posted, 0)
        let who = postedNames.isEmpty ? "You're" : "\(listed(postedNames)) are"
        guard remaining > 0 else { return "\(who) all in for today." }
        return "\(who) in. \(remaining) more can still add theirs today."
    }

    private func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return "You"
        case 1: return "\(names[0]) and you"
        default: return names.dropLast().joined(separator: ", ") + ", \(names[names.count - 1]) and you"
        }
    }

    /// Avatars in stable member order.
    ///
    /// The tick can only be shown for people we can *prove* posted. Before the
    /// day unlocks RLS hides everyone else's reflection rows, and
    /// `participation_count` is a bare number with no identities — so marking
    /// specific friends as done would be a guess. Only your own tick is real
    /// until the day opens; the count in the pill carries the rest.
    private var avatarRow: [(name: String, posted: Bool)] {
        session.members.map { member in
            let name = session.memberProfiles[member.userId]?.name ?? "Member"
            let isMe = member.userId == session.me?.id
            let posted = isMe
                ? session.myReflection?.moderationStatus == .approved
                : postedNames.contains(where: { name.hasPrefix($0) })
            return (name, posted)
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
