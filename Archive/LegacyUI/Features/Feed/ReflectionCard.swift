import SwiftUI

struct ReflectionCard: View {
    let reflection: Reflection
    let authorName: String
    var isMine: Bool = false
    var hearts: Int = 0
    var replies: Int = 0
    var hasCompanionReply: Bool = false
    var onTap: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button(action: onTap) {
            Panel {
                VStack(alignment: .leading, spacing: Space.md) {
                    header

                    if reflection.mediaType == .voice {
                        voicePlayer
                    }

                    Text(reflection.displayBody)
                        .font(.dwellBody)
                        .foregroundStyle(reflection.mediaType == .voice ? t.textSecondary : t.textPrimary)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)

                    if let note = translationNote {
                        HStack(spacing: Space.sm) {
                            Rectangle().fill(t.border).frame(width: 2)
                            Text(note)
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Rectangle().fill(t.border).frame(height: 1)
                    footer
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            Avatar(size: 34)
            HStack(spacing: 0) {
                Text(isMine ? "You" : authorName)
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Text(" · \(relativeAge) · \(kindLabel)")
                    .font(.dwellFootnote)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer()
            if reflection.isLate { LateBadge() }
            if translationNote != nil {
                Text("EN")
                    .font(.dwellCaptionMd)
                    .foregroundStyle(t.textSecondary)
            }
        }
    }

    private var voicePlayer: some View {
        HStack(spacing: Space.md) {
            ZStack {
                Circle().fill(t.accentSoft)
                Text("▸").font(.system(size: 13)).foregroundStyle(t.accent)
            }
            .frame(width: 34, height: 34)
            Waveform(seed: abs(reflection.id.hashValue % 9) + 1)
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .background(t.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: Space.lg) {
            Label("\(hearts)", systemImage: "heart")
                .font(.dwellFootnote).foregroundStyle(t.textSecondary)
            Label("\(replies)", systemImage: "bubble")
                .font(.dwellFootnote).foregroundStyle(t.textSecondary)
            Spacer()
            if hasCompanionReply {
                HStack(spacing: 5) {
                    Text("◈")
                    Text(isMine ? "companion wrote back" : "companion replied")
                }
                .font(.dwellFootnote)
                .foregroundStyle(t.accent)
            }
        }
    }

    private var kindLabel: String {
        reflection.mediaType == .voice ? "voice" : languageName
    }

    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: reflection.language)
            ?? reflection.language.uppercased()
    }

    private var translationNote: String? {
        guard reflection.translatedText != nil else { return nil }
        return "Translated from \(languageName)\(reflection.mediaType == .voice ? " · tap to hear their voice" : "")"
    }

    private var relativeAge: String {
        let seconds = Date.now.timeIntervalSince(reflection.createdAt)
        if seconds < 3_600 { return "\(max(Int(seconds / 60), 1))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}
