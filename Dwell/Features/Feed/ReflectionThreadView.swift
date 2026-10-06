import SwiftUI
import PhotosUI

/// One reflection, Eagle's reply to it, and the comment thread.
///
/// Eagle's note is collapsed behind "Show" by design — the companion speaks
/// second, after the person, and shouldn't crowd out what they wrote.
struct ReflectionThreadView: View {
    let reflection: Reflection
    let authorName: String
    /// The reply a push was about: scrolled to and briefly highlighted.
    var highlightCommentId: UUID? = nil
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var comments: Loadable<[Comment]> = .idle
    @State private var showCompanion = false
    @State private var draft = ""
    @State private var sending = false
    @State private var mediaSupported = false
    @State private var attachment: MediaAttachment?
    @State private var attachmentPeaks: [CGFloat] = []
    @State private var attachmentDuration: TimeInterval = 0
    @State private var photoPreview: UIImage?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var speech: SpeechRecognizer?
    @State private var captureToken = UUID()
    @State private var toast: Toast?
    @State private var flashing: UUID?
    @FocusState private var writing: Bool

    private var isMine: Bool { reflection.userId == session.me?.id }

    /// Set from the device locale at sign-up, editable in Settings.
    private var viewerLanguage: String { session.me?.preferredLanguage ?? "en" }

    /// Always detect from the words themselves, whatever produced them.
    ///
    /// Trusting the recogniser's locale for voice was wrong for the same
    /// reason trusting `preferred_language` was: someone with an English app
    /// can speak Spanish, and the recogniser's configuration says what it was
    /// *listening* for, not what was said. The locale stays as the fallback
    /// for text too short to judge.
    private func composedLanguage(_ text: String) -> String {
        LanguageDetect.dominant(of: text, fallback: viewerLanguage)
    }

