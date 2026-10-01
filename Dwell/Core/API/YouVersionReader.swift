import Foundation

/// Bridge to the YouVersion Platform SDK.
///
/// The reading experience is meant to be *their* component
/// (`BibleReaderView`), not a screen we draw — which is why the passage screen
/// in the Figma carries their chrome, their translation picker and their
/// highlight treatment. Our job is only to hand it the right reference.
///
/// **The SDK is not linked yet.** `platform-sdk-swift` 5.5.0 fails to compile
/// against the iOS 18.5 SDK: `YouVersionPlatformUI` uses
/// `ToolbarItemPlacement.title`, which is iOS 26+, behind a mistaken
/// `if #available(iOS 15, *)` guard. It needs Xcode 26. Everything here is
/// SDK-independent so it's ready the moment that's resolved.
enum YouVersionReader {

    static let appName = "Dwell"
    static let signInMessage = "Sign in with YouVersion to keep your highlights."

    /// Default Bible version id. The SDK ships no named constants; 111 is NIV,
    /// and the reader lets the user change it. The Figma shows **NLT** — if
    /// that's a requirement rather than a mock, its id needs confirming.
    static let defaultVersionId = 111

    /// A passage reference parsed out of `plan_days.passage_ref`.
    ///
    /// Mirrors the SDK's `BibleReference` so wiring it up is a one-line map:
    /// `BibleReference(versionId:bookUSFM:chapter:verse:)` or the
    /// `verseStart:verseEnd:` variant.
    struct Reference: Equatable {
        let versionId: Int
        let bookUSFM: String
        let chapter: Int
        let verseStart: Int?
        let verseEnd: Int?

        /// "John 16:33", "Romans 5:3-5", "Psalm 1" — for our own chrome.
        var display: String {
            let book = bookUSFM.capitalized
            guard let start = verseStart else { return "\(book) \(chapter)" }
            guard let end = verseEnd, end != start else { return "\(book) \(chapter):\(start)" }
            return "\(book) \(chapter):\(start)-\(end)"
        }
    }

    /// Parses the USFM refs in `plan_days.passage_ref`.
    ///
    ///   `PSA.1`      → whole chapter
    ///   `JHN.16.33`  → single verse
    ///   `ROM.5.3-5`  → verse range
    ///
    /// Returns nil rather than guessing, so a malformed ref surfaces an error
    /// instead of silently opening the wrong passage.
    static func reference(fromUSFM usfm: String,
                          versionId: Int = defaultVersionId) -> Reference? {
        let parts = usfm.uppercased().split(separator: ".").map(String.init)
        guard parts.count >= 2,
              !parts[0].isEmpty,
              let chapter = Int(parts[1]), chapter >= 1
        else { return nil }

        guard parts.count >= 3 else {
            return Reference(versionId: versionId, bookUSFM: parts[0],
                             chapter: chapter, verseStart: nil, verseEnd: nil)
        }

        let verses = parts[2].split(separator: "-").map(String.init)
        guard let start = Int(verses[0]), start >= 1 else { return nil }

        if verses.count >= 2, let end = Int(verses[1]), end >= start {
            return Reference(versionId: versionId, bookUSFM: parts[0],
                             chapter: chapter, verseStart: start, verseEnd: end)
        }
        return Reference(versionId: versionId, bookUSFM: parts[0],
                         chapter: chapter, verseStart: start, verseEnd: start)
    }
}
