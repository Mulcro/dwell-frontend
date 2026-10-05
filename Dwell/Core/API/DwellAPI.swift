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

    /// Clears `users.push_token` on the signed-in account, so a phone that
    /// switches accounts stops receiving the previous one's pushes.
    func clearPushToken() async throws

    /// POST /delete-account. Erases the account in the JWT — there is
    /// deliberately no way to name another user. Required by App Store
    /// guideline 5.1.1(v) for any app offering account creation.
    func deleteAccount() async throws

    /// Uploads a profile picture and runs it through moderation.
    ///
    /// Neither avatar column is writable directly — a PATCH on `users`
    /// touching them is refused — because it used to be possible to point
    /// `avatar_url` at any image on the internet. This is the only way in.
    /// Throws `.moderationRefused` on 422.
    func setAvatar(fileURL: URL, mime: String) async throws -> String

    /// Signed URL for an object in the private `avatars` bucket.
    func avatarURL(path: String) async throws -> URL

    // MARK: - §1.1 Client-facing Edge Functions

    /// POST /create-group → group in `forming` + a group_members row for the creator.
    /// `customDays` is required when and only when `frequency == .custom`;
    /// sending it with any other frequency is a 400.
    func createGroup(name: String,
                     planChallengeId: UUID,
                     frequency: Frequency,
                     customDays: [Int]?,
                     timezone: String,
                     autoSkipAfterDays: Int?,
                     continuesGroupId: UUID?) async throws -> CreateGroupResponse

    /// POST /join-group. If this join brings membership to 2, flips the group
    /// to `active` and creates the Day 1 row.
    func joinGroup(inviteToken: String) async throws -> JoinGroupResponse

    /// One-tap accept of a "same crew, new plan" invitation (KAN-50). Allowed
    /// only for members of the group it continues; the rules are otherwise
    /// those of joining by code.
    func joinGroup(groupId: UUID) async throws -> JoinGroupResponse

    /// Pending "same crew, new plan" invitations, newest first.
    func myContinuations() async throws -> [Continuation]

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
                          language: String,
                          attachment: MediaAttachment?) async throws -> SubmitReflectionResponse

    /// POST /group-challenge-action — the Continue / Pause / End response.
    func groupChallengeAction(groupId: UUID,
                              action: ChallengeAction) async throws -> ChallengeStatus

    // MARK: - §1.3 Direct database API (PostgREST + RLS)

    func currentUser() async throws -> DwellUser
    /// `name` is here because the auth trigger seeds the literal placeholder
    /// "Friend" when the provider sends no name — see `SessionStore`.
    func updateProfile(name: String?,
                       timezone: String?,
                       preferredLanguage: String?,
                       pushToken: String?) async throws -> DwellUser

    /// The caller's group. One group per user for MVP (Open Questions, 9/19).
    /// The group the app opens into: the one still going, otherwise the most
    /// recently finished, so a finished challenge keeps its celebration until
    /// the next one starts.
    func myGroup() async throws -> DwellGroup?
    /// Every group the caller is in, current first (`rpc/my_groups`).
    func myGroups() async throws -> [GroupSummary]
    func members(groupId: UUID) async throws -> [GroupMember]
    func users(ids: [UUID]) async throws -> [DwellUser]

    func dayInstances(groupId: UUID) async throws -> [DayInstance]
    func currentDay(groupId: UUID) async throws -> DayInstance?

    /// Own reflection always returned; group-mates' only once the caller has
    /// posted an approved one for that day. RLS enforces this server-side —
    /// the mock reproduces the same rule so the UI can't drift.
    func reflections(dayInstanceId: UUID) async throws -> [Reflection]

    /// Every reflection *you* have posted in this group's challenge.
    ///
    /// RLS always lets you read your own rows, whatever the day's state, so
    /// this works for sealed days too — unlike `reflections(dayInstanceId:)`,
    /// which is about what the group can see.
    func myReflections(groupId: UUID) async throws -> [Reflection]

    func comments(reflectionId: UUID) async throws -> [Comment]
    /// Posts a reply through `submit-comment`, which moderates it. Throws
    /// `.moderationRefused` when it's declined — nothing is written in that
    /// case, so there is no flagged row to reconcile.
    func addComment(reflectionId: UUID, content: String,
                    attachment: MediaAttachment?, transcript: String?,
                    language: String) async throws

    /// Whether replies can carry audio or a photo yet.
    ///
    /// Probed rather than assumed: the client is ready, the `comments` table
    /// isn't, and shipping buttons that post into a column that doesn't exist
    /// would lose someone's reply silently. When this is false the composer
    /// offers text only, and it starts offering media the moment the backend
    /// lands — no client release needed.
    func commentMediaSupported() async -> Bool

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

    /// `groups` and `group_members` joined the publication on 2026-10-01, so a
    /// member joining and `forming` → `active` now arrive on their own.
    ///
    /// Emits a bare signal rather than a row: the contract warns that a single
    /// insert was observed delivering twice, so this means "re-read", never
    /// "increment".
    func membershipChanges(groupId: UUID) -> AsyncStream<Void>

    // MARK: - §3.4 Mock PlanService

    /// Public URL for an object in the `plan-images` bucket. The bucket is
    /// public — catalogue art, identical for everyone — so no signing is
    /// needed and normal HTTP caching applies.
    func planImageURL(path: String) -> URL?

    /// Signed URL for a reflection's audio or photo — they share the private
    /// `reflection-media` bucket on purpose, so both inherit the same unlock
    /// rule as the reflection row.
    func mediaURL(path: String) async throws -> URL

    func listPlans() async throws -> [PlanChallenge]
    func getPlan(id: UUID) async throws -> PlanChallenge
    func getPlanDays(planId: UUID) async throws -> [PlanDay]

    // MARK: - Passage content (YouVersion Passages API — unauthenticated)

    /// Passage text is always fetched live by USFM ref; only the plan's table
    /// of contents is mocked (§3.4).
    func passage(ref: String) async throws -> Passage

    /// Debug-only: moves the group a day forward or back through the gated
    /// `/debug-day` function (item 48). `action` is "advance" or "rewind";
    /// returns the resulting day index. The server answers 404 when its
    /// `DEBUG_DAY_ENABLED` gate is off, which is the state outside our one
    /// project.
    func debugDay(groupId: UUID, action: String) async throws -> Int
}

