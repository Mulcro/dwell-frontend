import Foundation

/// The entire backend surface from the Backend Design Doc, as one protocol.
///
/// Organised the same way the doc is:
///   §1.1 client-facing Edge Functions  — real side effects, real logic
///   §1.3 direct PostgREST reads/writes — RLS does the access control
///   §1.4 realtime channels             — pub/sub, delivered as AsyncStreams
///   §3.4 mock PlanService              — stands in for a future plans endpoint
///
/// `MockDwellAPI` drives the whole app today; `SupabaseDwellAPI` is the
/// swap-in. No screen knows which one it has.
@MainActor
protocol DwellAPI {

    // MARK: - §2 Auth

    /// MVP ships standard OAuth (Apple/Google) via Supabase Auth; YouVersion
    /// arrives later as a Custom OIDC provider (Backend Design Doc §2).
    func signIn(provider: AuthProvider) async throws -> DwellUser
    func signIn(email: String, password: String) async throws -> DwellUser
    func signUp(email: String, password: String, name: String?) async throws -> DwellUser
    func signOut() async throws

    // MARK: - §1.1 Client-facing Edge Functions

    /// POST /create-group → group in `forming` + a group_members row for the creator.
    /// `customDays` is required when and only when `frequency == .custom`;
    /// sending it with any other frequency is a 400.
    func createGroup(name: String,
                     planChallengeId: UUID,
                     frequency: Frequency,
                     customDays: [Int]?,
                     timezone: String,
                     catchUpThresholdPct: Int?,
                     autoSkipAfterDays: Int?) async throws -> CreateGroupResponse

    /// POST /join-group. If this join brings membership to 2, flips the group
    /// to `active` and creates the Day 1 row.
    func joinGroup(inviteToken: String) async throws -> JoinGroupResponse

    /// POST /rest/v1/rpc/preview_group — public, unauthenticated. Returns an
    /// array; an empty one means the token matches nothing, which is a normal
    /// answer rather than an error, so this returns nil for that case.
    func previewGroup(inviteToken: String) async throws -> GroupPreview?

    /// POST /submit-reflection. Inserts as `pending`; moderation decides
    /// whether it ever counts. The returned status is the post-moderation one.
    func submitReflection(dayInstanceId: UUID,
                          mediaType: MediaType,
                          content: String?,
                          transcript: String?,
                          language: String) async throws -> SubmitReflectionResponse

    /// POST /group-challenge-action — the Continue / Pause / End response.
    func groupChallengeAction(groupId: UUID,
                              action: ChallengeAction) async throws -> ChallengeStatus

    // MARK: - §1.3 Direct database API (PostgREST + RLS)

    func currentUser() async throws -> DwellUser
    func updateProfile(timezone: String?,
                       preferredLanguage: String?,
                       pushToken: String?) async throws -> DwellUser

    /// The caller's group. One group per user for MVP (Open Questions, 9/19).
    func myGroup() async throws -> DwellGroup?
    func members(groupId: UUID) async throws -> [GroupMember]
    func users(ids: [UUID]) async throws -> [DwellUser]

    func dayInstances(groupId: UUID) async throws -> [DayInstance]
    func currentDay(groupId: UUID) async throws -> DayInstance?

    /// Own reflection always returned; group-mates' only once the caller has
    /// posted an approved one for that day. RLS enforces this server-side —
    /// the mock reproduces the same rule so the UI can't drift.
    func reflections(dayInstanceId: UUID) async throws -> [Reflection]

    func comments(reflectionId: UUID) async throws -> [Comment]
    func addComment(reflectionId: UUID, content: String) async throws -> Comment

    func reactions(reflectionId: UUID) async throws -> [Reaction]
    func addReaction(reflectionId: UUID, emoji: String) async throws -> Reaction
    func removeReaction(reflectionId: UUID, emoji: String) async throws

    func insights(groupId: UUID, type: InsightType?) async throws -> [AIInsight]
    func leaderboard(groupId: UUID, weekStart: Date?) async throws -> [LeaderboardEntry]

    // MARK: - §1.4 Realtime channels

    /// day_instances filtered to the group — status and participation_count
    /// changes. Also the source of the content-free "X of Y posted" signal.
    func dayInstanceUpdates(groupId: UUID) -> AsyncStream<DayInstance>

    /// ai_insights inserts for the group — nudges, pulse, end summaries.
    func insightInserts(groupId: UUID) -> AsyncStream<AIInsight>

    // MARK: - §3.4 Mock PlanService

    func listPlans() async throws -> [PlanChallenge]
    func getPlan(id: UUID) async throws -> PlanChallenge
    func getPlanDays(planId: UUID) async throws -> [PlanDay]

    // MARK: - Passage content (YouVersion Passages API — unauthenticated)

