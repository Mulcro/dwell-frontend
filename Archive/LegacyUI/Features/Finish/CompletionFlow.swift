import SwiftUI

/// `challenge_status = completed` — the celebration, then the AI growth
/// summary (`end_summary`).
struct CompletionFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var showJourney = false

    var body: some View {
        if showJourney {
            JourneyView(onClose: { showJourney = false })
        } else {
            CompletionView(onContinue: { showJourney = true })
        }
    }
}

struct CompletionView: View {
    var onContinue: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var dayCount: Int { session.plan?.dayCount ?? 7 }

    var body: some View {
        ZStack {
            ImagePlaceholder("closing image — evening light", radius: 0, alignment: .leading)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Eyebrow("Day \(dayCount) of \(dayCount)")

                Text("You finished it\ntogether.")
                    .font(.dwellDisplay)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.sm)

                Text("All \(session.members.count) of you posted on the last day.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .lineSpacing(5)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xxl)

                DwellButton(title: "See what these \(dayCount) days held", action: onContinue)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
    }
}

/// The end-of-challenge AI growth summary (§6).
struct JourneyView: View {
    var onClose: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var summary: Loadable<AIInsight?> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(leading: "✕",
                        title: session.plan?.title.components(separatedBy: ":").first,
                        trailing: "↑",
                        onLeading: onClose)

            LoadableView(state: summary, retry: { Task { await load() } }) { insight in
                if let insight { content(insight) }
                else {
                    EmptyStateView(title: "Still writing it",
                                   message: "Your summary lands shortly after the last day closes.")
                }
            }

            HStack(spacing: Space.sm) {
                DwellButton(title: "Start a new challenge")
                DwellButton(title: "Save", kind: .secondary).frame(width: 96)
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
                    Eyebrow("Your journey")
                    Text(chunks.first ?? "")
                        .font(.dwellTitle)
                        .foregroundStyle(t.textPrimary)
                        .lineSpacing(3)
                }

                ForEach(Array(chunks.dropFirst().enumerated()), id: \.offset) { _, paragraph in
                    Panel {
                        Text(paragraph)
                            .font(.dwellBody)
                            .foregroundStyle(t.textPrimary)
                            .lineSpacing(5)
                    }
                }
            }
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard let g = session.group.value ?? nil else { return }
        summary = .loading
        do {
            summary = .loaded(try await session.api.insights(groupId: g.id, type: .endSummary).first)
        } catch { summary = .failed(error.localizedDescription) }
    }
}
