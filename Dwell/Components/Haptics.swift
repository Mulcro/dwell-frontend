import UIKit

/// Tactile punctuation for the moments that matter. Kept in one place so the
/// vocabulary stays consistent — light for taps, success for posting, and a
/// heavier double beat reserved for the day unlocking.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func posted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// The day opening — the one moment in the app worth two beats.
    static func unlocked() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        }
    }
}
