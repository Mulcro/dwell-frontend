import SwiftUI

/// The unlocked day: everyone's reflections, plus the group pulse once the
/// AI has synthesised it.
struct FeedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var reflections: Loadable<[Reflection]> = .idle
    @State private var engagement: [UUID: (hearts: Int, replies: Int)] = [:]
    @State private var pulse: AIInsight?
    @State private var passage: Passage?
    @State private var selected: Reflection?

    private var day: DayInstance? { session.currentDay }

    var body: some View {
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
        .padding(.horizontal, Space.gutter)
        .task(id: day?.id) { await load() }
        .sheet(item: $selected) { reflection in
            ReflectionDetailView(reflection: reflection,
                                 authorName: session.name(for: reflection.userId),
                                 onBack: { selected = nil })
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day?.isUnlocked == true
                     ? "Day \(day?.dayIndex ?? 1) is open"
                     : "Day \(day?.dayIndex ?? 1)")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                Text("\(session.postedCount) of \(session.members.count) posted · \(passage?.reference ?? day?.passageRef ?? "")")
                    .font(.dwellFootnote)
                    .foregroundStyle(t.success)
            }
            Spacer()
            DayDial(fraction: fraction)
        }
        .padding(.top, Space.sm)
    }

    private var fraction: Double {
        guard session.members.count > 0 else { return 0 }
        return Double(session.postedCount) / Double(session.members.count)
    }

    private func feed(_ list: [Reflection]) -> some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if let pulse {
                    GroupPulseCard(insight: pulse)
                }

                ForEach(list) { reflection in
                    ReflectionCard(
                        reflection: reflection,
                        authorName: session.name(for: reflection.userId),
                        isMine: reflection.userId == session.me?.id,
                        hearts: engagement[reflection.id]?.hearts ?? 0,
                        replies: engagement[reflection.id]?.replies ?? 0,
                        hasCompanionReply: reflection.aiResponse != nil,
                        onTap: { selected = reflection })
                }

                ForEach(notYetPosted, id: \.userId) { member in
                    Panel(dashed: true) {
                        HStack(spacing: Space.md) {
                            Avatar(size: 30, tinted: false)
                            Text("\(session.name(for: member.userId)) hasn't posted yet")
                                .font(.dwellFootnote)
                                .foregroundStyle(t.textSecondary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await session.reload()
            await load()
        }
    }

    private var notYetPosted: [GroupMember] {
        let posted = Set((reflections.value ?? []).map(\.userId))
        return session.members.filter { !posted.contains($0.userId) }
    }

    private func load() async {
        guard let day else { return }
        reflections = .loading
        do {
            let list = try await session.api.reflections(dayInstanceId: day.id)
                .sorted { $0.createdAt < $1.createdAt }
            reflections = .loaded(list)

            for reflection in list {
                async let hearts = session.api.reactions(reflectionId: reflection.id)
                async let replies = session.api.comments(reflectionId: reflection.id)
                engagement[reflection.id] = (try await hearts.count, try await replies.count)
            }

            passage = try? await session.api.passage(ref: day.passageRef)

            if let g = session.group.value ?? nil {
                pulse = try await session.api.insights(groupId: g.id, type: .groupPulse)
                    .first { $0.dayInstanceId == day.id }
            }
        } catch {
            reflections = .failed(error.localizedDescription)
        }
    }
}

/// The AI's daily synthesis, shown inline at the top of the unlocked feed.
struct GroupPulseCard: View {
    let insight: AIInsight
    @Environment(\.dwell) private var t
    @State private var expanded = false

    private var parts: (body: String, question: String?) {
        let chunks = insight.content.components(separatedBy: "\n\n")
        guard chunks.count > 1 else { return (insight.content, nil) }
        return (chunks.dropLast().joined(separator: "\n\n"), chunks.last)
    }

    var body: some View {
        Panel(accented: true) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    CompanionMark(size: 22)
                    Eyebrow("Group pulse", color: t.accent)
                }

                Text(parts.body)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .lineSpacing(5)
                    .lineLimit(expanded ? nil : 4)

                if let question = parts.question {
                    Text(question.replacingOccurrences(of: "One question for tonight: ", with: ""))
                        .font(.dwellTitleSm)
                        .foregroundStyle(t.textPrimary)
                        .lineSpacing(3)
                }

                Button(expanded ? "Less" : "Read it all") { expanded.toggle() }
                    .font(.dwellFootnoteMd)
                    .foregroundStyle(t.accent)
            }
        }
    }
}
