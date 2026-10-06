import SwiftUI
import UserNotifications

/// Figma: "Enable Notifications". Priming screen — shows what a nudge looks
/// like before asking, so the system prompt isn't the first thing you see.
struct EnableNotificationsView: View {
    var onDone: () -> Void = {}
    @Environment(\.dwell) private var t
    @State private var asking = false

    private let samples: [(name: String, action: String, age: String, avatar: Int)] = [
        ("Daniel Osei", "Added their reflection", "now", 1),
        ("Jordan Reyes", "Reacted to your reflection", "2m", 3)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 380, fadeFrom: 0.35)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(spacing: Space.md) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                        notification(sample)
                    }
                }
                .padding(.bottom, Space.xxl)

                Text("Don't miss out on what your friends are learning from God.")
                    .font(.dwellTitle)
                    .lineSpacing(LineSpacing.title)
                    .foregroundStyle(t.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Never miss those precious moments.")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xxl)

                PrimaryButton(title: "Turn on notifications", loading: asking, perform: request)
                SecondaryButton(title: "Another time", action: onDone)
                    .padding(.top, Space.xs)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    private func notification(_ sample: (name: String, action: String, age: String, avatar: Int)) -> some View {
        HStack(spacing: Space.md) {
            PhotoAvatar(name: sample.name, index: sample.avatar, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(sample.name)
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
                Text(sample.action)
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer()
            Text(sample.age)
                .font(.dwellCaption)
                .foregroundStyle(t.textTertiary)
        }
        .padding(Space.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Asks for permission, then registers with APNs straight away so the
    /// token reaches the backend before the first nudge is due.
    private func request() async {
        asking = true
        defer { asking = false }
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        if granted == true {
            Haptics.posted()
            UIApplication.shared.registerForRemoteNotifications()
        }
        onDone()
    }
}

#Preview { EnableNotificationsView() }
