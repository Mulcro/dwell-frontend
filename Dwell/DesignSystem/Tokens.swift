import SwiftUI

/// Spacing and radii from the redesign. Screens are drawn at 402pt wide,
/// which is the iPhone 16 Pro logical width — so these are 1:1, no scaling.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 40

    /// Horizontal page gutter.
    static let gutter: CGFloat = 24
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 32
    static let pill: CGFloat = 100
}
