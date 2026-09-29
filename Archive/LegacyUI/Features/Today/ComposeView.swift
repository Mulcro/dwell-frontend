import SwiftUI

struct ComposeView: View {
    let passage: Passage
    let day: DayInstance
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var mode: MediaType = .text
    /// Drafts survive backing out of compose — losing a half-written
    /// reflection is the worst small failure this app could have.
    @AppStorage("compose.draft") private var body_ = ""
    @State private var showReview = false

    private var prompt: String {
        "Where did \u{201C}\(Seed.dayThemes[passage.ref] ?? "this")\u{201D} land for you today?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(leading: "✕", trailing: "Only you can see this", onLeading: onClose)

            Text(prompt)
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .lineSpacing(2)
                .padding(.top, Space.sm)

            HStack(spacing: Space.sm) {
                PillToggle(title: "Voice", selected: mode == .voice) {
                    Haptics.select(); mode = .voice
                }
                PillToggle(title: "Text", selected: mode == .text) {
                    Haptics.select(); mode = .text
                }
                PillToggle(title: session.me?.preferredLanguage.uppercased() ?? "EN",
                           selected: false, trailingChevron: true)
            }
            .padding(.top, Space.lg)

            capture
                .padding(.top, Space.lg)

            DwellButton(title: "Review before posting") {
                Haptics.tap()
                showReview = true
            }
                .padding(.top, Space.lg)
                .disabled(body_.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(body_.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Text("Posting unlocks the day for you and counts toward the group.")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Space.md)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .edgeSwipeBack(perform: onClose)
        .fullScreenCover(isPresented: $showReview) {
            ReviewPostView(draft: body_, mediaType: mode,
                           onBack: { showReview = false },
                           onPosted: { showReview = false; onClose() })
        }
    }

    @ViewBuilder
    private var capture: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(t.surface)

            if mode == .voice {
                VStack(spacing: Space.lg) {
                    RecordingMeter()
                    Text("hold to keep talking")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Text(body_.isEmpty ? "transcript appears here as you speak" : body_)
                        .font(body_.isEmpty ? .dwellMonoSm : .dwellBody)
                        .foregroundStyle(body_.isEmpty ? t.textTertiary : t.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.lg)
                    // Transcription is on-device Apple Speech; this stands in
                    // until the recognizer is wired.
                    Button("Simulate transcript") {
                        body_ = "I keep reading “anchor” and thinking about how much of this week I spent drifting."
                    }
                    .font(.dwellCaption)
                    .foregroundStyle(t.accent)
                }
                .padding(Space.lg)
            } else {
                TextEditor(text: $body_)
                    .scrollDismissesKeyboard(.interactively)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Space.md)
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("Say the true thing, not the tidy one.")
                                .font(.dwellBody)
                                .foregroundStyle(t.textTertiary)
                                .padding(Space.lg)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
