import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Colour tokens from the Figma redesign (page "Define", 402×874 screens).
///
/// The redesign is light-only — there are no dark comps. The dark palette here
/// is a derivation so the app stays usable if the system is set to dark; it is
/// not designed, and `DwellTheme.lockLight` keeps the app on light until it is.
struct DwellPalette {
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color
    let borderStrong: Color

    /// Near-black — buttons and primary text both use it.
    let ink: Color
    let onInk: Color

    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    static let light = DwellPalette(
        background:    Color(hex: 0xFFFFFF),
        surface:       Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xF7F7F7),
        border:        Color(hex: 0x787878, opacity: 0.2),
        borderStrong:  Color(hex: 0xD9D9D9),
        ink:           Color(hex: 0x282828),
        onInk:         Color(hex: 0xFFFFFF),
        accent:        Color(hex: 0x00C0E8),
        success:       Color(hex: 0x34C759),
        warning:       Color(hex: 0xFF991A),
        danger:        Color(hex: 0xFF3838),
        textPrimary:   Color(hex: 0x282828),
        textSecondary: Color(hex: 0x757575),
        textTertiary:  Color(hex: 0x787880)
    )

    /// Undesigned. Derived so dark mode degrades gracefully rather than breaking.
    static let dark = DwellPalette(
        background:    Color(hex: 0x101012),
        surface:       Color(hex: 0x17171A),
        surfaceRaised: Color(hex: 0x1C1C21),
        border:        Color(hex: 0x787878, opacity: 0.24),
        borderStrong:  Color(hex: 0x3A3A3E),
        ink:           Color(hex: 0xF2F2F2),
        onInk:         Color(hex: 0x101012),
        accent:        Color(hex: 0x00C0E8),
        success:       Color(hex: 0x34C759),
        warning:       Color(hex: 0xFF991A),
        danger:        Color(hex: 0xFF6B6B),
        textPrimary:   Color(hex: 0xF2F2F2),
        textSecondary: Color(hex: 0xA0A0A5),
        textTertiary:  Color(hex: 0x787880)
    )
}

private struct DwellPaletteKey: EnvironmentKey {
    static let defaultValue = DwellPalette.light
}

extension EnvironmentValues {
    var dwell: DwellPalette {
        get { self[DwellPaletteKey.self] }
        set { self[DwellPaletteKey.self] = newValue }
    }
}

enum DwellTheme {
    /// The redesign has no dark comps yet. Flip this off once they exist.
    static let lockLight = true
}

struct DwellThemed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let useDark = scheme == .dark && !DwellTheme.lockLight
        let palette = useDark ? DwellPalette.dark : DwellPalette.light
        content
            .environment(\.dwell, palette)
            .tint(palette.ink)
            .background(palette.background.ignoresSafeArea())
            .preferredColorScheme(DwellTheme.lockLight ? .light : nil)
    }
}

extension View {
    func dwellThemed() -> some View { modifier(DwellThemed()) }
}
