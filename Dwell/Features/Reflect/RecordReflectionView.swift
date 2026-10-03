import SwiftUI
import PhotosUI

/// "What stood out to you today?" — voice by default, text as the alternative.
///
/// Recording has four visible states (idle, recording, captured, failed), so
/// it's always obvious whether the mic is live. The earlier version showed
/// only a small mic glyph and buried failures in the transcript area.
struct RecordReflectionView: View {
    @Binding var draft: ReflectFlow.Draft
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var speech: SpeechRecognizer?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var preparingPhoto = false
    /// Bumped whenever the composer's intent changes. A photo that finishes
    /// preparing against a stale token is discarded — otherwise picking a
    /// photo, switching to Text, and waiting silently switched you back.
    @State private var captureToken = UUID()
    @FocusState private var typing: Bool

    private var dayIndex: Int { session.currentDay?.dayIndex ?? 1 }
    private var isRecording: Bool { speech?.state == .recording }

    /// While recording, read straight from the recogniser so partial results
    /// appear as they're spoken; afterwards, from the draft.
    private var liveText: String {
        isRecording ? (speech?.transcript ?? "") : draft.body
    }

    private var failure: String? {
        switch speech?.state {
        case .unauthorized(let m), .failed(let m): return m
        default: return nil
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.25)

            VStack(alignment: .leading, spacing: 0) {
                header

                Text("What stood out to you today?")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .lineSpacing(LineSpacing.title)
                    .padding(.top, Space.xl)

                ScrollView {
                    VStack(spacing: Space.lg) {
                        if let failure { failureBanner(failure) }
                        switch draft.mediaType {
                        case .voice: voiceCard
                        case .photo: photoCard
                        case .text:  textCard
                        }
                    }
                    .padding(.top, Space.xl)
                }
                .scrollIndicators(.hidden)

                modeRow.padding(.vertical, Space.lg)

                PrimaryButton(title: "Post to \(session.group.value??.name ?? "the group")",
                              enabled: draft.isPostable && !isRecording) {
                    onNext()
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .simultaneousGesture(TapGesture().onEnded { typing = false })
        .dwellThemed()
        // The recogniser can also finish by itself — the 120s cap, a final
        // result, or an error. Mirroring only on the Stop tap left a captured
        // reflection stranded in those cases.
        .scrollDismissesKeyboard(.immediately)
        // There was no way out of the keyboard at all: the composer fills the
        // screen above it and nothing dismissed it.
        .onChange(of: speech?.state) { _, _ in sync() }
        .onDisappear { speech?.stop() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await preparePhoto(item) }
        }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button(action: { speech?.stop(); onBack() }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            Text("Day \(dayIndex)")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
        }
        .padding(.top, Space.sm)
    }

    // MARK: - Voice

    private var voiceCard: some View {
        VStack(spacing: Space.lg) {
            VoiceWaveform(levels: isRecording ? (speech?.levels ?? []) : draft.levels,
                          seed: 4,
                          height: 56,
                          tint: isRecording ? t.danger : nil)

            if !liveText.isEmpty || isRecording {
                Text(liveText.isEmpty ? "Listening…" : liveText)
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(liveText.isEmpty ? t.textSecondary : t.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.15), value: liveText)
            }

            recordControl
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isRecording ? t.danger.opacity(0.4) : t.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var recordControl: some View {
        VStack(spacing: Space.md) {
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? t.danger : t.accent)
                        .frame(width: 72, height: 72)
                    if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            if isRecording {
                VStack(spacing: 2) {
                    Text("Recording · \(SpeechRecognizer.durationLabel(speech?.duration ?? 0))")
                        .font(.dwellSmallMd)
                        .foregroundStyle(t.danger)
                    Text("\(SpeechRecognizer.durationLabel(speech?.remaining ?? 0)) left")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                    if speech?.isOnDevice == false {
                        // The MVP's "stays on your device" claim doesn't hold
                        // for every language — say so rather than imply it.
                        Text("Transcribed by Apple for this language")
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                    }
                }
            } else if draft.body.isEmpty {
                Text("Tap to record")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            } else {
                Text("\(SpeechRecognizer.durationLabel(draft.duration)) · tap to record again")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            }
        }
    }

    // MARK: - Photo

    /// A photo always needs words with it — the backend rejects one without a
    /// caption, and the caption is what translation and the group pulse use.
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            } else if preparingPhoto {
                ProgressView().frame(maxWidth: .infinity, minHeight: 220)
            }

