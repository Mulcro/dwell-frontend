import SwiftUI

struct TodayView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var passage: Loadable<Passage> = .idle
    @State private var showReader = false

    private var group: DwellGroup? { session.group.value ?? nil }
    private var day: DayInstance? { session.currentDay }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let nudge = session.pendingNudge {
                    NudgeBanner(insight: nudge) {
                        Haptics.tap()
                        session.dismissNudge()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, Space.lg)
                }

                DayStrip(days: strip)
                    .padding(.top, Space.lg)

                passageCard
                    .padding(.top, Space.lg)

                statusPanel
                    .padding(.top, Space.lg)

                DwellButton(title: "Read, then reflect") {
                Haptics.tap()
                showReader = true
            }
                    .padding(.top, Space.lg)
                    .disabled(passage.value == nil)
                    .opacity(passage.value == nil ? 0.5 : 1)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await session.reload()
            await loadPassage()
        }
        .task(id: day?.passageRef) { await loadPassage() }
        .fullScreenCover(isPresented: $showReader) {
            if let passage = passage.value, let day {
                ReaderView(passage: passage, day: day, onClose: { showReader = false })
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(group?.name ?? "Your group")
                Text("Day \(day?.dayIndex ?? 1) · \(session.plan?.title.components(separatedBy: ":").first ?? "")")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
            }
            Spacer()
            Avatar(size: 38, tinted: false)
        }
        .padding(.top, Space.sm)
    }

    /// One cell per plan day, capped to a week's worth around today.
    private var strip: [DayStrip.Day] {
        guard let plan = session.plan, let day else { return [] }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (1...min(plan.dayCount, 7)).map { index in
            let state: DayStrip.Day.State
            if index < day.dayIndex { state = .done }
            else if index == day.dayIndex { state = .today }
            else { state = .upcoming }
            return DayStrip.Day(letter: letters[(index - 1) % 7], state: state)
        }
    }

    private var passageCard: some View {
        ZStack(alignment: .bottomLeading) {
            ImagePlaceholder("day image — quiet morning")

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Today's passage", color: t.textSecondary)
                switch passage {
                case .loaded(let p):
                    Text(p.reference)
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                    Text("\(p.readTimeLabel) · \(Seed.dayThemes[p.ref] ?? "")")
                        .font(.dwellBody)
                        .foregroundStyle(t.textSecondary)
                case .failed(let m):
                    Text("Couldn't load the passage")
                        .font(.dwellBodyMd).foregroundStyle(t.textPrimary)
                    Text(m).font(.dwellCaption).foregroundStyle(t.textSecondary)
                default:
                    Text(day?.passageRef ?? "—")
                        .font(.dwellTitle)
                        .foregroundStyle(t.textTertiary)
                    Text("Loading…").font(.dwellBody).foregroundStyle(t.textSecondary)
                }
            }
            .padding(Space.lg)
        }
        .frame(height: 230)
    }

    @ViewBuilder
    private var statusPanel: some View {
        let needed = session.requiredToUnlock
        let posted = session.postedCount

        Panel(accented: true) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text(day?.isUnlocked == true ? "The day is open" : "The day is closed")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Text("\(posted) / \(max(needed, 1))")
                        .font(.dwellTitleSm)
                        .foregroundStyle(t.accent)
                }
                SegmentedProgress(total: max(session.members.count, 1), filled: posted)
                Text(statusLine(posted: posted, needed: needed))
                    .font(.dwellFootnote)
                    .foregroundStyle(t.textSecondary)
                    .lineSpacing(3)
            }
        }
    }

    private func statusLine(posted: Int, needed: Int) -> String {
        if day?.isUnlocked == true { return "Everyone's words are open. Add yours." }
        if posted == 0 { return "Nobody's posted yet. Yours opens the door." }
        let remaining = max(needed - posted, 1)
        let who = session.members
            .filter { $0.userId != session.me?.id }
            .prefix(1)
            .map { session.name(for: $0.userId) }
            .joined()
        return "\(who) has posted. \(remaining) more \(remaining == 1 ? "unlocks" : "unlock") today for everyone."
    }

    private func loadPassage() async {
        guard let ref = day?.passageRef else { return }
        passage = .loading
        do { passage = .loaded(try await session.api.passage(ref: ref)) }
        catch { passage = .failed(error.localizedDescription) }
    }
}
