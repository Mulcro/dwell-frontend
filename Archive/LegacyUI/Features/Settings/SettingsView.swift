import SwiftUI

struct SettingsView: View {
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var notifications: [String: Bool] = [
        "Friends' posts": true,
        "Comments & reactions": true,
        "Your day closing": true,
        "Streaks & memories": false
    ]
    @State private var findByPhone = true
    @State private var contactSync = false

    private let order = ["Friends' posts", "Comments & reactions", "Your day closing", "Streaks & memories"]
    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(title: "Settings", onLeading: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    section("Nudges",
                            footnote: "Nudges appear in the app for now. Push notifications are coming.") {
                        ForEach(Array(order.enumerated()), id: \.offset) { index, key in
                            Toggle(isOn: Binding(
                                get: { notifications[key] ?? false },
                                set: { notifications[key] = $0 })) {
                                Text(key).font(.dwellBody).foregroundStyle(t.textPrimary)
                            }
                            .padding(.vertical, Space.sm)
                            if index < order.count - 1 {
                                Rectangle().fill(t.border).frame(height: 1)
                            }
                        }
                    }

                    section("Catch-up threshold",
                            footnote: "Any member can propose a change; it needs a majority.") {
                        HStack {
                            Text("Group unlocks at").font(.dwellBody).foregroundStyle(t.textPrimary)
                            Spacer()
                            Text("\(group?.catchUpThresholdPct ?? 50)%")
                                .font(.dwellBodyMd).foregroundStyle(t.accent)
                        }
                        .padding(.vertical, Space.sm)
                        Rectangle().fill(t.border).frame(height: 1)
                        HStack {
                            Text("Skip a stuck day after").font(.dwellBody).foregroundStyle(t.textPrimary)
                            Spacer()
                            Text("\(group?.autoSkipAfterDays ?? 3) days")
                                .font(.dwellBodyMd).foregroundStyle(t.accent)
                        }
                        .padding(.vertical, Space.sm)
                    }

                    section("You") {
                        HStack {
                            Text("Language").font(.dwellBody).foregroundStyle(t.textPrimary)
                            Spacer()
                            Text(languageName + " ›").font(.dwellCaption).foregroundStyle(t.textSecondary)
                        }
                        .padding(.vertical, Space.sm)
                        Rectangle().fill(t.border).frame(height: 1)
                        HStack {
                            Text("Time zone").font(.dwellBody).foregroundStyle(t.textPrimary)
                            Spacer()
                            Text((session.me?.timezone ?? "—") + " ›")
                                .font(.dwellCaption).foregroundStyle(t.textSecondary)
                        }
                        .padding(.vertical, Space.sm)
                        Rectangle().fill(t.border).frame(height: 1)
                        Toggle(isOn: $findByPhone) {
                            Text("Find me by phone number").font(.dwellBody).foregroundStyle(t.textPrimary)
                        }
                        .padding(.vertical, Space.sm)
                        Rectangle().fill(t.border).frame(height: 1)
                        Toggle(isOn: $contactSync) {
                            Text("Contact sync").font(.dwellBody).foregroundStyle(t.textPrimary)
                        }
                        .padding(.vertical, Space.sm)
                    }

                    Button("Sign out") {
                        Task {
                            try? await session.api.signOut()
                            await session.bootstrap()
                        }
                    }
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)

                    Text("Everything in Dwell is free. No plan, streak or memory is ever paywalled.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textTertiary)
                        .lineSpacing(3)
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Space.gutter)
        .dwellThemed()
    }

    private var languageName: String {
        let code = session.me?.preferredLanguage ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        footnote: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow(title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.xs)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            if let footnote {
                Text(footnote).font(.dwellCaption).foregroundStyle(t.textSecondary)
            }
        }
    }
}