            TextField("Say what this picture meant today…", text: $draft.body, axis: .vertical)
                .focused($typing)
                .font(.dwellBody)
                .lineLimit(2...6)
                .foregroundStyle(t.textPrimary)

            if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("A photo needs a few words with it.")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private func preparePhoto(_ item: PhotosPickerItem) async {
        // Claim a fresh token first, so an earlier pick still preparing can't
        // finish last and replace this one.
        captureToken = UUID()
        let token = captureToken
        preparingPhoto = true
        defer { preparingPhoto = false; pickedPhoto = nil }
        speech?.stop()
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = ImagePrep.jpeg(from: data) else { return }

        // Loading a photo takes long enough to change your mind during.
        guard token == captureToken else {
            try? FileManager.default.removeItem(at: prepared.fileURL)
            return
        }

        photoImage = UIImage(contentsOfFile: prepared.fileURL.path)
        draft.mediaType = .photo
        draft.attachment = .photo(fileURL: prepared.fileURL, mime: prepared.mime)
        typing = true
    }

    // MARK: - Text

    private var textCard: some View {
        TextEditor(text: $draft.body)
            .focused($typing)
            .font(.dwellBody)
            .foregroundStyle(t.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 240)
            .padding(Space.lg)
            .background(t.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if draft.body.isEmpty {
                    Text("Be honest — no one sees this until they've posted too.")
                        .font(.dwellBody)
                        .foregroundStyle(t.textSecondary)
                        .padding(Space.lg + 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(t.danger)
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(message)
                    .font(.dwellSmall)
                    .foregroundStyle(t.textPrimary)
                Button("Write it instead") {
                    draft.mediaType = .text
                    typing = true
                }
                .font(.dwellSmallMd)
                .foregroundStyle(t.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .background(t.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var modeRow: some View {
        HStack(spacing: Space.xl) {
            PhotoAvatar(name: session.me?.name ?? "You",
                        url: session.me.map { session.avatarURL(for: $0.id) } ?? nil, size: 44)

            modeButton(.voice, icon: "mic")
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 23))
                    .foregroundStyle(draft.mediaType == .photo ? t.accent : t.textPrimary)
            }
            .buttonStyle(PressScale())
            .disabled(preparingPhoto)
            modeButton(.text, icon: "textformat")

            Spacer()
        }
    }

    private func modeButton(_ mode: MediaType, icon: String) -> some View {
        Button {
            guard draft.mediaType != mode else { return }
            speech?.stop()
            // Otherwise a text reflection posts with the audio you recorded
            // before changing your mind, duration and waveform included.
            discardAttachment()
            draft.mediaType = mode
            if mode == .text { typing = true }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 23))
                .foregroundStyle(draft.mediaType == mode ? t.accent : t.textPrimary)
        }
        .buttonStyle(PressScale())
    }

    /// Drops whatever was captured for the previous mode, and the file with it.
    private func discardAttachment() {
        captureToken = UUID()
        if let attachment = draft.attachment {
            try? FileManager.default.removeItem(at: attachment.fileURL)
        }
        draft.attachment = nil
        draft.duration = 0
        draft.levels = []
        photoImage = nil
        speech = nil
    }

    // MARK: - Capture

    private func toggleRecording() async {
        if isRecording {
            speech?.stop()
            sync()
            return
        }
        let recognizer = SpeechRecognizer(languageCode: draft.language)
        speech = recognizer
        await recognizer.start()
        sync()
    }

    /// Mirror the recogniser into the draft so review and posting don't depend
    /// on it still being alive.
    private func sync() {
        guard let speech else { return }
        if !speech.transcript.isEmpty { draft.body = speech.transcript }
        draft.transcribedOnDevice = speech.isOnDevice
        draft.duration = speech.duration
        draft.levels = speech.levels
        if let url = speech.recordingURL, speech.state == .finished {
            draft.attachment = .voice(Recording(fileURL: url,
                                                durationSeconds: Int(speech.duration.rounded()),
                                                peaks: speech.peaks))
        }
    }
}
