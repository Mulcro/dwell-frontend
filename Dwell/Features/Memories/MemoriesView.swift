import SwiftUI

/// Your own history: a timeline of past reflections, or a calendar of the days
/// you showed up.
///
/// Both modes are built from *your* reflections, which RLS always lets you
/// read whatever the day's state — so a sealed day still appears here if you
/// posted on it.
struct MemoriesView: View {
    private enum Mode { case timeline, calendar }

    /// Where "Keep Reflecting" on the first-run screen sends you.
    var onKeepReflecting: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    // DWELL_MEMORIES=calendar opens the grid straight away, for screenshots.
    @State private var mode: Mode =
        ProcessInfo.processInfo.environment["DWELL_MEMORIES"] == "calendar" ? .calendar : .timeline
    @State private var opened: Reflection?
    @State private var pastPulses: [AIInsight] = []
    @State private var challengePhotos: [URL] = []
    @State private var challengePhotosSignedAt: Date?

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.35)

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    Group {
                        // No reflections yet means no memories in either mode,
                        // so both toggles land on the same first-run screen.
                        if entries.isEmpty {
                            MemoriesEmptyState(onKeepReflecting: onKeepReflecting)
                                .padding(.top, Space.xxl)
                        } else {
                            switch mode {
                            case .timeline: timeline
                            case .calendar: calendar
                            }
                        }
                    }
                    .padding(.bottom, TabBarMetrics.clearance)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await session.reload()
                    await loadPulses()
                    await loadChallengePhotos(force: true)
                }
            }
        }
        .dwellThemed()
        .task { await loadPulses() }
        .task(id: session.myReflections.count) { await loadChallengePhotos(force: true) }
        // Signed URLs expire after an hour. Keying the load to the reflection
        // count alone meant a tab left open — or refreshed without posting —
        // kept URLs until they died and the tiles went blank.
        .onAppear { Task { await loadChallengePhotos() } }
        .sheet(item: $opened) { reflection in
            MemoryDetailView(reflection: reflection) { opened = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Memories")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
            HStack(spacing: Space.sm) {
                modeButton(.timeline, icon: "clock.arrow.circlepath")
                modeButton(.calendar, icon: "calendar")
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    private func modeButton(_ target: Mode, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = target }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(mode == target ? t.onInk : t.textPrimary)
                .frame(width: 56, height: 44)
                .background(mode == target ? t.ink : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(PressScale())
    }

    // MARK: - Timeline

    private var entries: [Reflection] { session.myReflections.reversed() }

    /// Old enough to be worth being reminded of: a day, per the design's
    /// split between the first-run screen and the populated one. The comp
    /// reaches back across challenges; there is only this one to reach into.
    private var resurfaced: [Reflection] {
        session.myReflections.filter {
            (Calendar.current.dateComponents([.day], from: $0.createdAt, to: .now).day ?? 0) >= 1
        }.prefix(3).reversed()
    }

    private var planArt: URL? {
        guard let path = session.plan?.imagePath else { return nil }
        return session.api.planImageURL(path: path)
    }

    @ViewBuilder
    private var timeline: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if !resurfaced.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.lg) {
                        ForEach(Array(resurfaced.enumerated()), id: \.element.id) { index, reflection in
                            Button { opened = reflection } label: {
                                OnThisDayCard(reflection: reflection,
                                              kind: index == 0 ? .onThisDay : .noteForLater,
                                              planArt: planArt)
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                }
                .scrollIndicators(.hidden)
            }

            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Your reflections")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                ForEach(entries) { reflection in
                    Button { opened = reflection } label: {
                        MemoryCard(reflection: reflection,
                                   dayIndex: dayIndex(for: reflection),
                                   planTitle: session.plan?.title ?? "")
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(.horizontal, Space.gutter)

            pulseHistory
                .padding(.horizontal, Space.gutter)

            pastChallenges
                .padding(.horizontal, Space.gutter)
        }
        .padding(.top, Space.lg)
    }

    // MARK: - Past challenges

    /// Challenges this group has finished.
    ///
    /// Nothing is archived yet — `myGroup()` returns one group and a finished
    /// challenge leaves no record (item 46a in Notion). So this lists the
    /// current challenge only once it has actually ended, which is the only
    /// honest source available. It fills out properly the moment an archive
    /// endpoint exists.
    @ViewBuilder
    private var pastChallenges: some View {
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Past Challenges")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)

                ForEach(finished) { challenge in
                    PastChallengeRow(challenge: challenge)
                }
            }
        }
    }

    private var finished: [PastChallengeRow.Challenge] {
        guard let g = session.group.value ?? nil,
              let plan = session.plan,
              g.challengeStatus.isEnded else { return [] }
        return [.init(id: g.id,
                      title: plan.title,
                      ended: session.days.map(\.date).max() ?? .now,
                      mediaURLs: challengePhotos,
                      coverArt: planArt,
                      // The badge counts photographs, not reflections — it sits
                      // on a stack of pictures, so counting posts would promise
                      // images that aren't there.
                      totalCount: photoReflectionCount)]
    }

    private var photoReflectionCount: Int {
        session.myReflections.filter { $0.mediaType == .photo && $0.mediaPath != nil }.count
    }

    /// Signs the first few photographs for the fanned stack.
    ///
    /// Re-signed well before the hour is up, so a stack that has been on
    /// screen a while doesn't quietly turn into empty tiles.
    private func loadChallengePhotos(force: Bool = false) async {
        if !force, let signedAt = challengePhotosSignedAt,
           Date.now.timeIntervalSince(signedAt) < 45 * 60 { return }
        let paths = session.myReflections
            .filter { $0.mediaType == .photo }
            .compactMap(\.mediaPath)
            .suffix(4)
        var urls: [URL] = []
        for path in paths {
            if let url = try? await session.api.mediaURL(path: path) { urls.append(url) }
        }
        challengePhotos = urls
        challengePhotosSignedAt = .now
    }

    // MARK: - What the group noticed

    @ViewBuilder
    private var pulseHistory: some View {
        if !pastPulses.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("What the group noticed")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)

                ForEach(pastPulses) { pulse in
                    HStack(alignment: .top, spacing: Space.md) {
                        EagleAvatar(size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            if let index = pulseDayIndex(pulse) {
                                Text("Day \(index)")
                                    .font(.dwellCaption)
                                    .foregroundStyle(t.textSecondary)
                            }
                            Text(pulseLine(pulse))
                                .font(.dwellSmall)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.lg)
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
            }
        }
    }

    /// The headline where the backend wrote one, the opening sentence of the
    /// summary otherwise — the same rule the pulse screen itself uses.
    private func pulseLine(_ pulse: AIInsight) -> String {
        let language = session.me?.preferredLanguage ?? "en"
        if let headline = pulse.payload(in: language)?.headline, !headline.isEmpty {
            return headline
        }
        let text = pulse.summary(in: language).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stop = text.firstIndex(where: { ".!?".contains($0) }) else { return text }
        return String(text[...stop])
    }

    private func pulseDayIndex(_ pulse: AIInsight) -> Int? {
        session.days.first { $0.id == pulse.dayInstanceId }?.dayIndex
    }

    private func loadPulses() async {
        guard let g = session.group.value ?? nil else { return }
        let all = (try? await session.api.insights(groupId: g.id, type: .groupPulse)) ?? []
        pastPulses = all.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Calendar

    /// Months are derived from the day instances rather than the calendar, so
    /// a challenge that hasn't started doesn't draw an empty grid.
    private var months: [(label: String, leading: Int, dates: [Date])] {
        let days = session.days
        guard !days.isEmpty else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        let grouped = Dictionary(grouping: days) { day -> DateComponents in
            cal.dateComponents([.year, .month], from: day.date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"

        return grouped.keys.sorted {
            ($0.year ?? 0, $0.month ?? 0) > ($1.year ?? 0, $1.month ?? 0)
        }.compactMap { key in
            guard let first = cal.date(from: key),
                  let range = cal.range(of: .day, in: .month, for: first) else { return nil }
            let dates = range.compactMap {
                cal.date(byAdding: .day, value: $0 - 1, to: first)
            }
            // Blank cells before the 1st, so each date lands under its
            // weekday and the grid reads as a real month.
            let leading = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
            return (formatter.string(from: first), leading, dates)
        }
    }

    @ViewBuilder
    private var calendar: some View {
        if months.isEmpty {
            EmptyStateView(title: "No days yet",
                           message: "Once the challenge starts, every day you post shows up here.")
                .padding(.top, Space.xxxl)
        } else {
            VStack(alignment: .leading, spacing: Space.xxl) {
                ForEach(months, id: \.label) { month in
                    VStack(alignment: .leading, spacing: Space.lg) {
                        Text(month.label)
                            .font(.dwellCardTitleStrong)
                            .foregroundStyle(t.textPrimary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm),
                                                 count: 7),
                                  spacing: Space.sm) {
                            ForEach(0..<month.leading, id: \.self) { _ in
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                            ForEach(month.dates, id: \.self) { date in
                                dayCell(date)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.lg)
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let reflection = reflection(on: date)
        let number = Calendar.current.component(.day, from: date)
        return Button {
            if let reflection { opened = reflection }
        } label: {
            CalendarDayCell(reflection: reflection, number: number,
                            isToday: Calendar.current.isDateInToday(date))
        }
        .buttonStyle(PressScale())
        .disabled(reflection == nil)
    }

    /// Matched through the **day instance**, not the reflection's timestamp.
    ///
    /// A late post carries a `created_at` after midnight — post at 00:30 on
    /// the 2nd for the 1st's reading and matching on the timestamp lights the
    /// wrong cell, and leaves the day you actually read blank. The day
    /// instance's own `date` is what the reflection belongs to, which is also
    /// what `is_late` is measured against.
    private func reflection(on date: Date) -> Reflection? {
        let cal = Calendar.current
        guard let day = session.days.first(where: { cal.isDate($0.date, inSameDayAs: date) })
        else { return nil }
        return session.myReflections.first { $0.dayInstanceId == day.id }
    }

    private func dayIndex(for reflection: Reflection) -> Int? {
        session.days.first { $0.id == reflection.dayInstanceId }?.dayIndex
    }
}

/// One square in the calendar grid (`Memories · Calendar`, `3161:26303`).
///
/// A day whose reflection carries a photo shows the photograph itself; any
/// other posted day is an ink square with the date, and a day without a
/// reflection stays a quiet number. Today carries an accent ring even before
/// you post, so the grid never looks stuck on yesterday. Each cell signs its
/// own URL on appear, the same pattern as `OnThisDayCard`, so a grid left on
/// screen past the hour re-signs as cells are recreated rather than going
/// blank at once.
private struct CalendarDayCell: View {
    let reflection: Reflection?
    let number: Int
    var isToday: Bool = false

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var photoURL: URL?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(reflection == nil ? t.surfaceRaised : t.ink)
            if photoURL == nil {
                Text("\(number)")
                    .font(.dwellSmallMd)
                    .foregroundStyle(reflection == nil ? t.textSecondary.opacity(0.6) : t.onInk)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
            }
        }
        .clipShape(shape)
        .overlay {
            if isToday {
                shape.strokeBorder(t.accent, lineWidth: 2)
            }
        }
        .task(id: reflection?.id) { await loadPhoto() }
    }

    private func loadPhoto() async {
        guard let reflection, reflection.mediaType == .photo,
              let path = reflection.mediaPath else {
            photoURL = nil
            return
        }
        photoURL = try? await session.api.mediaURL(path: path)
    }
}
