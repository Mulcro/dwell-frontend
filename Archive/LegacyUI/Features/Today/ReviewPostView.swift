import SwiftUI

struct ReviewPostView: View {
    let draft: String
    let mediaType: MediaType
    var onBack: () -> Void = {}
    var onPosted: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var posting = false
    @State private var error: String?
    @State private var canRetry = false

    private let handling: [(String, String)] = [
        ("Checked for safety", "Runs before anyone can see it"),
        ("Translated for the group", "Tone preserved — they'll see both"),
        ("Private until the day unlocks", "Nothing shared outside the group")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(onLeading: onBack)

            Text("Review before posting")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .padding(.top, Space.sm)

            Panel {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack {
                        Eyebrow(mediaType == .voice ? "Your voice note" : "Your reflection")
                        Spacer()
                        Text((session.me?.preferredLanguage ?? "en").uppercased())
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                    }
                    if mediaType == .voice { Waveform(seed: 3) }
                    Text(draft)
                        .font(.dwellBody)
                        .foregroundStyle(t.textPrimary)
                        .lineSpacing(5)
                }
            }
            .padding(.top, Space.xl)

            Eyebrow("How it's handled")
                .padding(.top, Space.xl)
                .padding(.bottom, Space.sm)

            VStack(spacing: 0) {
                ForEach(Array(handling.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Space.md) {
                        Text("✓").font(.dwellFootnoteMd).foregroundStyle(t.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).font(.dwellFootnoteMd).foregroundStyle(t.textPrimary)
                            Text(item.1).font(.dwellCaption).foregroundStyle(t.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Space.md)
                    if index < handling.count - 1 {
                        Rectangle().fill(t.border).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            Spacer()

            if let error {
                HStack(alignment: .top, spacing: Space.sm) {
                    Text(error)
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                    if canRetry {
                        Button("Retry") { Task { await post() } }
                            .font(.dwellCaptionMd)
                            .foregroundStyle(t.accent)
                    }
                }
                .padding(.bottom, Space.sm)
            }

            DwellButton(title: posting ? "Posting…" : "Post to \(session.group.value??.name ?? "the group")") {
                Task { await post() }
            }
            .disabled(posting)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .edgeSwipeBack(perform: onBack)
    }

    private func post() async {
        posting = true
        defer { posting = false }
        do {
            try await session.submitReflection(mediaType: mediaType, body: draft)
            Haptics.posted()
            UserDefaults.standard.removeObject(forKey: "compose.draft")
            onPosted()
        } catch let dwellError as DwellError {
            Haptics.warning()
            self.error = dwellError.localizedDescription
            self.canRetry = dwellError.isRetryable
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}
