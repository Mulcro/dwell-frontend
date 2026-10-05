import SwiftUI

/// "View" on an archived challenge (What's Next): that group's closing recap,
/// read-only. Fetched on open because the session only ever loads the
/// current group.
struct ArchivedRecapView: View {
    let group: GroupSummary
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var state: Loadable<Found?> = .idle

    private struct Found {
        let recap: AIInsight
        let names: [UUID: String]
        let avatars: [UUID: URL]
    }

    var body: some View {
        switch state {
        case .loaded(let found?):
            RecapView(insight: found.recap, groupName: group.name,
                      names: found.names, avatars: found.avatars, onClose: onClose)
        case .loaded(nil):
            // A challenge that closed with nobody posting has no card; say so
            // rather than showing an empty recap.
            VStack(spacing: Space.lg) {
                OnboardingBackBar(onBack: onClose)
                Spacer()
                EmptyStateView(title: "No recap for this one",
                               message: "\(group.name) closed before anything was written to look back on.")
                Spacer()
            }
            .padding(.horizontal, Space.gutter)
            .dwellThemed()
        default:
            VStack(spacing: 0) {
                OnboardingBackBar(onBack: onClose)
                    .padding(.horizontal, Space.gutter)
                LoadableView(state: state, retry: { Task { await load() } }) { _ in
                    EmptyView()
                }
            }
            .dwellThemed()
            .task { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            var recap = try await session.api.insights(groupId: group.id, type: .endSummary).first
            if recap == nil {
                recap = try await session.api.insights(groupId: group.id, type: .fallbackRecap).first
            }
            guard let recap else { state = .loaded(nil); return }
            let ids = recap.payload?.members?.map(\.userId) ?? []
            let users = ids.isEmpty ? [] : ((try? await session.api.users(ids: ids)) ?? [])
            let names = Dictionary(uniqueKeysWithValues: users.map {
                ($0.id, $0.name.split(separator: " ").first.map(String.init) ?? $0.name)
            })
            // The session only signs the current roster's photos, so members
            // who are only in this archived group are signed here. Same
            // preference as the roster: a moderated avatar_path, then the
            // provider's avatar_url.
            var avatars: [UUID: URL] = [:]
            for user in users {
                if let path = user.avatarPath, !path.isEmpty {
                    if let cached = AvatarStore.shared.signed(for: path) {
                        avatars[user.id] = cached
                    } else if let url = try? await session.api.avatarURL(path: path) {
                        AvatarStore.shared.remember(url, for: path)
                        avatars[user.id] = url
                    }
                } else if let url = user.avatarUrl {
                    avatars[user.id] = url
                }
            }
            state = .loaded(Found(recap: recap, names: names, avatars: avatars))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
