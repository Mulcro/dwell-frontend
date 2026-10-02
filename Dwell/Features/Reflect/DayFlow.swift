import SwiftUI

/// The day, end to end: read the passage, then reflect on it.
///
/// Reading first is the whole point of the product — the old build's button
/// said "Read, then reflect" — so Home opens here rather than jumping
/// straight to the composer. The Plan Overview's checkboxes and the ✓ at the
/// end of the passage only mean anything as a step before reflecting.
struct DayFlow: View {
    /// Where to begin. Tapping "Start Reflection" on Home begins at the
    /// reading; "Add to today's reflection" can skip to the composer.
    var startAt: Stage = .reading
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @State private var stage: Stage = .reading
    @State private var passageRef: String?

    enum Stage: Equatable { case reading, reflecting }

    private var dayIndex: Int { session.currentDay?.dayIndex ?? 1 }

    var body: some View {
        Group {
            switch stage {
            case .reading:
                ReadingPager(item: .devotional(dayIndex: dayIndex),
                             onClose: onClose,
                             onComplete: { stage = .reflecting })
            case .reflecting:
                ReflectFlow(onClose: onClose)
            }
        }
        .onAppear { stage = startAt }
    }
}
