import SwiftUI
import UIKit

/// The redesign uses SF Pro (headlines, buttons — i.e. the system face) and
/// Inter (body). Inter isn't on iOS: drop the files into `Dwell/Fonts`, add
/// `UIAppFonts` to `Config/Info.plist`, and these resolve automatically.
/// Until then Inter falls back to the system face at the same size and weight.
enum DwellFont {
    /// SF Pro is the system font, so this is just `.system`.
    static func sf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .semibold: face = "Inter-SemiBold"
        case .medium:   face = "Inter-Medium"
        case .bold:     face = "Inter-Bold"
        default:        face = "Inter-Regular"
        }
        return UIFont(name: face, size: size) != nil
            ? .custom(face, size: size)
            : .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

/// Semantic styles. The comment on each is the Figma value it came from —
/// SF Pro weight 590 is semibold, 700 is bold.
extension Font {
    /// SF Pro w700 48 / lh 57.6 / tracking −0.96
    static let dwellHero = DwellFont.sf(48, .bold)
    /// SF Pro w590 32 / lh 38.4
    static let dwellTitle = DwellFont.sf(32, .semibold)
    /// SF Pro w400 24 / lh 28.8 / tracking −0.48
    static let dwellCardTitle = DwellFont.sf(24, .regular)
    /// SF Pro w590 24
    static let dwellCardTitleStrong = DwellFont.sf(24, .semibold)

    /// Inter w400 16 / lh 22.4
    static let dwellBody = DwellFont.inter(16)
    static let dwellBodyMd = DwellFont.inter(16, .semibold)
    /// Inter w400 14
    static let dwellSmall = DwellFont.inter(14)
    static let dwellSmallMd = DwellFont.inter(14, .semibold)
    /// SF Pro w590 16 — buttons
    static let dwellButton = DwellFont.sf(16, .semibold)
    /// SF Pro w400 12
    static let dwellCaption = DwellFont.sf(12)
    static let dwellCaptionMd = DwellFont.sf(12, .semibold)

    static let dwellCode = DwellFont.sf(20, .semibold)
}

/// Figma gives absolute line heights; SwiftUI's `lineSpacing` is *extra*
/// space on top of the font's own line height (≈1.2× size for SF). These are
/// the difference, which is why most of them are zero.
/// Extra space between lines, in points — SwiftUI's `lineSpacing` is additive,
/// not a multiplier.
///
/// Running text in the app is **double spaced**: a 16pt line is about 19pt
/// tall, so adding ~19 doubles it. Headings keep the Figma's tight leading —
/// double-spacing a two-line title pulls it apart rather than making it
/// readable. The Bible reader is YouVersion's own component and sets its own
/// leading; nothing here affects it.
enum LineSpacing {
    /// 48pt display — Figma leading, untouched.
    static let hero: CGFloat = 0
    /// 32pt title — Figma leading, untouched.
    static let title: CGFloat = 0
    /// 24pt card title — opened slightly, not doubled.
    static let cardTitle: CGFloat = 4
    /// 16pt body, ~19pt line → doubled.
    static let body: CGFloat = 19
    /// 14pt small, ~17pt line → doubled.
    static let small: CGFloat = 17
}
