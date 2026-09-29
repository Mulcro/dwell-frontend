import SwiftUI

/// Your own history, assembled from past reflections. Not in the MVP screen
/// list, but everything it shows already exists in the data model — no new
/// endpoint needed.
struct MemoriesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var filter: Filter = .mine
    @State private var entries: Loadable<[Entry]> = .idle

    enum Filter: String, CaseIterable, Identifiable {
        case mine = "Mine", group = "Group", voice = "Voice"
        var id: String { rawValue }
    }

    struct Entry: Identifiable {
        let id: UUID
        let dayIndex: Int
        let passageRef: String
        let mediaType: MediaType
        let body: String
        let isMine: Bool
        let authorName: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memories")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                Spacer()
                Text(filter == .group ? "Your group" : "Only you")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
            .padding(.top, Space.sm)

            HStack(spacing: Space.sm) {
                ForEach(Filter.allCases) { option in
                    PillToggle(title: option.rawValue, selected: filter == option) {
                        Haptics.select()
                        filter = option
                    }
                }
            }
            .padding(.top, Space.lg)

            LoadableView(state: entries, retry: { Task { await load() } }) { all in
                let list = apply(filter, to: all)
                if list.isEmpty {
                    EmptyStateView(
                        title: "Nothing here yet",
                        message: filter == .voice
                            ? "Voice reflections you record will collect here."
                            : "Your reflections start collecting from day one.")
                } else {
                    content(list)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .task { await load() }
    }

    private func content(_ list: [Entry]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Panel {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("\(list.count) reflection\(list.count == 1 ? "" : "s"), so far")
                            .font(.dwellTitleSm)
                            .foregroundStyle(t.textPrimary)
                        Text("Across \(Set(list.map(\.dayIndex)).count) days of \(session.plan?.title.components(separatedBy: ":").first ?? "this plan").")
                            .font(.dwellFootnote)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(4)
                    }
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    Eyebrow("This challenge")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md),
                                        GridItem(.flexible(), spacing: Space.md)],
                              spacing: Space.md) {
                        ForEach(list) { entry in tile(entry) }
                    }
                }
            }
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
    }

    private func tile(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Day \(entry.dayIndex) · \(entry.mediaType == .voice ? "voice" : "text")")
                .font(.dwellCaptionMd)
                .foregroundStyle(t.textPrimary)
            if filter == .group && !entry.isMine {
                Text(entry.authorName)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
            Text("\u{201C}\(entry.body.prefix(64))\u{2026}\u{201D}")
                .font(.dwellFootnote)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .frame(height: 124, alignment: .topLeading)
        .padding(Space.md)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func apply(_ filter: Filter, to all: [Entry]) -> [Entry] {
        switch filter {
        case .mine:  return all.filter(\.isMine)
        case .group: return all
        case .voice: return all.filter { $0.mediaType == .voice }
        }
    }

    private func load() async {
        guard let g = session.group.value ?? nil else { return }
        entries = .loading
        do {
            let days = try await session.api.dayInstances(groupId: g.id)
            var collected: [Entry] = []
            for day in days {
                let list = try await session.api.reflections(dayInstanceId: day.id)
                collected += list.map { reflection in
                    Entry(id: reflection.id,
                          dayIndex: day.dayIndex,
                          passageRef: day.passageRef,
                          mediaType: reflection.mediaType,
                          body: reflection.displayBody,
                          isMine: reflection.userId == session.me?.id,
                          authorName: session.name(for: reflection.userId))
                }
            }
            entries = .loaded(collected.sorted { $0.dayIndex > $1.dayIndex })
        } catch {
            entries = .failed(error.localizedDescription)
        }
    }
}
