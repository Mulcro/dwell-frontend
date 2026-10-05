import SwiftUI

/// Audio or a photo attached to a reply.
///
/// Replies live in the same bucket as reflections, so they inherit the same
/// unlock rule: the signed URL is simply refused until the day is earned, and
/// there is nothing extra to check here.
struct CommentMedia: View {
    let comment: Comment

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var player = RecordingPlayer()
    @State private var photoURL: URL?

    var body: some View {
        Group {
            if comment.hasRecording {
                voice
            } else if comment.hasPhoto {
                photo
            }
        }
        .onDisappear { player.tearDown() }
    }

    private var voice: some View {
        HStack(spacing: Space.md) {
            Button {
                guard let path = comment.mediaPath else { return }
                Task { await player.toggle(path: path, api: session.api) }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(PressScale())

            VoiceWaveform(levels: levels, barCount: 24, height: 20)

            Text(SpeechRecognizer.durationLabel(TimeInterval(comment.mediaDurationSeconds ?? 0)))
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(Space.md)
        .background(t.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Stored peaks are 0–100 whole numbers; the waveform wants 0–1.
    private var levels: [CGFloat] {
        (comment.mediaPeaks ?? []).map { CGFloat($0) / 100 }
    }

    @ViewBuilder
    private var photo: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure:            fallback("Couldn't load the photo")
                default:                  ZStack { t.surfaceRaised; ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            fallback("Loading photo…")
                .frame(height: 180)
                .task {
                    guard let path = comment.mediaPath else { return }
                    photoURL = try? await session.api.mediaURL(path: path)
                }
        }
    }

    private func fallback(_ caption: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(t.surfaceRaised)
            Text(caption).font(.dwellCaption).foregroundStyle(t.textSecondary)
        }
    }
}
