import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void = {}
    var onInvite: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            ImagePlaceholder("ambient image — hands / dawn light",
                             radius: 0, alignment: .leading)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Don't do it\n")
                    .font(.dwellDisplay)
                    .foregroundStyle(t.textPrimary)
                + Text("alone.")
                    .font(DwellFont.serifItalic(30))
                    .foregroundStyle(t.textPrimary)

                Text("A shared plan with 2–10 friends. The day opens when the group shows up.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .lineSpacing(5)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xxl)

                DwellButton(title: "Continue with YouVersion", action: onContinue)
                DwellButton(title: "I have an invite link", kind: .secondary, action: onInvite)
                    .padding(.top, Space.sm)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }
}

#Preview { WelcomeView() }
#Preview("Dark") { WelcomeView().preferredColorScheme(.dark) }
