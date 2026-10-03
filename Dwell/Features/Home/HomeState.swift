import Foundation

/// What the home screen should say, derived from whatever the account
/// actually is — not assumed.
///
/// A group can be forming, paused, finished, or active-with-no-open-day (a
/// `weekdays` or `custom` rhythm simply has no row on a skipped day). Each of
/// those is a normal state, and showing "Start Reflection" in any of them
/// would be a lie.
enum HomeState: Equatable {
    case noGroup
    case forming(memberCount: Int)
    case paused
    case completed
    case endedEarly(ChallengeStatus)
    case promptPending
    /// Active, but nothing is open today.
    case noOpenDay
    /// Open, and you haven't posted.
    case readyToReflect(dayIndex: Int)
    /// You posted; the group hasn't cleared the threshold.
    case waitingOnGroup(dayIndex: Int, posted: Int, needed: Int)
    /// Posted and cleared — the day is readable.
    case dayOpen(dayIndex: Int, posted: Int, total: Int)

    @MainActor
    static func resolve(_ session: SessionStore) -> HomeState {
        guard let group = session.group.value ?? nil else { return .noGroup }

        switch group.challengeStatus {
        case .forming:            return .forming(memberCount: session.members.count)
        case .paused:             return .paused
        case .completed:          return .completed
        case .abandoned, .expiredIncomplete:
            return .endedEarly(group.challengeStatus)
        case .active:             break
        }

        if group.promptPending { return .promptPending }
        guard let day = session.currentDay else { return .noOpenDay }

        let posted = day.participationCount
        if day.isUnlocked, session.myReflection?.moderationStatus == .approved {
            return .dayOpen(dayIndex: day.dayIndex, posted: posted, total: session.members.count)
        }
        guard session.myReflection?.moderationStatus == .approved else {
            return .readyToReflect(dayIndex: day.dayIndex)
        }
        return .waitingOnGroup(dayIndex: day.dayIndex,
                               posted: posted,
                               needed: max(session.requiredToUnlock, 1))
    }

    var headline: String {
        switch self {
        case .noGroup:                return "No group yet"
        case .forming:                return "Waiting for one more"
        case .paused:                 return "Paused"
        case .completed:              return "You finished it"
        case .endedEarly(let status): return status == .abandoned ? "Challenge ended" : "Challenge closed out"
        case .promptPending:          return "It's been quiet"
        case .noOpenDay:              return "Nothing open today"
        case .readyToReflect(let day):    return "Day \(day)"
        case .waitingOnGroup(let day, _, _): return "Day \(day) — you're in"
        case .dayOpen(let day, _, _):        return "Day \(day) is open"
        }
    }

    var detail: String {
        switch self {
        case .noGroup:
            return "Create a group or join one with a code."
        case .forming(let count):
            return "Day 1 opens the moment someone joins you. \(count) here so far."
        case .paused:
            return "No days are advancing and nobody's being nudged. Everything you wrote is still here."
        case .completed:
            return "You cleared the last day together."
        case .endedEarly(let status):
            return status == .abandoned
                ? "Everyone keeps what they wrote."
                : "It went quiet for two weeks, so we closed it out."
        case .promptPending:
            return "Your group needs to decide whether to keep going, pause, or end."
        case .noOpenDay:
            return "Your rhythm doesn't include today. The next day opens on schedule."
        case .readyToReflect:
            return "Read today's passage, then share where it landed."
        case .waitingOnGroup(_, let posted, let needed):
            let remaining = max(needed - posted, 1)
            return "\(posted) of \(needed) posted — \(remaining) more \(remaining == 1 ? "opens" : "open") the day."
        case .dayOpen(_, let posted, let total):
            return "\(posted) of \(total) posted. Everyone's words are readable."
        }
    }

    /// Nil when there's nothing honest to offer.
    var action: String? {
        switch self {
        case .noGroup:           return "Create or join a group"
        case .forming:           return "Share the invite"
        case .paused:            return "Pick it back up"
        case .completed:         return "See what those days held"
        case .endedEarly:        return "Start something new"
        case .promptPending:     return "Answer for the group"
        case .noOpenDay:         return nil
        case .readyToReflect:    return "Start Reflection"
        case .waitingOnGroup:    return "Nudge the group"
        case .dayOpen:           return "Read the day"
        }
    }
}
