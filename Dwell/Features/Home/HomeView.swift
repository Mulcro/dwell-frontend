import SwiftUI

/// Placeholder for the daily loop.
///
/// The redesign covers onboarding; Today / Reader / Compose / Feed and the
/// rest haven't been redrawn yet. The previous versions are in
/// Archive/LegacyUI and will be rebuilt against the new design system once
/// those comps land — this stands in so the app has somewhere to arrive.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                Text(greeting)
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.xxl)

                weekStrip.padding(.top, Space.xl)

                planCard.padding(.top, Space.xl)

                Spacer()

                Text("The daily loop is still being designed. Onboarding is complete and wired to the API layer.")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                SecondaryButton(title: "Sign out") {
                    Task {
                        try? await session.api.signOut()
                        session.finishOnboarding()
                        await session.bootstrap()
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    /// The auth trigger falls back to 'Friend' when a provider sends no name,
    /// so "Hi, Friend" is possible — drop to something warmer in that case.
    private var greeting: String {
        guard let name = session.me?.name,
              !name.isEmpty,
              name.caseInsensitiveCompare("Friend") != .orderedSame,
              let first = name.split(separator: " ").first
        else { return "Hi there" }
        return "Hi, \(first)"
    }

    /// The current calendar week, Sunday first, as the design draws it.
    ///
    /// A cell is filled when a day of the plan actually opened on that date
    /// and cleared; outlined when it's today; muted otherwise. Nothing here is
    /// assumed from the plan's day index — a `weekdays` or `custom` rhythm
    /// simply has no row on the days it skips.
    private var weekStrip: some View {
        HStack(spacing: Space.sm) {
            ForEach(weekDates, id: \.self) { date in
                let day = dayInstance(on: date)
                let isToday = calendar.isDateInToday(date)
                let cleared = day.map { $0.status == .complete || $0.status == .thresholdMet } ?? false

                VStack(spacing: 4) {
                    Text(letter(for: date))
                        .font(.dwellSmallMd)
                        .foregroundStyle(cleared ? t.onInk : (isToday ? t.textPrimary : t.textSecondary))
                    if day != nil {
                        Circle()
                            .fill(cleared ? t.onInk : t.textTertiary)
                            .frame(width: 4, height: 4)
                    } else {
                        Circle().fill(.clear).frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(cleared ? t.ink : t.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(isToday && !cleared ? t.ink : .clear, lineWidth: 2)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: date, day: day, isToday: isToday, cleared: cleared))
            }
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1   // Sunday, matching the design's S M T W T F S
        return calendar
    }

    /// The seven dates of the week `today` falls in.
    private var weekDates: [Date] {
        let today = Date()
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayInstance(on date: Date) -> DayInstance? {
        session.days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func letter(for date: Date) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols[calendar.component(.weekday, from: date) - 1]
    }

    private func accessibilityLabel(for date: Date, day: DayInstance?,
                                    isToday: Bool, cleared: Bool) -> String {
        let name = date.formatted(.dateTime.weekday(.wide))
        if isToday { return "\(name), today\(cleared ? ", complete" : "")" }
        guard day != nil else { return "\(name), no reading" }
        return "\(name), \(cleared ? "complete" : "not complete")"
    }

    private var state: HomeState { HomeState.resolve(session) }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(group?.name ?? "Dwell")
                .font(.dwellCardTitleStrong)
                .foregroundStyle(t.textPrimary)

            Text(subtitle)
                .font(.dwellSmall)
                .foregroundStyle(t.textSecondary)

            Text(state.detail)
                .font(.dwellBody)
                .lineSpacing(LineSpacing.body)
                .foregroundStyle(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)

            if let action = state.action {
                PrimaryButton(title: action) { }
                    .padding(.top, Space.md)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    /// "Day 3 · When Life Gets Hard" when there's a day; just the plan when
    /// there isn't, rather than inventing "Day 1".
    private var subtitle: String {
        let plan = session.plan?.title
        if let day = session.currentDay?.dayIndex, let plan {
            return "Day \(day) · \(plan)"
        }
        return plan ?? state.headline
    }
}
