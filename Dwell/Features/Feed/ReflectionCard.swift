import SwiftUI

/// One reflection, as it appears in the day feed and at the top of a thread.
///
/// Media is drawn but inert: audio and photos have nowhere to live yet
/// (`media_path` and the `reflection-media` bucket are Notion items 35–41), so
/// a voice note shows its transcript and a disabled player rather than
/// pretending it can play.
struct ReflectionCard: View {
    let reflection: Reflection
    let authorName: String
    var avatarURL: URL?
    var isMine: Bool = false
    /// Thread shows the whole thing; the feed truncates.
    var expanded: Bool = false
    var onExpand: (() -> Void)?
    var onReply: (() -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var showingOriginal = false
    @State private var player = RecordingPlayer()
    @State private var photoURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            header

            if reflection.mediaType == .voice { voicePlayer }
            if reflection.mediaType == .photo { photo }

            Text(bodyText)
                .font(.dwellBody)
                .foregroundStyle(t.textPrimary)
                .lineLimit(expanded ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            translationNote

            if let onReply {
                PrimaryButton(title: "Reply", compact: true, action: onReply)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            PhotoAvatar(name: authorName, url: avatarURL, size: 56)
            Text(isMine ? "You" : authorName)
                .font(.dwellBodyMd)
                .foregroundStyle(t.textPrimary)
            Spacer(minLength: Space.sm)
            Text(relativeAge)
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(t.textPrimary)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Open thread")
            }
        }
    }

    /// Plays the recording when there is one. Reflections posted before audio
    /// storage shipped have no object, so those still read as transcript-only
    /// — there is nothing to recover for them.
    @ViewBuilder
    private var voicePlayer: some View {
        if let path = reflection.mediaPath, !path.isEmpty {
            HStack(spacing: Space.lg) {
                Button {
                    Task { await player.toggle(path: path, api: session.api) }
                } label: {
                    ZStack {
                        Circle().fill(t.surfaceRaised)
                        if player.isLoading {
                            ProgressView().tint(t.textPrimary)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(t.textPrimary)
                        }
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play reflection")

                // Drawn from the stored peaks when present, so nothing has to
                // download the audio just to render bars.
                VoiceWaveform(levels: storedPeaks,
                              seed: abs(reflection.id.hashValue % 11) + 1,
                              height: 44)

                Spacer(minLength: 0)

                if let seconds = reflection.mediaDurationSeconds {
                    Text(SpeechRecognizer.durationLabel(TimeInterval(seconds)))
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                }
            }
            .onDisappear { player.tearDown() }

            if player.failed {
                Text("Couldn't load the recording.")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
        } else {
            HStack(spacing: Space.md) {
                ZStack {
                    Circle().fill(t.surfaceRaised)
                    Image(systemName: "waveform")
                        .font(.system(size: 17))
                        .foregroundStyle(t.textSecondary)
                }
                .frame(width: 40, height: 40)

                VoiceWaveform(seed: abs(reflection.id.hashValue % 11) + 1, height: 28)
                    .opacity(0.5)

                Text("Transcript only")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spoken reflection with no recording — the transcript is below.")
        }
    }

    /// `media_peaks` are 0–100 whole numbers; the waveform wants 0–1.
    private var storedPeaks: [CGFloat] {
        (reflection.mediaPeaks ?? []).map { CGFloat($0) / 100 }
    }

    /// Photos share the reflection bucket with audio, so they inherit the same
    /// unlock rule — the signed URL is simply refused until the day is earned.
    @ViewBuilder
    private var photo: some View {
        if let url = photoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder(systemImage: "exclamationmark.triangle",
                                caption: "Couldn't load the photo")
                default:
                    ZStack { t.surfaceRaised; ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            placeholder(systemImage: "photo", caption: "Photo unavailable")
                .frame(height: 200)
                .task { await loadPhoto() }
        }
    }

    private func placeholder(systemImage: String, caption: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(t.surfaceRaised)
            VStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .foregroundStyle(t.textSecondary)
                Text(caption)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
        }
    }

    private func loadPhoto() async {
        guard photoURL == nil, let path = reflection.mediaPath, !path.isEmpty else { return }
        photoURL = try? await session.api.mediaURL(path: path)
    }

    private var bodyText: String {
        if showingOriginal { return reflection.displayBody }
        return translation ?? reflection.displayBody
    }

    /// `translated_text` is keyed by the language translated **into**, and the
    /// row's own `language` says what `content`/`transcript` are written in.
    ///
    /// This used to look up `translations[reflection.language]` — the author's
    /// own language, which is never a key in there — so a translation existed
    /// in the row and was never shown.
    private var translation: String? {
        guard reflection.language != viewerLanguage else { return nil }
        return reflection.translatedText?[viewerLanguage]
    }

    /// Set from the device locale at sign-up and editable in Settings.
    private var viewerLanguage: String { session.me?.preferredLanguage ?? "en" }

    /// Only shown when there is actually another language to switch to.
    @ViewBuilder
    private var translationNote: some View {
        if translation != nil {
            HStack(spacing: 4) {
                Text(showingOriginal
                     ? "Showing original"
                     : "Translated from \(languageName)")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                if expanded {
                    Text("·").foregroundStyle(t.textSecondary)
                    Button(showingOriginal ? "See translation" : "See original") {
                        withAnimation(.easeInOut(duration: 0.15)) { showingOriginal.toggle() }
                    }
                    .font(.dwellBody)
                    .foregroundStyle(t.accent)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: reflection.language)
            ?? reflection.language.uppercased()
    }

    private var relativeAge: String {
        let seconds = Date.now.timeIntervalSince(reflection.createdAt)
        if seconds < 3_600 {
            let m = max(Int(seconds / 60), 1)
            return "\(m) minute\(m == 1 ? "" : "s") ago"
        }
        if seconds < 86_400 {
            let h = Int(seconds / 3_600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = Int(seconds / 86_400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }
}