    /// Passage text is always fetched live by USFM ref; only the plan's table
    /// of contents is mocked (§3.4).
    func passage(ref: String) async throws -> Passage
}

enum AuthProvider: String, Codable, Hashable, CaseIterable, Identifiable {
    /// Email + password. Designed in the redesign's Sign Up screen; not in the
    /// Client API Contract, which covers OAuth only — backend to confirm.
    case email
    case apple, google, youversion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .email:      return "Continue"
        case .apple:      return "Continue with Apple"
        case .google:     return "Continue with Google"
        case .youversion: return "Continue with YouVersion"
        }
    }

    /// YouVersion needs Supabase's Custom OIDC provider, which is blocked on
    /// two unknowns (Backend Design Doc §2): whether YouVersion publishes an
    /// OIDC discovery document, and whether its OAuth client issues a client
    /// secret at all. The screens are built either way; this decides which
    /// call actually fires.
    var isAvailableInMVP: Bool { self != .youversion }
}

// MARK: - Response envelopes

struct CreateGroupResponse: Codable, Hashable {
    let groupId: UUID
    let inviteToken: String

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case inviteToken = "invite_token"
    }
}

struct JoinGroupResponse: Codable, Hashable {
    let groupId: UUID
    let challengeStatus: ChallengeStatus

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case challengeStatus = "challenge_status"
    }
}

struct GroupPreview: Codable, Hashable {
    let name: String
    let planTitle: String

    enum CodingKeys: String, CodingKey {
        case name
        case planTitle = "plan_title"
    }
}

struct SubmitReflectionResponse: Codable, Hashable {
    let reflectionId: UUID
    /// Never `pending` — moderation runs synchronously inside the call.
    let moderationStatus: ModerationStatus
    /// Returned inline, so the late badge needs no re-fetch.
    let isLate: Bool

    enum CodingKeys: String, CodingKey {
        case reflectionId = "reflection_id"
        case moderationStatus = "moderation_status"
        case isLate = "is_late"
    }
}

/// Exactly what `POST /functions/v1/get-passage` returns.
///
/// Berean Standard Bible, plain text — there is no verse array, so the reader
/// renders `content` as a single passage. `audio_url` is always null for now;
/// the audio endpoint isn't wired up.
struct Passage: Codable, Hashable {
    let ref: String
    let bibleId: Int
    let reference: String
    let translation: String
    let content: String
    let audioURL: URL?
    /// Server-side cache hit. Scripture doesn't change, so `true` on a repeat
    /// call is expected, not a stale read.
    let cached: Bool

    enum CodingKeys: String, CodingKey {
        case ref, reference, translation, content, cached
        case bibleId = "bible_id"
        case audioURL = "audio_url"
    }

    var readTimeLabel: String {
        let words = content.split(separator: " ").count
        return "\(max(1, Int(ceil(Double(words) / 200.0)))) min read"
    }

    var hasAudio: Bool { audioURL != nil }
}

// MARK: - Errors

/// Mirrors the Client API Contract's status table. Two of these are states
/// rather than failures and the UI treats them that way: `conflict` (you
/// already posted, or the day closed) and `aiUnavailable` (nothing was saved,
/// so retrying is safe).
enum DwellError: LocalizedError, Equatable {
    case notAuthenticated                 // 401
    case notAMember                       // 403
    case notFound(String)                 // 404
    case conflict(String)                 // 409
    case planHasNoDays                    // 422
    case aiUnavailable                    // 502
    case notImplemented(String)
    case network(String)

    /// Error bodies are not uniform: Edge Functions return `{ "error": … }`,
    /// PostgREST returns `{ code, details, hint, message }`. Read `error`
    /// first, fall back to `message`.
    static func message(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return (json["error"] as? String) ?? (json["message"] as? String)
    }

    /// Maps a non-2xx response onto the contract's table.
    static func fromStatus(_ status: Int, message: String?) -> DwellError {
        switch status {
        case 401: return .notAuthenticated
        case 403: return .notAMember
        case 404: return .notFound(message ?? "That")
        case 409: return .conflict(message ?? "That's already done.")
        case 422: return .planHasNoDays
        case 502: return .aiUnavailable
        default:  return .network(message ?? "Something went wrong.")
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:      return "You need to sign in first."
        case .notAMember:            return "You're not a member of this group."
        case .notFound(let what):    return "\(what) couldn't be found."
        case .conflict(let message): return message
        case .planHasNoDays:         return "This plan has no days set up yet."
        case .aiUnavailable:         return "We couldn't reach the companion just now. Nothing was saved — try again."
        case .notImplemented(let w): return "\(w) isn't wired up yet."
        case .network(let m):        return m
        }
    }

    /// Whether the UI should offer a retry rather than a dead end.
    var isRetryable: Bool {
        switch self {
        case .aiUnavailable, .network: return true
        default: return false
        }
    }
}