enum AuthProvider: String, Codable, Hashable, CaseIterable, Identifiable {
    /// Email + password. Designed in the redesign's Sign Up screen; not in the
    /// Client API Contract, which covers OAuth only — backend to confirm.
    case email
    case apple, google, facebook, youversion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .email:      return "Continue"
        case .apple:      return "Continue with Apple"
        case .facebook:   return "Continue with Facebook"
        case .google:     return "Continue with Google"
        case .youversion: return "Continue with YouVersion"
        }
    }

    /// YouVersion needs Supabase's Custom OIDC provider, which is blocked on
    /// two unknowns (Backend Design Doc §2): whether YouVersion publishes an
    /// OIDC discovery document, and whether its OAuth client issues a client
    /// secret at all. The screens are built either way; this decides which
    /// call actually fires.
    var isAvailableInMVP: Bool { self == .google || self == .email || self == .youversion }
}

/// What a reflection carries besides words.
///
/// Modelled as one choice rather than two optionals because the contract
/// rejects the wrong combination: a photo sent with `media_duration_seconds`
/// or `media_peaks` is a 400, and so is a voice note without a duration.
enum MediaAttachment: Equatable {
    case voice(Recording)
    case photo(fileURL: URL, mime: String)

    var fileURL: URL {
        switch self {
        case .voice(let recording): return recording.fileURL
        case .photo(let url, _):    return url
        }
    }

    var mime: String {
        switch self {
        case .voice(let recording): return recording.mime
        case .photo(_, let mime):   return mime
        }
    }

    /// Extension for the object key — the bucket is shared, so the suffix is
    /// what distinguishes them.
    var pathExtension: String {
        switch self {
        case .voice: return "m4a"
        case .photo(_, let mime): return mime == "image/png" ? "png" : "jpg"
        }
    }
}

/// A recorded voice note, ready to upload.
///
/// Uploaded to `reflection-media/{user id}/{uuid}.m4a` with the user's own
/// token — the storage policy only permits writes inside your own folder —
/// and then named in the submit call.
struct Recording: Equatable {
    let fileURL: URL
    let durationSeconds: Int
    let mime: String
    /// 1–512 whole numbers, 0–100. Optional.
    let peaks: [Int]

    init(fileURL: URL, durationSeconds: Int, peaks: [Int], mime: String = "audio/mp4") {
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
        self.peaks = peaks
        self.mime = mime
    }
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
    case moderationRefused(String)

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
        case .aiUnavailable:         return "We couldn't reach the companion just now. Nothing was saved. Try again."
        case .notImplemented(let w): return "\(w) isn't wired up yet."
        case .moderationRefused(let m): return m
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
