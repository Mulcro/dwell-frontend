import SwiftUI

/// The seven day cells under the greeting.
///
/// Driven by real `day_instances`, not by the plan's day index: a `weekdays`
/// or `custom` rhythm simply has no row on the days it skips, and those cells
/// stay blank rather than claiming a miss.
struct WeekStrip: View {
    let days: [DayInstance]
    var reference: Date = .now
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(weekDates, id: \.self) { date in
                cell(for: date)
            }
        }
    }

    private func cell(for date: Date) -> some View {
        let day = dayInstance(on: date)
        let isToday = calendar.isDateInToday(date)
        let cleared = day.map { $0.status == .complete || $0.status == .thresholdMet } ?? false
        let missed = day?.status == .missed

        return VStack(spacing: 6) {
            Text(letter(for: date))
                .font(.dwellSmallMd)
                .foregroundStyle(isToday ? t.onInk : t.textPrimary)
            marker(isToday: isToday, cleared: cleared, missed: missed, hasDay: day != nil)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .background(isToday ? t.ink : t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: date, hasDay: day != nil,
                                  isToday: isToday, cleared: cleared, missed: missed))
    }

    @ViewBuilder
    private func marker(isToday: Bool, cleared: Bool, missed: Bool, hasDay: Bool) -> some View {
        if isToday {
            Circle().fill(t.onInk).frame(width: 8, height: 8)
        } else if cleared {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(t.success)
        } else if missed || !hasDay {
            // A dash for a day that came and went; nothing for a day the
            // rhythm never scheduled.
            Rectangle()
                .fill(hasDay ? t.textTertiary : .clear)
                .frame(width: 12, height: 2)
        } else {
            Color.clear
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1   // Sunday first, as the design draws it
        return calendar
    }

    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: reference)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayInstance(on date: Date) -> DayInstance? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func letter(for date: Date) -> String {
        calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    private func label(for date: Date, hasDay: Bool,
                       isToday: Bool, cleared: Bool, missed: Bool) -> String {
        let name = date.formatted(.dateTime.weekday(.wide))
        if isToday { return "\(name), today" }
        guard hasDay else { return "\(name), no reading" }
        if cleared { return "\(name), opened" }
        if missed { return "\(name), missed" }
        return "\(name), not opened"
    }
}
