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
        // A bare `date` carries no timezone — "2026-10-01" is a calendar day,
        // not an instant. Parsing it as UTC midnight and then comparing it
        // with `Calendar.current` shifts it to the previous day for anyone
        // west of UTC, which put the week strip's tick on the wrong cell.
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = .current
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

    /// The literal string the auth trigger writes when the provider sent no
    /// name: `coalesce(raw_user_meta_data->>'name', 'Friend')`. Someone who
    /// signed in with a provider that *does* know their name shouldn't be
    /// stuck being called this.
    private static let placeholderName = "Friend"

    /// Providers report identity in different shapes — YouVersion through the
    /// id_token claims, Google through Supabase's user metadata. Both land
    /// here once the session exists.
    ///
    /// The name is only written over the placeholder: a user who has since
    /// set their own name must not have it reverted by their next sign-in.
    private func adoptProviderProfile(name: String?, avatar: URL?) async {
        AvatarStore.shared.remember(avatar)

        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let current = try? await currentUser(),
              current.name == Self.placeholderName || current.name.isEmpty
        else { return }

        _ = try? await updateProfile(name: name, timezone: nil,
                                     preferredLanguage: nil, pushToken: nil)
    }

    /// Name and picture as Supabase stores them for an OAuth user. Key names
    /// differ by provider, so each is tried in turn.
    private func providerMetadata() async -> (name: String?, avatar: URL?) {
        guard let user = try? await client.auth.session.user else { return (nil, nil) }
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if case .string(let value)? = user.userMetadata[key], !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        return (string(["full_name", "name"]),
                string(["avatar_url", "picture"]).flatMap { URL(string: $0) })
    }

    func signIn(provider: AuthProvider) async throws -> DwellUser {
        switch provider {
        case .google:
            // Browser flow, not signInWithIdToken: the project's
            // external_google_additional_client_ids isn't set, so a native iOS
            // token is rejected.
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirectURL)
            let profile = await providerMetadata()
            await adoptProviderProfile(name: profile.name, avatar: profile.avatar)
        case .apple:
            throw DwellError.notImplemented("Sign in with Apple")
        case .facebook:
            throw DwellError.notImplemented("Facebook sign-in")
        case .youversion:
            guard let youVersion else {
                throw DwellError.notImplemented("YouVersion sign-in, YOUVERSION_APP_KEY isn't set")
            }
            // Their flow, then a bridge that hands back a magic-link hash we
            // redeem for an ordinary Supabase session — so every RLS policy
            // and the profile trigger work unchanged.
            let bridged = try await youVersion.authenticate(
                supabaseURL: url, publishableKey: publishableKey)
            try await client.auth.verifyOTP(tokenHash: bridged.tokenHash, type: .magiclink)
            // `users` has no avatar column, so the URL is kept on the device
            // for the signed-in user until the backend stores it.
            await adoptProviderProfile(name: youVersion.displayName,
                                       avatar: youVersion.avatarURL)
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

    func submitReflection(dayInstanceId: UUID,
                          mediaType: MediaType,
                          content: String?,
                          transcript: String?,
                          language: String,
                          attachment: MediaAttachment?) async throws -> SubmitReflectionResponse {
        var body: [String: AnyJSON] = [
            "day_instance_id": .string(dayInstanceId.uuidString.lowercased()),
            "media_type": .string(mediaType.rawValue),
            "language": .string(language)
        ]
        if let content { body["content"] = .string(content) }
        if let transcript { body["transcript"] = .string(transcript) }

        // Upload first, then name the object.
        //
        // A voice upload that fails degrades to a transcript-only post: the
        // words are what moderation, translation and the summaries use, so the
        // reflection still counts. A *photo* cannot degrade — the caption
        // alone is not what the person chose to post, and `media_type: photo`
        // without an object is a 400 — so that failure propagates.
        if let attachment {
            let path: String
            switch attachment {
            case .photo:
                path = try await uploadMedia(attachment)
            case .voice:
                guard let uploaded = try? await uploadMedia(attachment) else {
                    return try await invoke("submit-reflection", body: body)
                }
                path = uploaded
            }
            body["media_path"] = .string(path)
            body["media_mime"] = .string(attachment.mime)
            // Duration and peaks belong to audio only — sending either with a
            // photo is a 400.
            if case .voice(let recording) = attachment {
                body["media_duration_seconds"] = .integer(recording.durationSeconds)
                if !recording.peaks.isEmpty {
                    body["media_peaks"] = .array(recording.peaks.map { .integer($0) })
                }
            }
        }

        return try await invoke("submit-reflection", body: body)
    }

    /// Uploads with the user's own token to `{user id}/{uuid}.m4a`. The
    /// storage policy rejects any path outside your own folder, at upload and
    /// again at submit.
    private func uploadMedia(_ attachment: MediaAttachment) async throws -> String {
        let userId = try await currentUserId()
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased())"
            + ".\(attachment.pathExtension)"
        let data = try Data(contentsOf: attachment.fileURL)
        _ = try await client.storage.from("reflection-media")
            .upload(path, data: data,
                    options: FileOptions(contentType: attachment.mime))
        return path
    }

    func groupChallengeAction(groupId: UUID, action: ChallengeAction) async throws -> ChallengeStatus {
        struct Response: Decodable { let challenge_status: ChallengeStatus }
        let response: Response = try await invoke("group-challenge-action", body: [
            "group_id": .string(groupId.uuidString.lowercased()),
            "action": .string(action.rawValue)
        ])
        return response.challenge_status
    }

    func setAvatar(fileURL: URL, mime: String) async throws -> String {
        let userId = try await currentUserId()
        let ext = mime == "image/png" ? "png" : "jpg"
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
        let data = try Data(contentsOf: fileURL)
        _ = try await client.storage.from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: mime))

        struct Response: Decodable { let avatar_path: String }
        do {
            let response: Response = try await invoke("set-avatar", body: [
                "media_path": .string(path),
                "media_mime": .string(mime)
            ])
            return response.avatar_path
        } catch {
            // 422 is moderation refusing the picture, not a failure — the
            // upload is already destroyed server-side.
            throw DwellError.moderationRefused("That picture can't be used as a profile photo. Try a different one.")
        }
    }

    func avatarURL(path: String) async throws -> URL {
        try await client.storage.from("avatars")
            .createSignedURL(path: path, expiresIn: 60 * 60 * 24)
    }

    func deleteAccount() async throws {
        struct Response: Decodable { let deleted: Bool }
        // `confirm` is required by the contract so a mis-wired call can't
        // erase an account.
        let _: Response = try await invoke("delete-account",
                                           body: ["confirm": .string("DELETE")])
        try? await client.auth.signOut()
    }

    func passage(ref: String) async throws -> Passage {
        try await invoke("get-passage", body: ["ref": .string(ref)])
    }

    func debugDay(groupId: UUID, action: String) async throws -> Int {
        struct Response: Decodable { let day_index: Int }
        let response: Response = try await invoke("debug-day", body: [
            "group_id": .string(groupId.uuidString.lowercased()),
            "action": .string(action)
        ])
        return response.day_index
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

    func updateProfile(name: String?, timezone: String?, preferredLanguage: String?, pushToken: String?) async throws -> DwellUser {
        let id = try await currentUserId()
        var patch: [String: AnyJSON] = [:]
        if let name { patch["name"] = .string(name) }
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
        // my_groups orders the rows by the backend's rule (still going first,
        // then most recent activity), so row 1 is the current group. Sorting
        // by created_at here picked a finished group over an older one just
        // joined.
        let summaries = try await myGroups()

        #if DEBUG
        if let wanted = ProcessInfo.processInfo.environment["DWELL_GROUP"],
           let match = summaries.first(where: { $0.name.localizedCaseInsensitiveContains(wanted) }) {
            return try await group(id: match.id)
        }
        #endif
        guard let current = summaries.first else { return nil }
        return try await group(id: current.id)
    }

    func myGroups() async throws -> [GroupSummary] {
        try await client.rpc("my_groups").execute().value
    }

    private func group(id: UUID) async throws -> DwellGroup {
        try await client.from("groups").select()
            .eq("id", value: id).single().execute().value
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

    func myReflections(groupId: UUID) async throws -> [Reflection] {
        let id = try await currentUserId()
        // Joined through `day_instances` so this returns one group's history.
        // Unscoped, someone in two groups would see the other group's posts in
        // this group's Memories and stats.
        return try await client.from("reflections")
            .select("*, day_instances!inner(group_id)")
            .eq("user_id", value: id)
            .eq("day_instances.group_id", value: groupId)
            .execute().value
    }

    func comments(reflectionId: UUID) async throws -> [Comment] {
        try await client.from("comments").select()
            .eq("reflection_id", value: reflectionId)
            .order("created_at").execute().value
    }

    func addComment(reflectionId: UUID, content: String,
                    attachment: MediaAttachment?, transcript: String?,
                    language: String) async throws {
        // Direct inserts were revoked on 2026-10-02 (42501) — replies go
        // through the endpoint so media and text get the same moderation pass
        // reflections already get.
        var body: [String: AnyJSON] = [
            "reflection_id": .string(reflectionId.uuidString.lowercased()),
            // Optional on the endpoint, but sending it beats the fallback:
            // for a voice reply this is the recogniser's locale, which is what
            // the words were actually spoken in.
            "language": .string(language)
        ]

        switch attachment {
        case .voice(let recording):
            let path = try await uploadMedia(.voice(recording))
            body["media_type"] = .string(MediaType.voice.rawValue)
            body["media_path"] = .string(path)
            body["media_mime"] = .string(recording.mime)
            body["media_duration_seconds"] = .integer(recording.durationSeconds)
            if !recording.peaks.isEmpty {
                body["media_peaks"] = .array(recording.peaks.map { .integer($0) })
            }
            // A voice reply requires a transcript, same as a voice reflection.
            body["transcript"] = .string(transcript ?? content)
        case .photo(let url, let mime):
            let path = try await uploadMedia(.photo(fileURL: url, mime: mime))
            body["media_type"] = .string(MediaType.photo.rawValue)
            body["media_path"] = .string(path)
            body["media_mime"] = .string(mime)
            body["content"] = .string(content)
        case nil:
            body["media_type"] = .string(MediaType.text.rawValue)
            body["content"] = .string(content)
        }

        struct Response: Decodable { let comment_id: UUID }
        do {
            let _: Response = try await invoke("submit-comment", body: body)
        } catch DwellError.planHasNoDays {
            // `fromStatus` maps 422 to "plan has no days" for the endpoints
            // that predate this one. Here 422 is moderation refusing the
            // reply — nothing is written and any upload is already destroyed.
            throw DwellError.moderationRefused(
                "That reply couldn't be posted. Try rewording it or using a different photo.")
        }
    }

    func commentMediaSupported() async -> Bool {
        // PostgREST answers an unknown column with a 400 naming it, so asking
        // for one is the cheapest possible feature detection.
        do {
            _ = try await client.from("comments")
                .select("media_path").limit(1).execute()
            return true
        } catch {
            return false
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

    func planImageURL(path: String) -> URL? {
        try? client.storage.from("plan-images").getPublicURL(path: path)
    }

    func mediaURL(path: String) async throws -> URL {
        try await client.storage.from("reflection-media")
            .createSignedURL(path: path, expiresIn: 60 * 60)
    }

    /// Filters on `listed` itself: RLS also returns an unlisted plan to a
    /// member of a group reading it, and that read is indistinguishable from
    /// this one.
    func listPlans() async throws -> [PlanChallenge] {
        try await client.from("plan_challenges").select()
            .eq("listed", value: true)
            .order("title").execute().value
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

    func membershipChanges(groupId: UUID) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { [client] in
                if let token = try? await client.auth.session.accessToken {
                    await client.realtimeV2.setAuth(token)
                }
                let id = groupId.uuidString.lowercased()
                let channel = client.realtimeV2.channel("public:membership:\(id)")

                // `group_members` keys on group_id; `groups` on its own id.
                let members = channel.postgresChange(AnyAction.self,
                                                     schema: "public",
                                                     table: "group_members",
                                                     filter: "group_id=eq.\(id)")
                let groups = channel.postgresChange(AnyAction.self,
                                                    schema: "public",
                                                    table: "groups",
                                                    filter: "id=eq.\(id)")
                await channel.subscribe()

                await withTaskGroup(of: Void.self) { tasks in
                    tasks.addTask { for await _ in members { continuation.yield(()) } }
                    tasks.addTask { for await _ in groups { continuation.yield(()) } }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
    /// Enough detail to find the field without a debugger attached.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing field '\(key.stringValue)'."
        case .valueNotFound(_, let context):
            return "Null in non-optional '\(context.codingPath.map(\.stringValue).joined(separator: "."))'."
        case .typeMismatch(let type, let context):
            return "Expected \(type) at '\(context.codingPath.map(\.stringValue).joined(separator: "."))'."
        default:
            return "Malformed response."
        }
    }

    private static func translate(_ error: Error) -> DwellError {
        if let dwell = error as? DwellError { return dwell }

        // Foundation renders these as "The data couldn't be read because it is
        // missing", which says nothing about which field or why. A decoding
        // failure always means the row didn't match this model — usually a
        // column that became nullable — so name that.
        if let decoding = error as? DecodingError {
            return .network("The app couldn't read that response. It doesn't match "
                            + "what this build expects. \(Self.describe(decoding))")
        }

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
