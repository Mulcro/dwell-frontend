import SwiftUI

/// Fires after 3 consecutive days with no posts from anyone (§4.5). Shown
/// once to every member; the answer calls `/group-challenge-action`.
///
/// DESIGN: invented — no Figma source.
struct InactivityPromptView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var working: ChallengeAction?
    @State private var error: String?

    private let options: [(ChallengeAction, String, String)] = [
        (.continue, "Keep going", "Pick up at the day you're on. Nothing is marked missed."),
        (.pause,    "Pause for now", "Everything freezes — no days advance, no nudges. Resume whenever."),
        (.end,      "End the challenge", "Archive it. You keep everything you wrote.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow(session.group.value??.name ?? "Your group")
                        Text("It's been quiet\nfor a few days.")
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)
                            .lineSpacing(2)
                        Text("Nobody's posted since Thursday. That's allowed — life happens. What do you want to do with it?")
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(5)
                    }

                    VStack(spacing: Space.md) {
                        ForEach(options, id: \.0) { action, title, detail in
                            Button { Task { await respond(action) } } label: {
                                Panel(accented: action == .continue) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(title)
                                                .font(.dwellBodyMd)
                                                .foregroundStyle(action == .continue ? t.accent : t.textPrimary)
                                            Text(detail)
                                                .font(.dwellCaption)
                                                .foregroundStyle(t.textSecondary)
                                                .multilineTextAlignment(.leading)
                                                .lineSpacing(3)
                                        }
                                        Spacer()
                                        if working == action {
                                            ProgressView().tint(t.textTertiary)
                                        } else {
                                            Text("›").foregroundStyle(t.textTertiary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(working != nil)
                        }
                    }

                    if let error {
                        Text(error).font(.dwellCaption).foregroundStyle(t.textSecondary)
                    }

                    Text("Whatever you pick, everyone in the group sees the same choice once.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textTertiary)
                        .lineSpacing(3)
                }
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
    }

    private func respond(_ action: ChallengeAction) async {
        working = action
        defer { working = nil }
        do { try await session.respondToInactivity(action) }
        catch { self.error = error.localizedDescription }
    }
}

/// `challenge_status = paused`. Nothing advances, nothing nudges.
/// DESIGN: invented — no Figma source.
struct PausedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var resuming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()

            VStack(alignment: .leading, spacing: Space.sm) {
                Eyebrow(session.group.value??.name ?? "Your group")
                Text("Paused.")
                    .font(.dwellDisplay)
                    .foregroundStyle(t.textPrimary)
                Text("No days are advancing and nobody's being nudged. Everything you've written is still here, exactly where you left it.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .lineSpacing(5)
            }

            DwellButton(title: resuming ? "Resuming…" : "Pick it back up") {
                Task {
                    resuming = true
                    try? await session.respondToInactivity(.continue)
                    resuming = false
                }
            }

            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.xl)
    }
}