    private func languageName(_ code: String?) -> String {
        guard let code else { return "another language" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 280, fadeFrom: 0.25)

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        ReflectionCard(reflection: reflection,
                                       authorName: authorName,
                                       avatarURL: session.avatarURL(for: reflection.userId),
                                       isMine: isMine,
                                       expanded: true,
                                       onReply: { writing = true })

                        if reflection.aiResponse != nil { companion }

                        commentSection
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xl)
                }
                .scrollIndicators(.hidden)
                .onChange(of: comments.value?.count) { _, _ in
                    scrollToHighlight(proxy)
                }
                }
                // Dismissal lives on the scroll content, not the whole
                // screen, so a tap inside the reply field to move the cursor
                // doesn't close the keyboard out from under it.
                .simultaneousGesture(TapGesture().onEnded { writing = false })

                composer
            }
        }
        .dwellThemed()
        .scrollDismissesKeyboard(.immediately)
        .toast($toast)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            Spacer()
            // No avatar here: this screen is about someone else's reflection,
            // and your own face in the corner says nothing about it.
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    /// `ai_response` is a column on the reflection — the companion's note is
    /// per-reflection, not one of the group-wide `ai_insights` rows.
    @ViewBuilder
    private var companion: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showCompanion.toggle() }
            } label: {
                HStack(spacing: Space.md) {
                    // Active until the reply is opened.
                    EagleAvatar(mood: showCompanion ? .resting : .active, size: 36)

                    Text("Eagle replied to \(isMine ? "you" : authorName)")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.accent)
                    Spacer()
                    Text(showCompanion ? "Hide" : "Show")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(PressScale())

            if showCompanion, let response = reflection.companionResponse(in: viewerLanguage) {
                Text(response)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .padding(.horizontal, Space.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var commentSection: some View {
        LoadableView(state: comments, retry: { Task { await load() } }) { list in
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(list.isEmpty ? "No comments yet"
                                  : "\(list.count) comment\(list.count == 1 ? "" : "s")")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)

                ForEach(list) { comment in
                    commentRow(comment)
                        .id(comment.id)
                        .padding(Space.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(t.accent.opacity(flashing == comment.id ? 0.14 : 0))
                        )
                        .padding(-Space.sm)
                }
            }
        }
    }

    /// Brings the pushed reply into view and lights it for a moment, so it's
    /// clear which one the notification meant. Falls back to the top when
    /// the reply isn't there (deleted, or not loaded).
    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let target = highlightCommentId,
              comments.value?.contains(where: { $0.id == target }) == true else { return }
        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
        withAnimation(.easeIn(duration: 0.2)) { flashing = target }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.6)) { flashing = nil }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
                    HStack(alignment: .top, spacing: Space.md) {
                        PhotoAvatar(name: session.memberProfiles[comment.userId]?.name ?? "Member",
                                    url: session.avatarURL(for: comment.userId),
                                    size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Space.sm) {
                                Text(session.name(for: comment.userId))
                                    .font(.dwellBodyMd)
                                    .foregroundStyle(t.textPrimary)
                                Text(age(comment.createdAt))
                                    .font(.dwellSmall)
                                    .foregroundStyle(t.textSecondary)
                            }
                            if comment.hasRecording || comment.hasPhoto {
                                CommentMedia(comment: comment)
                                    .padding(.top, Space.sm)
                                    .padding(.bottom, comment.body.isEmpty ? 0 : Space.sm)
                            }
                            Text(comment.body(in: viewerLanguage))
                                .font(.dwellBody)
                                .foregroundStyle(t.textPrimary)
                            if comment.isTranslated(for: viewerLanguage) {
                                Text("Translated from \(languageName(comment.language))")
                                    .font(.dwellCaption)
                                    .foregroundStyle(t.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
    }

    private var composer: some View {
        VStack(spacing: Space.md) {
            stagedPreview
            if isRecording { recordingStrip }

            HStack(spacing: Space.md) {
                PhotoAvatar(name: session.me?.name ?? "You",
                            url: session.me.map { session.avatarURL(for: $0.id) } ?? nil, size: 44)

                TextField(placeholder, text: $draft, axis: .vertical)
                    .focused($writing)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(1...4)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md + 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )

                // Media buttons appear only once the backend can store them.
                if mediaSupported && attachment == nil {
                    Button { Task { await toggleRecording() } } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                            .font(.system(size: 22))
                            .foregroundStyle(isRecording ? t.danger : t.textPrimary)
                    }
                    .buttonStyle(PressScale())

                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 21))
                            .foregroundStyle(t.textPrimary)
                    }
                    .buttonStyle(PressScale())
                    .disabled(isRecording)
                }

                if canSend {
                    Button { Task { await send() } } label: {
                        Image(systemName: sending ? "ellipsis" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(t.accent)
                    }
                    .buttonStyle(PressScale())
                    .disabled(sending)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.md)
        .background(t.background)
        .overlay(alignment: .top) { Divider().overlay(t.border) }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await stagePhoto(item) }
        }
        // The recogniser can stop itself at the 120s cap or on a final result;
        // capturing only on the Stop tap loses the recording in those cases.
        .onChange(of: speech?.state) { _, state in
            guard state == .finished else { return }
            captureRecording()
        }
    }

    /// Mirrors a finished recording into the staged attachment.
    private func captureRecording() {
        guard attachment == nil, let speech, let url = speech.recordingURL else { return }
        attachmentDuration = speech.duration
        attachmentPeaks = speech.levels
        attachment = .voice(Recording(fileURL: url,
                                      durationSeconds: Int(attachmentDuration.rounded()),
                                      peaks: speech.peaks))
        if draft.isEmpty, !speech.transcript.isEmpty { draft = speech.transcript }
    }

    private var placeholder: String {
        switch attachment {
        case .photo: return "Add a few words…"
        case .voice: return "Add a note (optional)"
        case nil:    return "Write your response"
        }
    }

    private var isRecording: Bool { speech?.state == .recording }

    /// A voice reply may stand on its own; a photo needs words, matching the
    /// rule reflections already follow.
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch attachment {
        case .voice: return true
        case .photo: return hasText
        case nil:    return hasText
        }
    }

    @ViewBuilder
    private var stagedPreview: some View {
        if let attachment {
            HStack(spacing: Space.md) {
                switch attachment {
                case .voice:
                    Image(systemName: "waveform")
                        .foregroundStyle(t.accent)
                    VoiceWaveform(levels: attachmentPeaks, barCount: 28, height: 22)
                    Text(SpeechRecognizer.durationLabel(attachmentDuration))
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                        .monospacedDigit()
                        .fixedSize()
                case .photo:
                    if let photoPreview {
                        Image(uiImage: photoPreview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    Text("Photo attached")
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                    Spacer(minLength: 0)
                }

                Button { discardAttachment() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(t.textSecondary)
                }
                .buttonStyle(PressScale())
            }
            .padding(Space.md)
            .background(t.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var recordingStrip: some View {
        HStack(spacing: Space.md) {
            Circle().fill(t.danger).frame(width: 8, height: 8)
            VoiceWaveform(levels: speech?.levels ?? [], barCount: 28, height: 22,
                          tint: t.accent, live: true)
            Text(SpeechRecognizer.durationLabel(speech?.remaining ?? 0) + " left")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .monospacedDigit()
        }
        .padding(Space.md)
        .background(t.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func toggleRecording() async {
        if isRecording {
            speech?.stop()
            // The encoder is flushed on stop, so the file is only valid now.
            captureRecording()
            return
        }
        writing = false
        let recognizer = SpeechRecognizer(languageCode: session.me?.preferredLanguage ?? "en")
        speech = recognizer
        await recognizer.start()
        if case .failed(let message) = recognizer.state { toast = .failure(message) }
        if case .unauthorized(let message) = recognizer.state { toast = .failure(message) }
    }

    private func stagePhoto(_ item: PhotosPickerItem) async {
        // Claim a fresh token first: two picks in quick succession otherwise
        // share one, and the slower preparation finishes last and overwrites
        // the newer choice.
        captureToken = UUID()
        let token = captureToken
        defer { pickedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ImagePrep.jpeg(from: data) else {
            toast = .failure("That image couldn't be read.")
            return
        }
        // Discarded while it was loading — don't bring it back.
        guard token == captureToken else {
            try? FileManager.default.removeItem(at: prepared.fileURL)
            return
        }
        photoPreview = UIImage(contentsOfFile: prepared.fileURL.path)
        attachment = .photo(fileURL: prepared.fileURL, mime: prepared.mime)
        writing = true
    }

    private func discardAttachment() {
        captureToken = UUID()
        if let attachment { try? FileManager.default.removeItem(at: attachment.fileURL) }
        attachment = nil
        photoPreview = nil
        attachmentPeaks = []
        attachmentDuration = 0
        speech = nil
    }

    private func age(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 3_600 { return "\(max(Int(seconds / 60), 1))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    private func load() async {
        if !mediaSupported { mediaSupported = await session.api.commentMediaSupported() }
        comments = .loading
        do { comments = .loaded(try await session.api.comments(reflectionId: reflection.id)) }
        catch { comments = .failed(error.localizedDescription) }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        sending = true
        defer { sending = false }
        if attachment != nil { toast = .working("Sending…") }
        do {
            try await session.api.addComment(
                reflectionId: reflection.id,
                content: text,
                attachment: attachment,
                transcript: attachment.map { if case .voice = $0 { return text } else { return nil } } ?? nil,
                language: composedLanguage(text))
            discardAttachment()
            draft = ""
            toast = nil
            Haptics.tap()
            await load()
        } catch {
            Haptics.warning()
            toast = .failure(error.localizedDescription)
        }
    }
}
