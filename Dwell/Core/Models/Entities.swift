import Foundation

/// One struct per table in Backend Design Doc §3.1. Column names are carried
/// through in CodingKeys so the same models decode straight off PostgREST.

struct DwellUser: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var preferredLanguage: String
    var timezone: String
    var pushToken: String?
    /// Added backend-side 2026-10-01 and backfilled. Populated by
    /// `handle_new_auth_user` from the provider's `avatar_url` or `picture`,
    /// and writable through the existing "update own profile" policy.
    /// Readable for group-mates, which is what finally lets the app show
    /// anyone's face but your own.
    var avatarUrl: URL?
    /// Object key in the private `avatars` bucket, set only by `/set-avatar`
    /// after moderation. Preferred over `avatarUrl` when present — that one is
    /// whatever the identity provider happened to have, and nothing checked it.
    var avatarPath: String?
    var createdAt: Date
    /// Per-type push switches (KAN-22), checked by send-push before every
    /// push. A missing key is on.
    var notificationPrefs: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case preferredLanguage = "preferred_language"
        case pushToken = "push_token"
        case notificationPrefs = "notification_prefs"
        case avatarUrl = "avatar_url"
        case avatarPath = "avatar_path"
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
    /// Object key in the **public** `plan-images` bucket — a key, not a URL,
    /// so the same row works against local and hosted projects.
    var imagePath: String?
    /// The Figma's plan detail (02b) wants a description, a key verse and
    /// titled days. These three are capability probes: the columns don't
    /// exist yet, so they decode as nil and the detail screen renders only
    /// the sections it has data for — no client release needed when they
    /// land. Raised in Notion.
    var planDescription: String?
    var keyVerse: String?
    var keyVerseRef: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceType = "source_type"
        case dayCount = "day_count"
        case youversionPlanId = "youversion_plan_id"
        case youversionDeepLink = "youversion_deep_link"
        case imagePath = "image_path"
        case planDescription = "description"
        case keyVerse = "key_verse"
        case keyVerseRef = "key_verse_ref"
    }
}

struct PlanDay: Codable, Hashable, Identifiable {
    var planChallengeId: UUID
    var dayIndex: Int
    var passageRef: String
    /// The day's theme line ("Stop", "Remain in the vine"). Same capability
    /// probe as the plan columns above: nil until the backend adds it.
    var title: String?

    var id: String { "\(planChallengeId)-\(dayIndex)" }

    enum CodingKeys: String, CodingKey {
        case planChallengeId = "plan_challenge_id"
        case dayIndex = "day_index"
        case passageRef = "passage_ref"
        case title
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

/// One row of `rpc/my_groups` (KAN-46): every group the caller is in, the
/// one still going first, otherwise the most recently active. Counts are the
/// whole group's, not what RLS would show of sealed reflections.
struct GroupSummary: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var challengeStatus: ChallengeStatus
    var planChallengeId: UUID
    var planTitle: String
    var planImagePath: String?
    var dayCount: Int
    var memberCount: Int
    var reflectionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case challengeStatus = "challenge_status"
        case planChallengeId = "plan_challenge_id"
        case planTitle = "plan_title"
        case planImagePath = "plan_image_path"
        case dayCount = "day_count"
        case memberCount = "member_count"
        case reflectionCount = "reflection_count"
    }
}

/// One row of `rpc/my_continuations` (KAN-50): a "same crew, new plan" group
/// that continues one the caller was in, which they haven't joined yet.
/// Carries no invite code; accepting is `join-group` by `groupId`.
struct Continuation: Codable, Hashable, Identifiable {
    var groupId: UUID
    var name: String
    var continuesGroupId: UUID
    var planTitle: String
    var planImagePath: String?
    var dayCount: Int
    var memberCount: Int
    var createdBy: UUID?
    var createdByName: String?

    var id: UUID { groupId }

    enum CodingKeys: String, CodingKey {
        case name
        case groupId = "group_id"
        case continuesGroupId = "continues_group_id"
        case planTitle = "plan_title"
        case planImagePath = "plan_image_path"
        case dayCount = "day_count"
        case memberCount = "member_count"
        case createdBy = "created_by"
        case createdByName = "created_by_name"
    }
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
    /// Object key in the private `reflection-media` bucket, shaped
    /// `{user_id}/{uuid}.m4a`. Playback goes through `createSignedUrl`, which
    /// applies the same unlock rule as the row itself.
    var mediaPath: String?
    var mediaMime: String?
    var mediaDurationSeconds: Int?
    /// 1–512 whole numbers, each 0–100 — lets the waveform be drawn without
    /// downloading and decoding the audio.
    var mediaPeaks: [Int]?
    var createdAt: Date

    /// The per-reflection companion response. Backend Design Doc §1.1 says
    /// /submit-reflection writes "sentiment tag + translation + personalized
    /// response ... back onto the row", but §3.1's schema has no column for it
    /// — see SCHEMA-GAPS.md. Modelled here as the doc's prose describes.
    var aiResponse: String?
    /// `ai_response_translated jsonb` — language code → the companion's reply
    /// translated into that language; null when everyone already reads the
    /// author's language. Same shape and semantics as `translated_text`.
    var aiResponseTranslated: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, content, transcript, language
        case userId = "user_id"
        case dayInstanceId = "day_instance_id"
        case mediaType = "media_type"
        case translatedText = "translated_text"
        case sentimentTag = "sentiment_tag"
        case moderationStatus = "moderation_status"
        case isLate = "is_late"
        case mediaPath = "media_path"
        case mediaMime = "media_mime"
        case mediaDurationSeconds = "media_duration_seconds"
        case mediaPeaks = "media_peaks"
        case createdAt = "created_at"
        case aiResponse = "ai_response"
        case aiResponseTranslated = "ai_response_translated"
    }

    /// What the reader sees: transcript for voice, content for text.
    var displayBody: String { transcript ?? content ?? "" }

    /// True when there is a recording to play.
    var hasRecording: Bool { mediaPath?.isEmpty == false }

    /// Only approved reflections count toward the threshold (§4.2).
    var countsTowardThreshold: Bool { moderationStatus == .approved }

    /// The companion's reply as the viewer reads it: translated into their
    /// language when a translation exists, otherwise as written.
    func companionResponse(in viewerLanguage: String) -> String? {
        guard let response = aiResponse else { return nil }
        guard language != viewerLanguage,
              let translated = aiResponseTranslated?[viewerLanguage] else { return response }
        return translated
    }
}

