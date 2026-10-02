import SwiftUI
import YouVersionPlatform

/// The two-step reader: devotional, then passage, with the "Day 1 • 1 of 2"
/// pager the design puts along the bottom.
struct ReadingPager: View {
    let item: ReadingItem
    var onClose: () -> Void = {}
    /// Fired by the final ✓. Reading isn't the end of the day — reflecting is
    /// — so whoever presents this decides what comes next.
    var onComplete: (() -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var step = 0
    @State private var passageRef: String?

    private var steps: [ReadingItem] {
        guard let usfm = passageRef else { return [.devotional(dayIndex: item.dayIndex)] }
        return [.devotional(dayIndex: item.dayIndex),
                .passage(dayIndex: item.dayIndex, usfm: usfm)]
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch steps[min(step, steps.count - 1)] {
                case .devotional:
                    DevotionalView(dayIndex: item.dayIndex, onClose: onClose)
                case let .passage(_, usfm):
                    PassageView(usfm: usfm, onClose: onClose)
                }
            }
            .frame(maxHeight: .infinity)

            pager
        }
        // Keyed to the plan: bootstrap may not have resolved it when this
        // first appears, and an unkeyed task would never retry — leaving the
        // pager stuck on "1 of 1" with no passage step.
        .task(id: session.plan?.id) { await resolvePassage() }
        // Opening straight onto the passage has to wait for `passageRef`:
        // before it resolves there is only one step, so setting step = 1 early
        // just clamps back to the devotional.
        .onChange(of: passageRef) { _, ref in
            if ref != nil, case .passage = item { step = steps.count - 1 }
        }
    }

    private var pager: some View {
        HStack {
            Button {
                if step > 0 { step -= 1 } else { onClose() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressScale())

            Spacer()

            VStack(spacing: 2) {
                Text(session.plan?.title ?? "")
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(1)
                Text("Day \(item.dayIndex) • \(min(step, steps.count - 1) + 1) of \(steps.count)")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }

            Spacer()

            Button {
                if step < steps.count - 1 { step += 1 } else { complete() }
            } label: {
                Image(systemName: step < steps.count - 1 ? "chevron.right" : "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(step < steps.count - 1 ? t.textPrimary : t.onInk)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(step < steps.count - 1 ? Color.clear : t.ink)
                    )
            }
            .buttonStyle(PressScale())
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(t.background)
        .overlay(alignment: .top) { Divider().overlay(t.border) }
    }

    private func complete() {
        Haptics.posted()
        if let onComplete { onComplete() } else { onClose() }
    }

    private func resolvePassage() async {
        if case let .passage(_, usfm) = item { passageRef = usfm; return }
        guard let plan = session.plan else { return }
        guard let days = try? await session.api.getPlanDays(planId: plan.id) else { return }
        passageRef = days.first { $0.dayIndex == item.dayIndex }?.passageRef
    }
}

/// The devotional.
///
/// There is no source for this text: Backend Design Doc §3.4 says the Platform
/// API cannot serve devotional content, and `plan_days` carries only a
/// `passage_ref`. The copy below is a stand-in so the flow reads correctly —
/// see Notion item 29 for the ask.
struct DevotionalView: View {
    let dayIndex: Int
    var onClose: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(t.surfaceRaised))
                }
                .buttonStyle(PressScale())
                Spacer()
                Text("Devotional")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)

            ScrollView {
                Text(Self.placeholder)
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(t.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
    }

    private static let placeholder = """
        It would be great if once you decided to trust Jesus, you'd have an \
        easy life, but unfortunately that isn't true. We live in a broken world \
        full of sin, and because of that, bad things will happen to all of us. \
        We will all have to deal with loss, pain, sickness, and failure.

        That is kind of depressing, but Jesus gives us a great reminder in \
        John 16:33. He wants us to know that he had victory over sin, and that \
        those of us who trust in him will get to experience his peace \
        regardless of the difficult times we are facing.

        Challenge: Write down some of the difficulties you are currently \
        facing and how you feel about them. Be completely honest with God.
        """
}

/// The passage — YouVersion's own reader, not a screen we draw.
///
/// Their component owns the translation picker, the surrounding context and
/// the highlight treatment, which is why the Figma frame carries their chrome.
struct PassageView: View {
    let usfm: String
    var onClose: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        if let reference = YouVersionReader.bibleReference(fromUSFM: usfm) {
            // `showsFullChapter: false` renders only the day's verse range, so
            // what you're meant to read is unambiguous.
            //
            // The Figma shows the target highlighted *within* its chapter, but
            // the SDK can't do that: `BibleReaderViewModel.selectedVerses` is
            // internal and `BibleReaderView` exposes no pre-selection. Only
            // `BibleTextView` takes a `selectedVerses` binding — and that's the
            // text component, without the reader's translation picker, audio
            // and search chrome the design also shows.
            BibleReaderView(reference: reference, showsFullChapter: false)
        } else {
            ErrorStateView(message: "Couldn't read the reference “\(usfm)”.")
        }
    }
}
