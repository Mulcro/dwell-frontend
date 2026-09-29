import SwiftUI

/// The sky photograph that heads most onboarding screens, fading into the
/// page so content sits on white.
struct SkyBackground: View {
    /// How far down the screen the photo reaches.
    var height: CGFloat = 420
    /// Where the fade to background begins, as a fraction of `height`.
    var fadeFrom: CGFloat = 0.45
    @Environment(\.dwell) private var t

    var body: some View {
        Image("SkyHero")
            .resizable()
            .scaledToFill()
            .frame(height: height)
            .clipped()
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: fadeFrom),
                        .init(color: t.background, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
