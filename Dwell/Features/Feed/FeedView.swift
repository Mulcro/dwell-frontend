import SwiftUI

/// The day's reflections, once the threshold has cleared.
///
/// Reached from Home's "Read reflections" — not a tab. RLS does the gating:
/// if the day hasn't unlocked, or you haven't posted an approved reflection,
/// the server simply doesn't return anyone else's rows.
struct FeedView: View {
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var reflections: Loadable<[Reflection]> = .idle
    @State private var selected: Reflection?

    private var dayIndex: Int { session.currentDay?.dayIndex ?? 1 }

    /// The sky fades to white across this distance from the top of the screen.
    private let skyHeight: CGFloat = 300
    /// Cards begin partway down the fade — enough air under "Day 1" that the
    /// header breathes, without pushing the first post off the fold.
    private var contentTopInset: CGFloat { skyHeight * 0.27 }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: skyHeight, fadeFrom: 0.25)

            VStack(alignment: .leading, spacing: 0) {
                header

                LoadableView(state: reflections, retry: { Task { await load() } }) { list in
                    if list.isEmpty {
                        EmptyStateView(
                            title: "Nothing to read yet",
                            message: "When enough of you have posted, everyone's words open at once.")
                    } else {
                        feed(list)
                    }
                }
            }
        }
        .dwellThemed()
        .task(id: session.currentDay?.id) { await load() }
        .sheet(item: $selected) { reflection in
            ReflectionThreadView(reflection: reflection,
                                 authorName: session.name(for: reflection.userId),
                                 onClose: { selected = nil })
        }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            Text("Day \(dayIndex)")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    private func feed(_ list: [Reflection]) -> some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                ForEach(list) { reflection in
                    ReflectionCard(
                        reflection: reflection,
                        authorName: session.name(for: reflection.userId),
                        avatarURL: session.avatarURL(for: reflection.userId),
                        isMine: reflection.userId == session.me?.id,
                        onExpand: { selected = reflection },
                        onReply: { selected = reflection })
                }

                ForEach(notYetPosted, id: \.userId) { member in
                    HStack(spacing: Space.md) {
                        PhotoAvatar(name: session.memberProfiles[member.userId]?.name ?? "Member",
                                    url: session.avatarURL(for: member.userId),
                                    size: 40)
                        Text("\(session.name(for: member.userId)) hasn't posted yet")
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                        Spacer()
                    }
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(t.border, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    )
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, contentTopInset)
            .padding(.bottom, Space.xxxl)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
    }

    private var notYetPosted: [GroupMember] {
        let posted = Set((reflections.value ?? []).map(\.userId))
        return session.members.filter { !posted.contains($0.userId) }
    }

    private func load() async {
        guard let day = session.currentDay else {
            reflections = .loaded([])
            return
        }
        reflections = .loading
        do {
            let list = try await session.api.reflections(dayInstanceId: day.id)
                .sorted { $0.createdAt > $1.createdAt }
            reflections = .loaded(list)
            // DWELL_THREAD=1 opens the first thread, for screenshots.
            if ProcessInfo.processInfo.environment["DWELL_THREAD"] == "1" {
                selected = list.first { $0.aiResponse != nil } ?? list.first
            }
        } catch {
            reflections = .failed(error.localizedDescription)
        }
    }
}
