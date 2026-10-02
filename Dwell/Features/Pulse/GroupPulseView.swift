import SwiftUI

/// The companion's read on the day, once it has opened.
///
/// Structure follows the Figma, which is consistent across all four pulse
/// options (`3182:3552`, `3888`, `4196`, `4490`): one tinted card carrying the
/// lede, Eagle's mark, the synthesis headline and the per-member lines, then a
/// separate Question of the Day card below it.
///
/// What varies between the options is only the middle of that first card —
/// quotes (A), scripture tallies (B), grouped readings (C) or commitments (D).
/// D was chosen, and its layout is the same avatar / name / line as A, so this
/// renders both shapes.
struct GroupPulseView: View {
    let insight: AIInsight
    var onClose: () -> Void = {}
    var onOpenFeed: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var reflections: Loadable<[Reflection]> = .idle
    @State private var showingOriginal: Set<UUID> = []

    private var viewerLanguage: String { session.me?.preferredLanguage ?? "en" }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        pulseCard
                        questionCard
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.lg)
                    .padding(.bottom, TabBarMetrics.clearance)
                }
                .scrollIndicators(.hidden)
            }
        }
        .dwellThemed()
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            Text("Group Pulse")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    // MARK: - The pulse card

    private var payload: PulsePayload? { insight.payload(in: viewerLanguage) }

    private var pulseCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .top) {
                Text(lede)
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.accent)
                Spacer(minLength: Space.md)
                ZStack {
                    Circle().fill(t.ink)
                    Image(systemName: "sparkle")
                        .font(.system(size: 16))
                        .foregroundStyle(t.onInk)
                }
                .frame(width: 40, height: 40)
            }

            if let headline {
                Text(headline)
                    .font(.dwellCardTitle)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary {
                Text(summary)
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The companion's reading above, the group's own words below —
            // the rule marks the change of voice. It fades at both ends so it
            // divides without boxing the content in.
            LinearGradient(colors: [t.accent.opacity(0),
                                    t.accent.opacity(0.45),
                                    t.accent.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.vertical, Space.sm)

            if let members = payload?.members, !members.isEmpty {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    ForEach(members) { member in
                        commitmentLine(member)
                    }
                }
                if insight.isTranslated(for: viewerLanguage) {
                    Text("Translated from \(languageName(insight.language ?? "en"))")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                }
            } else {
                // Rows written before the payload existed carry no member
                // lines; the day's own reflections are the honest stand-in.
                LoadableView(state: reflections, retry: { Task { await load() } }) { list in
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        ForEach(list) { reflection in
                            memberLine(reflection)
                        }
                    }
                }
            }

            // The card says one thing about the day; the reflections it was
            // built from live in the feed.
            Button(action: onOpenFeed) {
                HStack(spacing: 4) {
                    Text("See more")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.dwellBodyMd)
                .foregroundStyle(t.accent)
            }
            .buttonStyle(PressScale())
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent, but frosted rather than merely see-through. A plain
        // 6% wash let the clouds land behind the text and cyan type on cloud
        // is close to unreadable; a material blurs whatever is behind it, so
        // the sky still reads through the card without competing with it.
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(t.accent.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
        )
    }

    /// Avatar, name, and the thing they said they'd do.
    private func commitmentLine(_ member: PulseMember) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            PhotoAvatar(name: session.name(for: member.userId),
                        url: session.avatarURL(for: member.userId),
                        size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name(for: member.userId))
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Text(member.line)
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func memberLine(_ reflection: Reflection) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            PhotoAvatar(name: session.name(for: reflection.userId),
                        url: session.avatarURL(for: reflection.userId),
                        size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name(for: reflection.userId))
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Text("“\(quote(from: reflection))”")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if isTranslated(reflection) {
                    HStack(spacing: 4) {
                        Text("Translated from \(languageName(reflection.language))")
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                        Text("·").foregroundStyle(t.textSecondary)
                        Button(showingOriginal.contains(reflection.id)
                               ? "See translation" : "See original") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if showingOriginal.contains(reflection.id) {
                                    showingOriginal.remove(reflection.id)
                                } else {
                                    showingOriginal.insert(reflection.id)
                                }
                            }
                        }
                        .font(.dwellCaption)
                        .foregroundStyle(t.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Question of the Day

    /// Present on every pulse option in the Figma, but there is no generated
    /// question in `ai_insights` yet — so this renders only when one exists
    /// rather than inventing a question the companion never asked.
    @ViewBuilder
    private var questionCard: some View {
        if let question = session.pulseQuestion {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Question of the Day")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)

                Text(question)
                    .font(.dwellCardTitle)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.md) {
                    MemberAvatarRow(members: responders, size: 40)
                    Text("\(answeredCount) Response\(answeredCount == 1 ? "" : "s")")
                        .font(.dwellCardTitle)
                        .foregroundStyle(t.textPrimary)
                    Spacer(minLength: 0)
                }

                PrimaryButton(title: "Answer in the feed", action: onOpenFeed)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(t.surfaceRaised.opacity(0.6))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Ticks mark whoever has posted today — the only answer signal that
    /// exists until the backend tracks responses to the question itself.
    private var responders: [(name: String, url: URL?, posted: Bool)] {
        let answered = Set((reflections.value ?? []).map(\.userId))
        return session.members.map { member in
            (name: session.name(for: member.userId),
             url: session.avatarURL(for: member.userId),
             posted: answered.contains(member.userId))
        }
    }

    private var answeredCount: Int { Set((reflections.value ?? []).map(\.userId)).count }

    // MARK: - Helpers

    /// The design's synthesis is one short line — "Everyone wrote about
    /// someone they'd stopped hearing."
    ///
    /// What the backend actually returns is a multi-sentence summary ("In your
    /// reflections on Psalm 34:18, you all share a common theme of…"), which
    /// fills the whole screen and buries the member lines the card exists to
    /// show. So this takes the headline only when the text is short enough to
    /// *be* a headline, and shows nothing otherwise rather than pasting an
    /// essay into the slot. It starts working on its own the moment the
    /// backend returns a one-liner — see item 45 in Notion.
    /// 24pt, matching the Figma. There is always one: without a real headline
    /// the card was nothing but 16pt lede and 16pt body, which is why it read
    /// as having no header at all.
    private var headline: String? {
        if let written = payload?.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !written.isEmpty { return written }
        // No payload yet — the summary's opening sentence is the closest thing
        // to a noticing that the prose contains.
        return firstSentence(of: insight.content)
    }

    /// The longer synthesis, kept — but set in body type and clamped to four
    /// lines, because at headline size it filled the screen and pushed the
    /// member lines out of sight. Once the backend returns a real one-line
    /// headline, this sits beneath it exactly as a standfirst would.
    /// One sentence. The full synthesis runs to a paragraph that buries the
    /// member lines, and the card's job is to say one thing — the rest of the
    /// prose belongs wherever the long form is wanted, not here.
    private var summary: String? {
        // Without a payload the opening sentence is already the headline, so
        // repeating it beneath itself would be nonsense.
        guard payload?.headline?.isEmpty == false else { return nil }
        return firstSentence(of: insight.summary(in: viewerLanguage))
    }

    private func firstSentence(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let stop = trimmed.firstIndex(where: { ".!?".contains($0) }) else { return trimmed }
        return String(trimmed[...stop])
    }

    private var lede: String {
        if let written = payload?.lede?.trimmingCharacters(in: .whitespacesAndNewlines),
           !written.isEmpty { return written }
        // Derived fallback, for rows written before the backend supplied one.
        let posted = payload?.reflectionCount ?? answeredCount
        let total = session.members.count
        if posted > 0 && posted == total { return "Today, all \(spelled(total)) of you…" }
        if posted > 0 { return "Today, \(spelled(posted)) of you…" }
        return "Today…"
    }

    private func quote(from reflection: Reflection) -> String {
        let text = showingOriginal.contains(reflection.id)
            ? reflection.displayBody
            : body(of: reflection)
        guard text.count > 160 else { return text }
        if let stop = text.prefix(200).lastIndex(where: { ".!?".contains($0) }) {
            return String(text[...stop])
        }
        return String(text.prefix(160)) + "…"
    }

    private func body(of reflection: Reflection) -> String {
        guard reflection.language != viewerLanguage,
              let translated = reflection.translatedText?[viewerLanguage] else {
            return reflection.displayBody
        }
        return translated
    }

    private func isTranslated(_ reflection: Reflection) -> Bool {
        reflection.language != viewerLanguage
            && reflection.translatedText?[viewerLanguage] != nil
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }

    private func load() async {
        guard let dayId = insight.dayInstanceId ?? session.currentDay?.id else {
            reflections = .loaded([])
            return
        }
        reflections = .loading
        do {
            let all = try await session.api.reflections(dayInstanceId: dayId)
            reflections = .loaded(all.filter { $0.moderationStatus == .approved })
        } catch {
            reflections = .failed(error.localizedDescription)
        }
    }
}