struct Comment: Identifiable, Codable, Hashable {
    let id: UUID
    var reflectionId: UUID
    var userId: UUID
    /// Null on a voice reply, which carries its words in `transcript` — the
    /// same split `Reflection` uses.
    var content: String?
    var createdAt: Date

    // Replies are text-only on the backend as of 2026-10-02; these are all
    // optional so the row decodes unchanged either way, and light up the moment
    // the columns exist. See the media-replies request in Notion.
    var mediaType: MediaType?
    var mediaPath: String?
    var mediaMime: String?
    var mediaDurationSeconds: Int?
    var mediaPeaks: [Int]?
    var transcript: String?
    /// What the reply was written in, and translations keyed by the language
    /// translated **into** — the same shape `Reflection` uses. Both are absent
    /// until the backend adds them; see the translation request in Notion.
    var language: String?
    var translatedText: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, content, transcript, language
        case reflectionId = "reflection_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case mediaType = "media_type"
        case mediaPath = "media_path"
        case mediaMime = "media_mime"
        case mediaDurationSeconds = "media_duration_seconds"
        case mediaPeaks = "media_peaks"
        case translatedText = "translated_text"
    }

    /// What to show in the bubble — a voice reply carries its words in
    /// `transcript`, everything else in `content`.
    var body: String { transcript ?? content ?? "" }

    /// The reply in the reader's language where one exists, falling back to
    /// what was written. Mirrors how a reflection is shown.
    func body(in viewerLanguage: String) -> String {
        guard let language, language != viewerLanguage,
              let translated = translatedText?[viewerLanguage] else { return body }
        return translated
    }

    /// Whether this reply is being shown translated, so the UI can say so.
    func isTranslated(for viewerLanguage: String) -> Bool {
        guard let language, language != viewerLanguage else { return false }
        return translatedText?[viewerLanguage] != nil
    }
    var hasRecording: Bool { mediaType == .voice && mediaPath?.isEmpty == false }
    var hasPhoto: Bool { mediaType == .photo && mediaPath?.isEmpty == false }
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

/// A member line on the group pulse — a commitment in Option D, a selected
/// quote in Option A. The backend never shows the model a `user_id`; it maps
/// positions back to people server-side, so a bad position is dropped rather
/// than attributed to the wrong person.
struct PulseMember: Codable, Hashable, Identifiable {
    var userId: UUID
    var line: String
    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case line
        case userId = "user_id"
    }
}

/// The structured half of a group pulse, added 2026-10-02.
///
/// Everything is optional: the backend ships sections independently, and a row
/// written before this existed has no payload at all.
struct PulsePayload: Codable, Hashable {
    var headline: String?
    var lede: String?
    var members: [PulseMember]?
    var reflectionCount: Int?
    /// The translated standfirst. The contract names this `summary` inside a
    /// `translated_text` value — `content` is only the untranslated column on
    /// the row itself. Both are accepted so neither spelling silently yields
    /// an untranslated summary.
    var summary: String?
    var content: String?
    /// Recap card fields (end_summary / fallback_recap / weekly_recap).
    /// Days the group cleared against the days that counted; both null on a
    /// weekly recap when no day opened that week but someone still posted.
    var daysShowedUp: Int?
    var daysTotal: Int?
    /// weekly_recap only.
    var weekStart: String?

    enum CodingKeys: String, CodingKey {
        case headline, lede, members, summary, content
        case reflectionCount = "reflection_count"
        case daysShowedUp = "days_showed_up"
        case daysTotal = "days_total"
        case weekStart = "week_start"
    }

    /// Whichever of the two the backend sent.
    var standfirst: String? {
        [summary, content].compactMap { $0 }.first { !$0.isEmpty }
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
    var payload: PulsePayload?
    /// What the insight was written in, and translations keyed by the language
    /// translated **into** — the same shape reflections and comments use.
    var language: String?
    var translatedText: [String: PulsePayload]?

    enum CodingKeys: String, CodingKey {
        case id, scope, type, content, payload, language
        case groupId = "group_id"
        case dayInstanceId = "day_instance_id"
        case targetUserId = "target_user_id"
        case createdAt = "created_at"
        case translatedText = "translated_text"
    }

    /// The payload in the reader's language where one exists.
    func payload(in viewerLanguage: String) -> PulsePayload? {
        if let language, language != viewerLanguage,
           let translated = translatedText?[viewerLanguage] { return translated }
        return payload
    }

    /// The summary, translated when a translation carries one.
    func summary(in viewerLanguage: String) -> String {
        if let language, language != viewerLanguage,
           let translated = translatedText?[viewerLanguage]?.standfirst,
           !translated.isEmpty { return translated }
        return content
    }

    func isTranslated(for viewerLanguage: String) -> Bool {
        guard let language, language != viewerLanguage else { return false }
        return translatedText?[viewerLanguage] != nil
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
