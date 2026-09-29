import SwiftUI

struct ReaderView: View {
    let passage: Passage
    let day: DayInstance
    var onClose: () -> Void = {}
    @Environment(\.dwell) private var t
    @State private var showCompose = false
    @State private var playing = false
    @State private var textScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(leading: "✕",
                        title: "\(passage.reference) · \(passage.translation)",
                        trailing: "Aa",
                        onLeading: onClose,
                        onTrailing: { textScale = textScale > 1.1 ? 1 : 1.25 })

            audioBar

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    ForEach(passage.verses) { verse in
                        verseView(verse)
                    }
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            DwellButton(title: "Reflect on this") {
                Haptics.tap()
                showCompose = true
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .edgeSwipeBack(perform: onClose)
        .fullScreenCover(isPresented: $showCompose) {
            ComposeView(passage: passage, day: day, onClose: {
                showCompose = false
                onClose()
            })
        }
    }

    /// Audio Bible listen-along. The Passages/Audio API is a named MVP
    /// integration; transport is here, the player is stubbed until the
    /// endpoint is wired. DESIGN: invented — no Figma source.
    private var audioBar: some View {
        HStack(spacing: Space.md) {
            Button { playing.toggle() } label: {
                ZStack {
                    Circle().fill(t.accentWash)
                    Text(playing ? "❚❚" : "▸")
                        .font(.system(size: 12))
                        .foregroundStyle(t.accent)
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(playing ? "Playing" : "Listen along")
                    .font(.dwellCaptionMd)
                    .foregroundStyle(t.textPrimary)
                Text(passage.audioURL == nil ? "Audio arrives with the API" : "Audio Bible")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textTertiary)
            }
            Spacer()
            Text(passage.readTimeLabel)
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
        }
        .padding(Space.md)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .opacity(passage.audioURL == nil ? 0.75 : 1)
    }

    private func verseView(_ verse: Passage.Verse) -> some View {
        Group {
            if let number = verse.number {
                Text(number)
                    .font(DwellFont.serif(13 * textScale))
                    .baselineOffset(7)
                    .foregroundStyle(t.textSecondary)
                + Text(" " + verse.text)
                    .font(DwellFont.serif(21 * textScale))
                    .foregroundStyle(t.textPrimary)
            } else {
                Text(verse.text)
                    .font(DwellFont.serif(21 * textScale))
                    .foregroundStyle(t.textPrimary)
            }
        }
        .lineSpacing(9)
    }
}
