import SwiftUI

/// The lighter "here's how far you got" recap (`fallback_recap`), shown when a
/// challenge ends abandoned or expired-incomplete with little content —
/// instead of the full growth summary (§4.5 Closure).
///
/// DESIGN: invented — no Figma source.
struct FallbackRecapView: View {
    let status: ChallengeStatus
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var recap: Loadable<AIInsight?> = .idle

    private var headline: String {
        status == .abandoned ? "You called it.\nThat counts too." : "This one ran out\nof road."
    }

    private var subline: String {
        status == .abandoned
            ? "You ended the challenge together. Everything written is kept."
            : "It went quiet for two weeks, so we closed it out rather than leaving it hanging."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow(status == .abandoned ? "Ended" : "Closed out")
                        Text(headline)
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)
                            .lineSpacing(2)
                        Text(subline)
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(5)
                    }

                    LoadableView(state: recap, retry: { Task { await load() } }) { insight in
                        if let insight {
                            Panel {
                                VStack(alignment: .leading, spacing: Space.md) {
                                    HStack(spacing: Space.sm) {
                                        CompanionMark(size: 22)
                                        Eyebrow("How far you got", color: t.accent)
                                    }
                                    Text(insight.content)
                                        .font(.dwellBody)
                                        .foregroundStyle(t.textPrimary)
                                        .lineSpacing(5)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        Eyebrow("What's kept")
                        ForEach(["Every reflection you wrote", "Your streak and history", "The days the group opened"], id: \.self) { item in
                            HStack(spacing: Space.md) {
                                Text("✓").font(.dwellFootnoteMd).foregroundStyle(t.success)
                                Text(item).font(.dwellBody).foregroundStyle(t.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)

            DwellButton(title: "Start something new")
            Text("Archived groups stay readable forever. Nobody can post into them again.")
                .font(.dwellCaption)
                .foregroundStyle(t.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.md)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .task { await load() }
    }

    private func load() async {
        guard let g = session.group.value ?? nil else { return }
        recap = .loading
        do { recap = .loaded(try await session.api.insights(groupId: g.id, type: .fallbackRecap).first) }
        catch { recap = .failed(error.localizedDescription) }
    }
}
