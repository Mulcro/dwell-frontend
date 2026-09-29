import SwiftUI

struct ReflectionDetailView: View {
    let reflection: Reflection
    let authorName: String
    var onBack: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var comments: Loadable<[Comment]> = .idle
    @State private var myReactions: Set<String> = []
    @State private var draft = ""
    @State private var sending = false
    @State private var failure: String?

    private var isMine: Bool { reflection.userId == session.me?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(title: "\(isMine ? "You" : authorName) · Day \(session.currentDay?.dayIndex ?? 1)",
                        trailing: "···",
                        onLeading: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if reflection.mediaType == .voice {
                        Panel(padding: Space.md) {
                            HStack(spacing: Space.md) {
                                ZStack {
                                    Circle().fill(t.accentSoft)
                                    Text("▸").font(.system(size: 13)).foregroundStyle(t.accent)
                                }
                                .frame(width: 34, height: 34)
                                Waveform(seed: 5)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Text(reflection.displayBody)
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                        .lineSpacing(7)

                    if let response = reflection.aiResponse {
                        companionNote(response)
                    }

                    commentSection
                }
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            if !isMine { reactionBar }
            composer
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .dwellThemed()
        .task { await load() }
    }

    /// The per-reflection companion response (§6 must-have). Shown on your own
    /// post too — the Figma only ever showed it on other people's.
    private func companionNote(_ text: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    CompanionMark(size: 22)
                    Text(isMine ? "For you" : "For \(authorName)")
                        .font(.dwellFootnoteMd)
                        .foregroundStyle(t.accent)
                }
                Text(text)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .lineSpacing(6)
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            LoadableView(state: comments) { list in
                VStack(alignment: .leading, spacing: Space.lg) {
                    Eyebrow(list.isEmpty ? "No comments yet" : "\(list.count) comment\(list.count == 1 ? "" : "s")")
                    ForEach(list) { comment in
                        HStack(alignment: .top, spacing: Space.md) {
                            Avatar(size: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(session.name(for: comment.userId)) · \(age(comment.createdAt))")
                                    .font(.dwellCaption)
                                    .foregroundStyle(t.textSecondary)
                                Text(comment.content)
                                    .font(.dwellBody)
                                    .foregroundStyle(t.textPrimary)
                                    .lineSpacing(4)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var reactionBar: some View {
        HStack(spacing: Space.sm) {
            ForEach(["♡", "Pray", "Amen"], id: \.self) { emoji in
                PillToggle(title: emoji, selected: myReactions.contains(emoji)) {
                    Task { await toggle(emoji) }
                }
            }
        }
        .padding(.bottom, Space.md)
    }

    private var composer: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                TextField("Say something…", text: $draft)
                    .font(.dwellBody)
                    .foregroundStyle(t.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md + 2)
                    .overlay(Capsule().strokeBorder(t.border, lineWidth: 1))

                if !draft.isEmpty {
                    Button { Task { await send() } } label: {
                        Text(sending ? "…" : "Send")
                            .font(.dwellFootnoteMd)
                            .foregroundStyle(t.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(failure ?? "Reply in your language — they'll read it in theirs.")
                .font(.dwellCaption)
                .foregroundStyle(failure == nil ? t.textTertiary : t.textSecondary)
        }
    }

    private func age(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 3_600 { return "\(max(Int(seconds / 60), 1))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    private func load() async {
        comments = .loading
        do {
            comments = .loaded(try await session.api.comments(reflectionId: reflection.id))
            let mine = try await session.api.reactions(reflectionId: reflection.id)
                .filter { $0.userId == session.me?.id }
            myReactions = Set(mine.map(\.emoji))
        } catch {
            comments = .failed(error.localizedDescription)
        }
    }

    private func toggle(_ emoji: String) async {
        Haptics.select()
        do {
            if myReactions.contains(emoji) {
                try await session.api.removeReaction(reflectionId: reflection.id, emoji: emoji)
                myReactions.remove(emoji)
            } else {
                _ = try await session.api.addReaction(reflectionId: reflection.id, emoji: emoji)
                myReactions.insert(emoji)
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Optimistic: the comment appears immediately and is reconciled with the
    /// server's row when it lands. A failure puts the text back in the field
    /// rather than dropping it.
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let me = session.me else { return }

        let placeholder = Comment(id: UUID(), reflectionId: reflection.id,
                                  userId: me.id, content: text, createdAt: .now)
        let previous = comments.value ?? []
        comments = .loaded(previous + [placeholder])
        draft = ""
        sending = true
        defer { sending = false }

        do {
            _ = try await session.api.addComment(reflectionId: reflection.id, content: text)
            Haptics.tap()
            await load()
        } catch {
            comments = .loaded(previous)
            draft = text
            Haptics.warning()
            failure = error.localizedDescription
        }
    }
}
