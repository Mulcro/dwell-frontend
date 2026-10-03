import Foundation

/// Mirrors the Postgres enums in the Backend Design Doc §3.1 verbatim.
/// Raw values are the database's own strings so Codable needs no mapping.

enum MediaType: String, Codable, Hashable, CaseIterable {
    case text, voice
    /// Not in the Postgres enum yet (Notion items 31 and 35). The server never
    /// sends it, so decoding is unaffected; it exists so the feed and composer
    /// are already written for it when the bucket lands. The composer refuses
    /// to submit one in the meantime.
    case photo
}

/// The five values `create-group` accepts.
///
/// The redesign's picker offers three of them — Daily, 4 Days/Week and Custom.
/// `weekdays` and `three_per_week` exist on the wire but aren't offered in the
/// UI; they're here so a group created elsewhere still decodes.
enum Frequency: String, Codable, Hashable, CaseIterable, Identifiable {
    case daily
    case weekdays
    case fourPerWeek = "four_per_week"
    case threePerWeek = "three_per_week"
    case custom

    var id: String { rawValue }

    /// What the redesign's Frequency & Threshold screen offers.
    static var offered: [Frequency] { [.daily, .fourPerWeek, .custom] }

    var label: String {
        switch self {
        case .daily:        return "Daily"
        case .weekdays:     return "Weekdays"
        case .fourPerWeek:  return "4 Days/Week"
        case .threePerWeek: return "3 Days/Week"
        case .custom:       return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .daily:        return "Every day, the strongest rhythm."
        case .weekdays:     return "Monday to Friday."
        case .fourPerWeek:  return "Mon, Tue, Thu, Fri, where the research says change happens."
        case .threePerWeek: return "Monday, Wednesday, Friday."
        case .custom:       return "Pick your own days."
        }
    }

    /// The days this rhythm implies, as ISO weekdays (1 = Monday … 7 = Sunday).
    /// Only `custom` sends these; the rest are resolved server-side.
    var impliedDays: [Int] {
        switch self {
        case .daily:        return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays:     return [1, 2, 3, 4, 5]
        case .fourPerWeek:  return [1, 2, 4, 5]
        case .threePerWeek: return [1, 3, 5]
        case .custom:       return []
        }
    }
}

enum SourceType: String, Codable, Hashable {
    case youversionPlan = "youversion_plan"
    case custom
}

enum DayStatus: String, Codable, Hashable {
    case open
    case thresholdMet = "threshold_met"
    case complete
    case missed
}

enum ChallengeStatus: String, Codable, Hashable {
    case forming, active, paused, completed, abandoned
    case expiredIncomplete = "expired_incomplete"

    /// Terminal states show a recap instead of a day.
    var isEnded: Bool {
        switch self {
        case .completed, .abandoned, .expiredIncomplete: return true
        case .forming, .active, .paused: return false
        }
    }
}

enum InsightScope: String, Codable, Hashable {
    case dayInstance = "day_instance"
    case groupChallenge = "group_challenge"
}

enum InsightType: String, Codable, Hashable {
    case groupPulse = "group_pulse"
    case nudge
    /// The Continue / Pause / End question, delivered as an insight row
    /// rather than a client-side flag.
    case inactivityPrompt = "inactivity_prompt"
    case endSummary = "end_summary"
    case fallbackRecap = "fallback_recap"
}

/// `reflections.moderation_status` is a plain text column defaulting to
/// 'pending'; these are the three values the pipeline writes.
enum ModerationStatus: String, Codable, Hashable {
    case pending, approved, flagged
}

/// Payload for `/group-challenge-action`.
enum ChallengeAction: String, Codable, Hashable {
    case `continue`, pause, end
}
