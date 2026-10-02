import NaturalLanguage

/// Works out what language something was actually written in.
///
/// `preferred_language` is what someone wants to *read*, and using it as what
/// they wrote is an assumption that breaks the moment anyone types in a second
/// language — a Spanish reply from an English-preferring account was labelled
/// "Translated from English". The backend's translator auto-detects and gets
/// the translation right either way, so this only ever corrected the label —
/// but the label is the part the reader is asked to trust.
enum LanguageDetect {
    /// Below this, detection is closer to a coin toss than a signal.
    private static let minimumCharacters = 10
    private static let minimumConfidence = 0.60

    /// Returns an ISO code, or `fallback` when the text is too short or the
    /// guess too weak to be worth overriding a known preference with.
    static func dominant(of text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return fallback }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[language],
              confidence >= minimumConfidence else { return fallback }

        return language.rawValue
    }
}
