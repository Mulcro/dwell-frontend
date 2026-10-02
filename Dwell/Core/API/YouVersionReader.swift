import Foundation
import YouVersionPlatform

/// Bridge to the YouVersion Platform SDK.
///
/// The reading experience is meant to be *their* component
/// (`BibleReaderView`), not a screen we draw — which is why the passage screen
/// in the Figma carries their chrome, their translation picker and their
/// highlight treatment. Our job is only to hand it the right reference.
///
/// Requires Xcode 26 or newer: `YouVersionPlatformUI` uses
/// `ToolbarItemPlacement.title` (iOS 26+) behind a mistaken
/// `if #available(iOS 15, *)` guard, so it will not compile against the
/// iOS 18 SDK. Built and verified against Xcode 27 / iOS 27.
enum YouVersionReader {

    /// Called once at launch — `configure` is main-actor isolated.
    @MainActor
    static func configure(appKey: String?) {
        guard let appKey, !appKey.isEmpty else { return }
        YouVersionPlatformConfiguration.configure(
            appKey: appKey,
            appName: appName,
            // Our own sign-in is Supabase. The reader only needs a YouVersion
            // account for highlights, so its prompt stays available but quiet.
            isSignInEnabled: true,
            signInPromptMessage: signInMessage)
    }

    static let appName = "Dwell"
    static let signInMessage = "Sign in with YouVersion to keep your highlights."

    /// Berean Standard Bible — confirmed as `bible_id` 3034 from our own
    /// `get-passage` response, so the reader and the rest of the app show the
    /// same translation.
    ///
    /// The Figma shows **NLT**, which we cannot ship: our app key only grants
    /// freely-licensed versions. The reader's own picker lists 11 English
    /// versions — ASV, BSB, CPDV, FBV, GNV, LSV, TOJB, TCENT, WEBUS, WMB —
    /// with no NLT and no NIV. Asking for 111 (NIV) is what made the reader
    /// fall back to that picker instead of opening the passage.
    ///
    /// Not restricted via `permittedVersionIds`: the design shows a
    /// translation chip, so switching between the licensed versions stays
    /// available.
    static let defaultVersionId = 3034

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

    /// Maps our parsed reference onto the SDK's.
    static func bibleReference(for reference: Reference) -> BibleReference {
        guard let start = reference.verseStart else {
            return BibleReference(versionId: reference.versionId,
                                  bookUSFM: reference.bookUSFM,
                                  chapter: reference.chapter)
        }
        guard let end = reference.verseEnd, end != start else {
            return BibleReference(versionId: reference.versionId,
                                  bookUSFM: reference.bookUSFM,
                                  chapter: reference.chapter,
                                  verse: start)
        }
        return BibleReference(versionId: reference.versionId,
                              bookUSFM: reference.bookUSFM,
                              chapter: reference.chapter,
                              verseStart: start, verseEnd: end)
    }

    /// Convenience: USFM straight to the SDK's reference.
    static func bibleReference(fromUSFM usfm: String,
                               versionId: Int = defaultVersionId) -> BibleReference? {
        reference(fromUSFM: usfm, versionId: versionId).map(bibleReference(for:))
    }
}
