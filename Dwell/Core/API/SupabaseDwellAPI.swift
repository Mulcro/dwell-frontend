import Foundation
import Supabase

/// The real backend, against the deployed project.
///
/// Shapes come from the Client API Contract, verified live. Three rules from
/// that document are load-bearing and easy to get wrong, so they're called out
/// where they apply:
///   • the socket needs the user's access token, or it silently delivers nothing
///   • `custom_days` is required when and only when frequency is `custom`
///   • error bodies differ — Edge Functions use `error`, PostgREST uses `message`
@MainActor
final class SupabaseDwellAPI: DwellAPI {

    private let client: SupabaseClient
    private let url: URL
    private let publishableKey: String
    private lazy var youVersion: YouVersionAuth? = {
        guard let appKey = DwellConfig.youVersionAppKey else { return nil }
        return YouVersionAuth(supabaseURL: url, appKey: appKey)
    }()

    /// `dwell://auth-callback` is the deployed `site_url` and is on the
    /// redirect allow-list.
    private let redirectURL = URL(string: "dwell://auth-callback")!

    init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                db: .init(decoder: SupabaseDwellAPI.decoder),
                global: .init(headers: ["x-client-info": "dwell-ios"])
            )
        )
    }

    /// Postgres hands back three date shapes: timestamptz with fractional
    /// seconds, timestamptz without, and bare `date` columns
    /// (`day_instances.date`, `leaderboard_entries.week_start`). A single
    /// ISO8601 strategy fails on the third.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = TimeZone(identifier: "UTC")
        dateOnly.locale = Locale(identifier: "en_US_POSIX")

        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            if let date = dateOnly.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unrecognised date: \(raw)"))
        }
        return decoder
    }()

    // MARK: - Auth

    func signIn(provider: AuthProvider) async throws -> DwellUser {
        switch provider {
        case .google:
            // Browser flow, not signInWithIdToken: the project's
            // external_google_additional_client_ids isn't set, so a native iOS
            // token is rejected.
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirectURL)
        case .apple:
            throw DwellError.notImplemented("Sign in with Apple")
        case .youversion:
            guard let youVersion else {
                throw DwellError.notImplemented("YouVersion sign-in — YOUVERSION_APP_KEY isn't set")
            }
            // Their flow, then a bridge that hands back a magic-link hash we
            // redeem for an ordinary Supabase session — so every RLS policy
            // and the profile trigger work unchanged.
            let bridged = try await youVersion.authenticate(
                supabaseURL: url, publishableKey: publishableKey)
            try await client.auth.verifyOTP(tokenHash: bridged.tokenHash, type: .magiclink)
        case .email:
            throw DwellError.notImplemented("Use signIn(email:password:)")
        }
        return try await currentUser()
    }

    func signIn(email: String, password: String) async throws -> DwellUser {
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            throw Self.translate(error)
        }
        return try await currentUser()
    }

    func signUp(email: String, password: String, name: String?) async throws -> DwellUser {
        do {
            try await client.auth.signUp(
                email: email,
                password: password,
                data: name.map { ["name": AnyJSON.string($0)] })
        } catch {
            throw Self.translate(error)
        }
        return try await currentUser()
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Every authenticated call goes through here. Supabase reports a missing
    /// session as `AuthError.sessionMissing`, which is not an error condition
    /// — it's the signed-out state, and the app routes on it.
    private func currentUserId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw DwellError.notAuthenticated
        }
    }

    // MARK: - Edge Functions

    func createGroup(name: String, planChallengeId: UUID,
                     frequency: Frequency, customDays: [Int]?, timezone: String,
                     catchUpThresholdPct: Int?, autoSkipAfterDays: Int?) async throws -> CreateGroupResponse {
        var body: [String: AnyJSON] = [
            "name": .string(name),
            "plan_challenge_id": .string(planChallengeId.uuidString.lowercased()),
            "frequency": .string(frequency.rawValue),
            "timezone": .string(timezone)
        ]
        if let catchUpThresholdPct { body["catch_up_threshold_pct"] = .integer(catchUpThresholdPct) }
        if let autoSkipAfterDays { body["auto_skip_after_days"] = .integer(autoSkipAfterDays) }
        // Required for `custom`, rejected with a 400 for anything else.
        if frequency == .custom {
            body["custom_days"] = .array((customDays ?? []).map { .integer($0) })
        }
        return try await invoke("create-group", body: body)
    }

    func joinGroup(inviteToken: String) async throws -> JoinGroupResponse {
        try await invoke("join-group", body: ["invite_token": .string(inviteToken)])
    }

    /// Public RPC — `apikey` only, no session. Returns `[]` for an unknown
    /// token rather than erroring.
    func previewGroup(inviteToken: String) async throws -> GroupPreview? {
        let rows: [GroupPreview] = try await client
            .rpc("preview_group", params: ["token": inviteToken])
            .execute()
            .value
        return rows.first
    }

    func submitReflection(dayInstanceId: UUID, mediaType: MediaType,
                          content: String?, transcript: String?,
                          language: String) async throws -> SubmitReflectionResponse {
        var body: [String: AnyJSON] = [
            "day_instance_id": .string(dayInstanceId.uuidString.lowercased()),
            "media_type": .string(mediaType.rawValue),
            "language": .string(language)
        ]
        if let content { body["content"] = .string(content) }
        if let transcript { body["transcript"] = .string(transcript) }
        return try await invoke("submit-reflection", body: body)
    }

    func groupChallengeAction(groupId: UUID, action: ChallengeAction) async throws -> ChallengeStatus {
        struct Response: Decodable { let challenge_status: ChallengeStatus }
        let response: Response = try await invoke("group-challenge-action", body: [
            "group_id": .string(groupId.uuidString.lowercased()),
            "action": .string(action.rawValue)
        ])
        return response.challenge_status
    }

    func passage(ref: String) async throws -> Passage {
        try await invoke("get-passage", body: ["ref": .string(ref)])
    }

    private func invoke<T: Decodable>(_ name: String, body: [String: AnyJSON]) async throws -> T {
        do {
            return try await client.functions.invoke(
                name,
                options: FunctionInvokeOptions(body: body),
                decode: { data, response in
                    guard (200..<300).contains(response.statusCode) else {
                        throw DwellError.fromStatus(response.statusCode,
                                                    message: DwellError.message(from: data))
                    }
                    return try Self.decoder.decode(T.self, from: data)
                })
        } catch let error as DwellError {
            throw error
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: - PostgREST

    func currentUser() async throws -> DwellUser {
        let id = try await currentUserId()
        return try await client.from("users").select().eq("id", value: id)
            .single().execute().value
    }

    func updateProfile(timezone: String?, preferredLanguage: String?, pushToken: String?) async throws -> DwellUser {
        let id = try await currentUserId()
        var patch: [String: AnyJSON] = [:]
        if let timezone { patch["timezone"] = .string(timezone) }
        if let preferredLanguage { patch["preferred_language"] = .string(preferredLanguage) }
        if let pushToken { patch["push_token"] = .string(pushToken) }
        guard !patch.isEmpty else { return try await currentUser() }
        return try await client.from("users").update(patch).eq("id", value: id)
            .select().single().execute().value
    }

    /// MVP assumes one group per user, but the demo seed puts a user in four,
    /// and PostgREST doesn't guarantee row order without an ORDER BY — so
    /// without this the app would land on a different group between launches.
    /// Newest first, and `DWELL_GROUP` pins a specific one for demos.
    func myGroup() async throws -> DwellGroup? {
        let rows: [DwellGroup] = try await client.from("groups").select()
            .order("created_at", ascending: false)
            .execute().value

        #if DEBUG
        if let wanted = ProcessInfo.processInfo.environment["DWELL_GROUP"],
           let match = rows.first(where: { $0.name.localizedCaseInsensitiveContains(wanted) }) {
            return match
        }
        #endif
        return rows.first
    }

    func members(groupId: UUID) async throws -> [GroupMember] {
        try await client.from("group_members").select()
            .eq("group_id", value: groupId).execute().value
    }

    func users(ids: [UUID]) async throws -> [DwellUser] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("users").select()
            .in("id", values: ids).execute().value
    }

    func dayInstances(groupId: UUID) async throws -> [DayInstance] {
        try await client.from("day_instances").select()
            .eq("group_id", value: groupId)
            .order("day_index").execute().value
    }

    func currentDay(groupId: UUID) async throws -> DayInstance? {
        let rows: [DayInstance] = try await client.from("day_instances").select()
            .eq("group_id", value: groupId)
            .order("day_index", ascending: false)
            .limit(1).execute().value
        return rows.first
    }

    /// RLS applies the reflection lock — own row always, others' only once the
    /// day is cleared and yours is approved. No client-side filtering needed.
    func reflections(dayInstanceId: UUID) async throws -> [Reflection] {
        try await client.from("reflections").select()
            .eq("day_instance_id", value: dayInstanceId).execute().value
    }

    func comments(reflectionId: UUID) async throws -> [Comment] {
        try await client.from("comments").select()
            .eq("reflection_id", value: reflectionId)
            .order("created_at").execute().value
    }

    func addComment(reflectionId: UUID, content: String) async throws -> Comment {
        let id = try await currentUserId()
        do {
            return try await client.from("comments").insert([
                "reflection_id": AnyJSON.string(reflectionId.uuidString.lowercased()),
                "user_id": .string(id.uuidString.lowercased()),
                "content": .string(content)
            ]).select().single().execute().value
        } catch {
            throw Self.translate(error)
        }
    }

    func reactions(reflectionId: UUID) async throws -> [Reaction] {
        try await client.from("reactions").select()
            .eq("reflection_id", value: reflectionId).execute().value
    }

    func addReaction(reflectionId: UUID, emoji: String) async throws -> Reaction {
        let id = try await currentUserId()
        return try await client.from("reactions").insert([
            "reflection_id": AnyJSON.string(reflectionId.uuidString.lowercased()),
            "user_id": .string(id.uuidString.lowercased()),
            "emoji": .string(emoji)
        ]).select().single().execute().value
    }

    func removeReaction(reflectionId: UUID, emoji: String) async throws {
        let id = try await currentUserId()
        try await client.from("reactions").delete()
            .eq("reflection_id", value: reflectionId)
            .eq("user_id", value: id)
            .eq("emoji", value: emoji)
            .execute()
    }

    func insights(groupId: UUID, type: InsightType?) async throws -> [AIInsight] {
        var query = client.from("ai_insights").select().eq("group_id", value: groupId)
        if let type { query = query.eq("type", value: type.rawValue) }
        return try await query.order("created_at", ascending: false).execute().value
    }

    func leaderboard(groupId: UUID, weekStart: Date?) async throws -> [LeaderboardEntry] {
        try await client.from("leaderboard_entries").select()
            .eq("group_id", value: groupId).execute().value
    }

    // MARK: - Plans

    func listPlans() async throws -> [PlanChallenge] {
        try await client.from("plan_challenges").select().order("title").execute().value
    }

    func getPlan(id: UUID) async throws -> PlanChallenge {
        try await client.from("plan_challenges").select()
            .eq("id", value: id).single().execute().value
    }

    func getPlanDays(planId: UUID) async throws -> [PlanDay] {
        try await client.from("plan_days").select()
            .eq("plan_challenge_id", value: planId)
            .order("day_index").execute().value
    }

    // MARK: - Realtime

    /// INSERT is published as well as UPDATE, so a new day opening arrives
    /// here too — subscribe to all changes, not just updates.
    func dayInstanceUpdates(groupId: UUID) -> AsyncStream<DayInstance> {
        stream(table: "day_instances", groupId: groupId)
    }

    func insightInserts(groupId: UUID) -> AsyncStream<AIInsight> {
        stream(table: "ai_insights", groupId: groupId)
    }

    private func stream<T: Decodable & Sendable>(table: String, groupId: UUID) -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task { [client] in
                // Without the user's token the socket connects and then
                // silently delivers nothing, because RLS is applied per message.
                if let token = try? await client.auth.session.accessToken {
                    await client.realtimeV2.setAuth(token)
                }

                let channel = client.realtimeV2.channel("public:\(table):\(groupId)")
                let changes = channel.postgresChange(AnyAction.self,
                                                     schema: "public",
                                                     table: table,
                                                     filter: "group_id=eq.\(groupId.uuidString.lowercased())")
                await channel.subscribe()

                for await change in changes {
                    // AnyAction is an enum; only insert and update carry a row.
                    let decoded: T? = switch change {
                    case .insert(let action): try? action.decodeRecord(decoder: Self.decoder)
                    case .update(let action): try? action.decodeRecord(decoder: Self.decoder)
                    case .delete: nil
                    }
                    if let decoded { continuation.yield(decoded) }
                }
                await channel.unsubscribe()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Errors

    /// Edge Functions return `{ "error": … }`; PostgREST returns
    /// `{ code, details, hint, message }`. Neither is safe to show raw.
    private static func translate(_ error: Error) -> DwellError {
        if let dwell = error as? DwellError { return dwell }

        if let postgrest = error as? PostgrestError {
            // 42501 is an RLS denial — for comments it just means the day
            // isn't unlocked yet, which is a state, not a failure.
            if postgrest.code == "42501" {
                return .notAMember
            }
            if postgrest.code == "23505" {
                return .conflict("That's already saved.")
            }
            return .network(postgrest.message)
        }

        if let auth = error as? AuthError {
            // Signed out is a state, not a failure.
            if auth.localizedDescription.lowercased().contains("session missing") {
                return .notAuthenticated
            }
            return .network(auth.localizedDescription)
        }

        return .network(error.localizedDescription)
    }
}
