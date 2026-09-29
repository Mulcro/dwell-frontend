import SwiftUI

/// Full-screen group pulse — the AI's daily synthesis for an unlocked day.
struct GroupPulseView: View {
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var pulse: Loadable<AIInsight?> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(title: "Day \(session.currentDay?.dayIndex ?? 1) · group pulse", onLeading: onBack)

            LoadableView(state: pulse, retry: { Task { await load() } }) { insight in
                if let insight {
                    content(insight)
                } else {
                    EmptyStateView(
                        title: "Not yet",
                        message: "The pulse arrives once the day unlocks and everyone's words are in.")
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .task { await load() }
    }

    private func content(_ insight: AIInsight) -> some View {
        let chunks = insight.content.components(separatedBy: "\n\n")
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.md) {
                    Eyebrow("Today, all \(session.members.count) of you")
                    Text(chunks.first ?? insight.content)
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                        .lineSpacing(2)
                }

                if chunks.count > 1 {
                    ForEach(chunks.dropFirst().dropLast(), id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(5)
                    }
                }

                if let question = chunks.last, chunks.count > 1 {
                    Panel(accented: true) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Eyebrow("One question for tonight", color: t.accent)
                            Text(question.replacingOccurrences(of: "One question for tonight: ", with: ""))
                                .font(.dwellTitleSm)
                                .foregroundStyle(t.textPrimary)
                                .lineSpacing(3)
                        }
                    }
                }
            }
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard let g = session.group.value ?? nil, let day = session.currentDay else { return }
        pulse = .loading
        do {
            pulse = .loaded(try await session.api.insights(groupId: g.id, type: .groupPulse)
                .first { $0.dayInstanceId == day.id })
        } catch { pulse = .failed(error.localizedDescription) }
    }
}
