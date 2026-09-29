#if DEBUG
import Foundation

/// Launch with `DWELL_SELFTEST=1` to exercise the real backend and print what
/// came back. This is how the decoders get verified against live rows rather
/// than against assumptions — date formats and enum raw values are the two
/// things most likely to be wrong, and both fail loudly here.
enum SelfTest {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DWELL_SELFTEST"] == "1"
    }

    @MainActor
    static func run(api: DwellAPI) async {
        var transcript: [String] = []
        func log(_ line: String) {
            print("SELFTEST \(line)")
            transcript.append(line)
            // stdout from the simulator is unreliable to capture, so the run
            // also lands in the app container where the host can read it.
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? transcript.joined(separator: "\n")
                    .write(to: dir.appendingPathComponent("selftest.txt"),
                           atomically: true, encoding: .utf8)
            }
        }

        let email = ProcessInfo.processInfo.environment["DWELL_TEST_EMAIL"] ?? "demo-alice@dwell.test"
        let password = ProcessInfo.processInfo.environment["DWELL_TEST_PASSWORD"] ?? "dwell-demo-2026"

        do {
            // Never clobber a session that's already there — signing in as the
            // demo account would silently replace whoever is actually logged
            // in, and the app would then show their name and their groups.
            let user: DwellUser
            if let existing = try? await api.currentUser() {
                user = existing
                log("ℹ️  using existing session — \(user.name) (not signing in)")
            } else {
                user = try await api.signIn(email: email, password: password)
                log("✅ signIn — \(user.name) · tz=\(user.timezone) · lang=\(user.preferredLanguage)")
            }

            let plans = try await api.listPlans()
            log("✅ listPlans — \(plans.count): \(plans.map(\.title).joined(separator: " | "))")

            if let first = plans.first {
                let days = try await api.getPlanDays(planId: first.id)
                log("✅ getPlanDays — \(days.count) refs: \(days.map(\.passageRef).prefix(3).joined(separator: ", "))…")
            }

            let passage = try await api.passage(ref: "HEB.6.19")
            log("✅ get-passage — \(passage.reference) [\(passage.translation)] cached=\(passage.cached) \(passage.content.prefix(48))…")

            guard let group = try await api.myGroup() else {
                log("⚠️  myGroup — none for this account")
                return
            }
            log("✅ myGroup — \(group.name) · \(group.challengeStatus.rawValue) · freq=\(group.frequency.rawValue) · promptPending=\(group.promptPending) · tz=\(group.timezone ?? "nil")")

            let members = try await api.members(groupId: group.id)
            let profiles = try await api.users(ids: members.map(\.userId))
            log("✅ members — \(members.count): \(profiles.map(\.name).joined(separator: ", "))")

            let days = try await api.dayInstances(groupId: group.id)
            log("✅ dayInstances — \(days.count), statuses: \(days.map { $0.status.rawValue }.joined(separator: ","))")

            if let today = days.last {
                let reflections = try await api.reflections(dayInstanceId: today.id)
                log("✅ reflections — day \(today.dayIndex): \(reflections.count) visible, mine=\(reflections.filter { $0.userId == user.id }.count)")
                for r in reflections {
                    log("     · \(r.moderationStatus.rawValue) late=\(r.isLate) ai=\(r.aiResponse != nil ? "yes" : "no") \(r.displayBody.prefix(40))…")
                }
            }

            let insights = try await api.insights(groupId: group.id, type: nil)
            log("✅ insights — \(insights.count): \(Set(insights.map { $0.type.rawValue }).sorted().joined(separator: ", "))")

            let board = try await api.leaderboard(groupId: group.id, weekStart: nil)
            log("✅ leaderboard — \(board.count) rows\(board.isEmpty ? " (expected before first Monday)" : "")")

            log("🎉 all calls decoded")
        } catch {
            log("❌ \(type(of: error)): \(error)")
        }
    }
}
#endif
