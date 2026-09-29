import Foundation

/// One struct per table in Backend Design Doc §3.1. Column names are carried
/// through in CodingKeys so the same models decode straight off PostgREST.

struct DwellUser: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var preferredLanguage: String
    var timezone: String
    var pushToken: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case preferredLanguage = "preferred_language"
        case pushToken = "push_token"
        case createdAt = "created_at"
    }
}

struct PlanChallenge: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceType: SourceType
    var dayCount: Int
    var youversionPlanId: String?
    var youversionDeepLink: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceType = "source_type"
        case dayCount = "day_count"
        case youversionPlanId = "youversion_plan_id"
        case youversionDeepLink = "youversion_deep_link"
    }
}

struct PlanDay: Codable, Hashable, Identifiable {
    var planChallengeId: UUID
    var dayIndex: Int
    var passageRef: String

    var id: String { "\(planChallengeId)-\(dayIndex)" }

    enum CodingKeys: String, CodingKey {
        case planChallengeId = "plan_challenge_id"
        case dayIndex = "day_index"
        case passageRef = "passage_ref"
    }
}

struct DwellGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var planChallengeId: UUID
    var catchUpThresholdPct: Int
    var autoSkipAfterDays: Int
    var frequency: Frequency
    /// ISO weekdays, set only when `frequency == .custom`.
    var customDays: [Int]?
    var timezone: String?
    var challengeStatus: ChallengeStatus
    /// Whether the Continue / Pause / End question is outstanding.
    ///
    /// This — not the presence of an `inactivity_prompt` insight — is what
    /// decides. One insight row is written per member and it is never deleted,
    /// so treating the row as the signal would strand people on that screen.
    /// `group-challenge-action` clears this boolean on any answer.
    var promptPending: Bool
    var inviteToken: String
    var createdBy: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, frequency, timezone
        case customDays = "custom_days"
        case promptPending = "prompt_pending"
        case planChallengeId = "plan_challenge_id"
        case catchUpThresholdPct = "catch_up_threshold_pct"
        case autoSkipAfterDays = "auto_skip_after_days"
        case challengeStatus = "challenge_status"
        case inviteToken = "invite_token"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    /// Magic link shown on the invite screen.
    var inviteURL: String { "dwell.to/\(inviteToken)" }
}

struct GroupMember: Codable, Hashable, Identifiable {
    var groupId: UUID
    var userId: UUID
    var joinedAt: Date

    var id: String { "\(groupId)-\(userId)" }

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct DayInstance: Identifiable, Codable, Hashable {
    let id: UUID
    var groupId: UUID
    var dayIndex: Int
    var date: Date
    var passageRef: String
    var openedAt: Date
    var status: DayStatus
    var participationCount: Int
    var consecutiveBelowThresholdCount: Int

    enum CodingKeys: String, CodingKey {
        case id, date, status
        case groupId = "group_id"
        case dayIndex = "day_index"
        case passageRef = "passage_ref"
        case openedAt = "opened_at"
        case participationCount = "participation_count"
        case consecutiveBelowThresholdCount = "consecutive_below_threshold_count"
    }

    /// Each member gets a rolling 24h window from when the day opened
    /// (MVP Spec §4.5). A late joiner's window starts at their join time.
    func windowCloses(joinedAt: Date? = nil) -> Date {
        let start = max(openedAt, joinedAt ?? openedAt)
        return start.addingTimeInterval(24 * 60 * 60)
    }

    var isUnlocked: Bool { status == .thresholdMet || status == .complete }
}

struct Reflection: Identifiable, Codable, Hashable {
    let id: UUID
    var userId: UUID
    var dayInstanceId: UUID
    var mediaType: MediaType
    var content: String?
    var transcript: String?
    /// `translated_text jsonb` — language code → translated body.
    var translatedText: [String: String]?
    var language: String
    var sentimentTag: String?
    var moderationStatus: ModerationStatus
    var isLate: Bool
    var createdAt: Date

    /// The per-reflection companion response. Backend Design Doc §1.1 says
    /// /submit-reflection writes "sentiment tag + translation + personalized
    /// response ... back onto the row", but §3.1's schema has no column for it
    /// — see SCHEMA-GAPS.md. Modelled here as the doc's prose describes.
    var aiResponse: String?

    enum CodingKeys: String, CodingKey {
        case id, content, transcript, language
        case userId = "user_id"
        case dayInstanceId = "day_instance_id"
        case mediaType = "media_type"
        case translatedText = "translated_text"
        case sentimentTag = "sentiment_tag"
        case moderationStatus = "moderation_status"
        case isLate = "is_late"
        case createdAt = "created_at"
        case aiResponse = "ai_response"
    }

    /// What the reader sees: transcript for voice, content for text.
    var displayBody: String { transcript ?? content ?? "" }

    /// Only approved reflections count toward the threshold (§4.2).
    var countsTowardThreshold: Bool { moderationStatus == .approved }
}

struct Comment: Identifiable, Codable, Hashable {
    let id: UUID
    var reflectionId: UUID
    var userId: UUID
    var content: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content
        case reflectionId = "reflection_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct Reaction: Identifiable, Codable, Hashable {
    let id: UUID
    var reflectionId: UUID
    var userId: UUID
    var emoji: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case reflectionId = "reflection_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct AIInsight: Identifiable, Codable, Hashable {
    let id: UUID
    var groupId: UUID
    var dayInstanceId: UUID?
    /// null = group-wide (pulse, end summary); set = personal nudge.
    var targetUserId: UUID?
    var scope: InsightScope
    var type: InsightType
    var content: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, scope, type, content
        case groupId = "group_id"
        case dayInstanceId = "day_instance_id"
        case targetUserId = "target_user_id"
        case createdAt = "created_at"
    }
}

struct LeaderboardEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var groupId: UUID
    var weekStart: Date
    var userId: UUID
    var participationScore: Int

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case weekStart = "week_start"
        case userId = "user_id"
        case participationScore = "participation_score"
    }
}
