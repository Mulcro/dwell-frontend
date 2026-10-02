import SwiftUI

/// Plan Overview — the Reading tab's root.
///
/// Day selection is driven by real `day_instances`, so a day the rhythm never
/// scheduled simply isn't there. Days ahead of the group are visible but not
/// openable: pacing is one day per 24h and the next only opens once the
/// current one clears (MVP §4.5).
struct ReadingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var planDays: Loadable<[PlanDay]> = .idle
    @State private var selectedIndex: Int?
    @State private var reading: ReadingItem?

    private var plan: PlanChallenge? { session.plan }

    /// Cover art for the current plan, if the catalogue has any.
    private var planArt: URL? {
        guard let path = session.plan?.imagePath else { return nil }
        return session.api.planImageURL(path: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            LoadableView(state: planDays, retry: { Task { await load() } }) { days in
                content(planDays: days)
            }
        }
        // Keyed to the plan: bootstrap may not have resolved it when this
        // first appears, and an unkeyed task would never retry.
        .task(id: session.plan?.id) { await load() }
        // A tapped day otherwise outlives the day it was tapped on: once a new
        // day opens, the screen stayed on yesterday until the tab was rebuilt.
        .onChange(of: session.currentDay?.id) { _, _ in selectedIndex = nil }
        // DWELL_READ=devotional|passage opens the reader straight away, for
        // screenshots.
        .task(id: planDays.value?.count) {
            guard reading == nil,
                  let want = ProcessInfo.processInfo.environment["DWELL_READ"],
                  let days = planDays.value else { return }
            let index = session.currentDay?.dayIndex ?? 1
            if want == "passage", let ref = days.first(where: { $0.dayIndex == index })?.passageRef {
                reading = .passage(dayIndex: index, usfm: ref)
            } else if want == "devotional" {
                reading = .devotional(dayIndex: index)
            }
        }
        .fullScreenCover(item: $reading) { item in
            ReadingPager(item: item, onClose: { reading = nil })
        }
    }

    private var header: some View {
        HStack {
            Spacer().frame(width: 44)
            Text(plan?.title ?? "Reading")
                .font(.dwellBodyMd)
                .foregroundStyle(t.textPrimary)
                .lineLimit(1)
            Spacer()
            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(t.surfaceRaised))
            }
            .buttonStyle(PressScale())
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    private func content(planDays days: [PlanDay]) -> some View {
        let index = selectedIndex ?? session.currentDay?.dayIndex ?? 1
        let today = days.first { $0.dayIndex == index }

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PlanCover(title: plan?.title ?? "", imageURL: planArt)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

                daySelector(days: days, selected: index)

                HStack {
                    Text("Day \(index) of \(plan?.dayCount ?? days.count)")
                        .font(.dwellCardTitleStrong)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    if isComplete(index) {
                        Label("Done", systemImage: "checkmark")
                            .font(.dwellSmallMd)
                            .foregroundStyle(t.success)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.sm)
                            .overlay(Capsule().strokeBorder(t.success.opacity(0.4), lineWidth: 1))
                    } else if let chip = paceChip {
                        Text(chip)
                            .font(.dwellSmallMd)
                            .foregroundStyle(t.textPrimary)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.sm)
                            .overlay(Capsule().strokeBorder(t.border, lineWidth: 1))
                    }
                }

                VStack(spacing: 0) {
                    itemRow(.devotional(dayIndex: index), title: "Devotional")
                    Divider().overlay(t.border)
                    if let ref = today?.passageRef {
                        itemRow(.passage(dayIndex: index, usfm: ref),
                                title: YouVersionReader.reference(fromUSFM: ref)?.display ?? ref)
                    }
                }

                Spacer(minLength: Space.xl)

                PrimaryButton(title: isOpenable(index) ? "Start Reading" : "Not open yet",
                              enabled: isOpenable(index)) {
                    reading = .devotional(dayIndex: index)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, TabBarMetrics.clearance)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await session.reload()
            await load()
        }
    }

    private func daySelector(days: [PlanDay], selected: Int) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.md) {
                ForEach(days, id: \.dayIndex) { day in
                    let isSelected = day.dayIndex == selected
                    VStack(spacing: Space.sm) {
                        Text("\(day.dayIndex)")
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                        Text(dateLabel(for: day.dayIndex))
                            .font(.dwellCaption)
                            .foregroundStyle(isSelected ? t.onInk : t.textSecondary)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 3)
                            .background(isSelected ? t.ink : .clear)
                            .clipShape(Capsule())
                    }
                    .frame(width: 84)
                    .padding(.vertical, Space.md)
                    .background(isSelected ? t.background : t.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(isSelected ? t.ink : .clear, lineWidth: 2)
                    )
                    // A badge rather than replacing the date, so the selected
                    // day doesn't lose its label to show it's done.
                    .overlay(alignment: .topTrailing) {
                        if isComplete(day.dayIndex) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(t.success)
                                .background(Circle().fill(t.background).padding(1))
                                .padding(5)
                        }
                    }
                    .onTapGesture { selectedIndex = day.dayIndex }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// A day counts as done once your reflection on it is approved.
    ///
    /// The two rows aren't tracked separately — nothing records "read the
    /// devotional" on its own, and posting a reflection is the only evidence
    /// the day was actually done. So they tick together rather than inventing
    /// per-row state the backend doesn't have.
    private func isComplete(_ dayIndex: Int) -> Bool {
        // `session.days` are the group's day *instances*; the view's `days`
        // are the plan's catalogue entries and carry no identity to match on.
        guard let day = session.days.first(where: { $0.dayIndex == dayIndex }) else { return false }
        return session.completedDayIds.contains(day.id)
    }

    private func itemRow(_ item: ReadingItem, title: String) -> some View {
        Button { reading = item } label: {
            HStack(spacing: Space.md) {
                Image(systemName: isComplete(item.dayIndex)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22,
                                  weight: isComplete(item.dayIndex) ? .regular : .light))
                    .foregroundStyle(isComplete(item.dayIndex) ? t.success : t.border)
                Text(title)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
            }
            .padding(.vertical, Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(!isOpenable(item.dayIndex))
        .opacity(isOpenable(item.dayIndex) ? 1 : 0.4)
    }

    /// A day is readable once it has actually opened for the group.
    private func isOpenable(_ dayIndex: Int) -> Bool {
        session.days.contains { $0.dayIndex == dayIndex }
    }

    private func dateLabel(for dayIndex: Int) -> String {
        guard let day = session.days.first(where: { $0.dayIndex == dayIndex }) else { return "—" }
        return day.date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "On Track!" only when the group has actually cleared every day so far.
    private var paceChip: String? {
        let opened = session.days.count
        guard opened > 0 else { return nil }
        let cleared = session.days.filter { $0.status == .complete || $0.status == .thresholdMet }.count
        return cleared >= opened - 1 ? "On Track!" : nil
    }

    private func load() async {
        guard let plan else {
            // Still booting — stay in the loading state rather than failing.
            planDays = .loading
            return
        }
        planDays = .loading
        do { planDays = .loaded(try await session.api.getPlanDays(planId: plan.id)) }
        catch { planDays = .failed(error.localizedDescription) }
    }
}

/// One readable thing within a day. The design paginates these as "1 of 2".
enum ReadingItem: Identifiable, Hashable {
    case devotional(dayIndex: Int)
    case passage(dayIndex: Int, usfm: String)

    var id: String {
        switch self {
        case .devotional(let d):      return "devotional-\(d)"
        case .passage(let d, let u):  return "passage-\(d)-\(u)"
        }
    }

    var dayIndex: Int {
        switch self {
        case .devotional(let d):     return d
        case .passage(let d, _):     return d
        }
    }
}
