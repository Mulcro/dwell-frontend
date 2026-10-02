import SwiftUI

/// Record → review → posted. Presented over Home from "Start Reflection".
struct ReflectFlow: View {
    var onClose: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @State private var step: Step = .compose
    @State private var draft = Draft()

    enum Step: Equatable { case compose, review, posted }

    /// What's being posted, regardless of how it was captured.
    struct Draft: Equatable {
        var mediaType: MediaType = .voice
        var body = ""
        var duration: TimeInterval = 0
        var levels: [CGFloat] = []
        var language = "en"
        /// The m4a written while recording, with its peaks. Nil for a text
        /// reflection, or when recording failed — posting then degrades to
        /// transcript-only rather than losing the reflection.
        var attachment: MediaAttachment?

        var isPostable: Bool {
            !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Group {
            switch step {
            case .compose:
                RecordReflectionView(draft: $draft,
                                     onBack: onClose,
                                     onNext: { step = .review })
            case .review:
                ReviewReflectionView(draft: draft,
                                     onBack: { step = .compose },
                                     onPosted: { step = .posted })
            case .posted:
                PostedConfirmationView(onDone: onClose)
            }
        }
        .onAppear { draft.language = session.me?.preferredLanguage ?? "en" }
    }
}
