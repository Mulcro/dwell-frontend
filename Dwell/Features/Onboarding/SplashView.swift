import SwiftUI

/// Full-bleed sky with the wordmark. Figma: "Splash Screen".
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Image("SkyHero")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Text("Dwell")
                .font(.dwellHero)
                .tracking(-0.96)
                .foregroundStyle(.white)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.96)
        }
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.easeOut(duration: 0.7)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dwell")
    }
}

#Preview { SplashView() }
