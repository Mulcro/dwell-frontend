import SwiftUI

/// One past reflection, in full — with its audio or photo if it had either.
struct MemoryDetailView: View {
    let reflection: Reflection
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var player = RecordingPlayer()
    @State private var photoURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.sm) {
                        Text(dateLabel)
                            .font(.dwellSmallMd)
                            .foregroundStyle(t.textSecondary)
                        if reflection.isLate {
                            Text("Late")
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                                .padding(.horizontal, Space.sm)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(t.border, lineWidth: 1))
                        }
                    }

                    if reflection.hasRecording { audio }
                    if reflection.mediaType == .photo { photo }

                    Text(reflection.displayBody)
                        .font(.dwellBody)
                        .foregroundStyle(t.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let response = reflection.aiResponse, !response.isEmpty {
                        VStack(alignment: .leading, spacing: Space.md) {
                            HStack(spacing: Space.sm) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(t.accent)
                                Text("Eagle wrote back")
                                    .font(.dwellSmallMd)
                                    .foregroundStyle(t.accent)
                            }
                            Text(response)
                                .font(.dwellBody)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.accent.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    }
                }
                .padding(Space.gutter)
            }
            .scrollIndicators(.hidden)
            .background(t.background)
            .navigationTitle(dayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .onDisappear { player.tearDown() }
    }

    private var audio: some View {
        HStack(spacing: Space.md) {
            Button {
                guard let path = reflection.mediaPath else { return }
                Task { await player.toggle(path: path, api: session.api) }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(PressScale())

            VoiceWaveform(levels: (reflection.mediaPeaks ?? []).map { CGFloat($0) / 100 },
                          barCount: 28, height: 24)

            Text(SpeechRecognizer.durationLabel(
                TimeInterval(reflection.mediaDurationSeconds ?? 0)))
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .monospacedDigit()
        }
        .padding(Space.md)
        .background(t.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var photo: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: ZStack { t.surfaceRaised; ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(t.surfaceRaised)
                .frame(height: 240)
                .task {
                    guard let path = reflection.mediaPath else { return }
                    photoURL = try? await session.api.mediaURL(path: path)
                }
        }
    }

    private var dayTitle: String {
        guard let index = session.days.first(where: { $0.id == reflection.dayInstanceId })?.dayIndex
        else { return "Reflection" }
        return "Day \(index)"
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: reflection.createdAt)
    }
}
