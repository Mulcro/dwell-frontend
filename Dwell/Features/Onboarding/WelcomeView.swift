import SwiftUI

/// Figma: "Welcome". Sky above, the promise below, two ways in.
struct WelcomeView: View {
    var onGetStarted: () -> Void = {}
    var onLogIn: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 470, fadeFrom: 0.55)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("We're not meant to do life alone.")
                    .font(.dwellHero)
                    .tracking(-0.96)
                    .lineSpacing(LineSpacing.hero)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A shared plan with 2-7 friends. The day opens when the group shows up.")
                    .font(.dwellBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(t.textSecondary)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)

                PrimaryButton(title: "Get Started", action: onGetStarted)
                SecondaryButton(title: "Log In", action: onLogIn)
                    .padding(.top, Space.xs)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }
}

#Preview { WelcomeView() }
