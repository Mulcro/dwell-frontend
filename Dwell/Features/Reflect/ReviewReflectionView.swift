import SwiftUI

/// "How It's Handled" — what happens to the reflection once posted.
///
/// These are promises about the pipeline, not results: moderation and
/// translation run server-side inside `submit-reflection`, so none of it has
/// happened yet when this screen is shown (Notion item 26e).
struct ReviewReflectionView: View {
    let draft: ReflectFlow.Draft
    var onBack: () -> Void = {}
    var onPosted: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var posting = false
    @State private var player = RecordingPlayer()
    @State private var toast: Toast?
    @State private var error: String?

    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: draft.language)
            ?? draft.language.uppercased()
    }

    /// Only claim what actually happens to *this* reflection. A text post was
    /// never transcribed, so showing "Transcribed · English" over something
    /// the user typed is simply untrue.
    private var handled: [(icon: String, title: String, detail: String)] {
        var rows: [(String, String, String)] = []
        if draft.mediaType == .voice {
            rows.append(("waveform", "Transcribed",
                         draft.transcribedOnDevice
                         ? "\(languageName), on this device"
                         : "\(languageName), by Apple's service"))
        }
        rows.append(("character.bubble", "Translated for the group",
                     "Written in \(languageName) — members read it in theirs"))
        rows.append(("checkmark.shield", "Safety check",
                     "Nothing shared outside the group"))
        return rows
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.25)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(t.textPrimary)
                    }
                    .buttonStyle(PressScale())
                    Spacer()
                }
                .padding(.top, Space.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        card

                        VStack(alignment: .leading, spacing: Space.md) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("How It's Handled")
                                    .font(.dwellCardTitleStrong)
                                    .foregroundStyle(t.textPrimary)
                                Spacer()
                                // The language is the user's own
                                // `preferred_language`, seeded from the device
                                // — not something the group owner sets. Say
                                // where it's changed, since Settings owns it.
                                Text("Change in Settings")
                                    .font(.dwellCaption)
                                    .foregroundStyle(t.textSecondary)
                            }

                            ForEach(Array(handled.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: Space.lg) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(t.surfaceRaised)
                                        Image(systemName: item.icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(t.textPrimary)
                                    }
                                    .frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.dwellBodyMd)
                                            .foregroundStyle(t.textPrimary)
                                        Text(item.detail)
                                            .font(.dwellBody)
                                            .foregroundStyle(t.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(Space.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(t.background)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                        .strokeBorder(t.border, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xl)
                }
                .scrollIndicators(.hidden)

                if let error {
                    Text(error)
                        .font(.dwellSmall)
                        .foregroundStyle(t.danger)
                        .padding(.bottom, Space.sm)
                }

                PrimaryButton(title: "Post to \(session.group.value??.name ?? "the group")",
                              loading: posting) {
                    Task { await post() }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .dwellThemed()
        .toast($toast)
        .onDisappear { player.tearDown() }
    }

    private var card: some View {
        VoiceNoteCard(levels: draft.levels,
                      duration: SpeechRecognizer.durationLabel(draft.duration),
                      isPlaying: player.isPlaying,
                      onPlay: playAction) {
            HStack(alignment: .top, spacing: Space.md) {
                Text(draft.body)
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(4)
                Spacer(minLength: 0)
                if draft.mediaType == .voice {
                    Text(SpeechRecognizer.durationLabel(draft.duration))
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                }
            }
        }
    }

    /// Hearing it back before posting only makes sense when there's a file —
    /// a text reflection gets no transport at all.
    private var playAction: (() -> Void)? {
        guard draft.mediaType == .voice,
              case .voice(let recording)? = draft.attachment else { return nil }
        let url = recording.fileURL
        return { Task { await player.toggle(fileURL: url) } }
    }

    private func post() async {
        posting = true
        // With media attached this uploads the file, runs moderation and
        // generates the companion response before returning — long enough that
        // a button spinner alone reads as a hang.
        toast = .working(draft.attachment == nil ? "Posting…" : "Uploading your reflection…")
        defer { posting = false }
        do {
            try await session.submitReflection(mediaType: draft.mediaType,
                                               body: draft.body,
                                               attachment: draft.attachment)
            Haptics.posted()
            toast = nil
            onPosted()
        } catch {
            Haptics.warning()
            toast = .failure(error.localizedDescription)
            self.error = error.localizedDescription
        }
    }
}

/// The 402×278 confirmation sheet: "Reflection posted!" with progress.
struct PostedConfirmationView: View {
    var onDone: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    private var completed: Int {
        session.days.filter { $0.status == .complete || $0.status == .thresholdMet }.count + 1
    }

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            VStack(spacing: Space.sm) {
                Text("Reflection posted!")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                Text("\(completed) of \(session.plan?.dayCount ?? 7) days completed")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
            }

            VStack(spacing: Space.md) {
                PrimaryButton(title: "Yay!", accent: true, action: onDone)
                SecondaryButton(title: "Nudge Group", action: onDone)
            }

            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.background)
        .dwellThemed()
    }
}
