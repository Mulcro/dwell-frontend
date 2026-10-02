import SwiftUI

/// Figma: "Settings · Group Owner" / "Settings · Member".
///
/// Only the unambiguous parts are built. Two things are deliberately left
/// pending a design decision (see the design-notes page):
///
///   • The two frames are identical, and the owner's shows "Set by group
///     owner." under the threshold — so who can edit it is unclear. The slider
///     is read-only for everyone here, which is the least-wrong reading.
///   • "Catch-Up Threshold" is used as the heading for two different sections.
///     The second block is rendered without a heading rather than shipping a
///     visible duplicate.
struct SettingsView: View {
    var onBack: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var notifications: [String: Bool] = [:]
    @State private var findByPhone = false
    @State private var contactSync = false
    @State private var showLanguage = false
    @State private var showTimeZone = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var toast: Toast?

    /// Drawn order, verbatim from the Figma.
    private let notificationRows = [
        "Reminder nudges",
        "Friends' posts",
        "Comments, reactions, & mentions",
        "Returning friends",
        "Streaks & memories"
    ]

    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 280, fadeFrom: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        section("Notifications") { notificationCard }
                        section("Catch-Up Threshold") { thresholdCard }
                        // Heading omitted deliberately — see the type doc.
                        preferencesCard

                        accountCard

                        #if DEBUG
                        section("Preview (debug builds only)") { previewCard }
                        #endif
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xxxl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .dwellThemed()
        .onAppear(perform: seedToggles)
        .sheet(isPresented: $showLanguage) {
            PickerSheet(title: "Language",
                        options: Self.languages,
                        selected: session.me?.preferredLanguage ?? "en") { code in
                Task { await updateLanguage(code) }
            }
        }
        .sheet(isPresented: $showTimeZone) {
            PickerSheet(title: "Time Zone",
                        options: Self.timeZones,
                        selected: session.me?.timezone ?? TimeZone.current.identifier) { zone in
                Task { await updateTimeZone(zone) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            Text("Settings")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title)
                .font(.dwellCardTitleStrong)
                .foregroundStyle(t.textPrimary)
            content()
        }
    }

    private static let notificationsKey = "settings.notifications"
    private static let findByPhoneKey = "settings.findByPhone"
    private static let contactSyncKey = "settings.contactSync"

    private var notificationCard: some View {
        card {
            ForEach(Array(notificationRows.enumerated()), id: \.offset) { index, row in
                Toggle(isOn: Binding(
                    get: { notifications[row] ?? true },
                    set: {
                        notifications[row] = $0
                        UserDefaults.standard.set(notifications, forKey: Self.notificationsKey)
                    })) {
                    Text(row)
                        .font(.dwellBody)
                        .foregroundStyle(t.textPrimary)
                }
                .tint(t.accent)
                .padding(.vertical, Space.sm)

                if index < notificationRows.count - 1 { divider }
            }

            divider
            // Honest about reach: push needs a paid Apple Developer
            // membership, so until then these govern what appears in the app.
            Text("Reminders appear in Dwell for now. Push notifications arrive "
                 + "once the app is on the App Store.")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .padding(.top, Space.sm)
        }
    }

    /// Read-only pending the owner/member decision.
    private var thresholdCard: some View {
        card {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Unlock Threshold")
                        .font(.dwellCardTitle)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Text("\(group?.catchUpThresholdPct ?? 50)%")
                        .font(.dwellCardTitleStrong)
                        .foregroundStyle(t.accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(t.surfaceRaised)
                        Capsule().fill(t.accent)
                            .frame(width: geo.size.width * thresholdFraction)
                        Circle()
                            .fill(t.background)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                            .offset(x: geo.size.width * thresholdFraction - 12)
                    }
                }
                .frame(height: 24)
                .accessibilityLabel("Unlock threshold \(group?.catchUpThresholdPct ?? 50) percent, set by the group owner")

                Text("Set by group owner.")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            }
            .padding(.vertical, Space.sm)
        }
    }

    private var thresholdFraction: CGFloat {
        CGFloat(group?.catchUpThresholdPct ?? 50) / 100
    }

    private var preferencesCard: some View {
        card {
            Toggle(isOn: Binding(get: { findByPhone }, set: {
                findByPhone = $0
                UserDefaults.standard.set($0, forKey: Self.findByPhoneKey)
            })) {
                Text("Find me by phone number")
                    .font(.dwellBody).foregroundStyle(t.textPrimary)
            }
            .tint(t.accent)
            .padding(.vertical, Space.sm)

            divider

            Toggle(isOn: Binding(get: { contactSync }, set: {
                contactSync = $0
                UserDefaults.standard.set($0, forKey: Self.contactSyncKey)
            })) {
                Text("Contact sync")
                    .font(.dwellBody).foregroundStyle(t.textPrimary)
            }
            .tint(t.accent)
            .padding(.vertical, Space.sm)

            divider

            row("Time zone & day window", value: shortTimeZone) { showTimeZone = true }

            divider

            row("Read reflections in", value: languageName) { showLanguage = true }
        }
    }

    #if DEBUG
    /// Switches for states that only occur after days of real inactivity.
    ///
    /// Compiled out of release builds entirely. They exist because the
    /// stalled-group question and the companion's nudge are both written by a
    /// backend cron after days of nobody posting — there is no way to reach
    /// either on demand, which makes them impossible to check or demo.
    private var previewCard: some View {
        card {
            VStack(spacing: Space.md) {
                Toggle(isOn: Binding(get: { session.previewStalled },
                                     set: { session.previewStalled = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stalled group question").font(.dwellBody)
                        Text("Replaces Home with Keep Going / Pause / End")
                            .font(.dwellCaption).foregroundStyle(t.textSecondary)
                    }
                }
                Divider().overlay(t.border)
                Toggle(isOn: Binding(get: { session.previewNudge },
                                     set: { session.previewNudge = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Companion nudge").font(.dwellBody)
                        Text("Shows a sample nudge banner on Home")
                            .font(.dwellCaption).foregroundStyle(t.textSecondary)
                    }
                }
                Divider().overlay(t.border)
                Toggle(isOn: Binding(get: { session.previewPulse },
                                     set: { session.previewPulse = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group Pulse").font(.dwellBody)
                        Text("Adds the pulse card to Home with a sample synthesis")
                            .font(.dwellCaption).foregroundStyle(t.textSecondary)
                    }
                }
            }
            .tint(t.accent)
            .foregroundStyle(t.textPrimary)
        }
    }
    #endif

    /// Sign out and account deletion.
    ///
    /// DESIGN: invented — the Figma's Settings has neither. Deleting an
    /// account is an App Store requirement (guideline 5.1.1(v)) for any app
    /// that lets you create one, so it can't wait for a comp.
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            card {
                Button {
                    Task {
                        try? await session.api.signOut()
                        session.finishOnboarding()
                        await session.bootstrap()
                    }
                } label: {
                    HStack {
                        Text("Sign out").font(.dwellBody).foregroundStyle(t.textPrimary)
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16))
                            .foregroundStyle(t.textSecondary)
                    }
                    .padding(.vertical, Space.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())

                divider

                Button { confirmingDelete = true } label: {
                    HStack {
                        Text("Delete account").font(.dwellBody).foregroundStyle(t.danger)
                        Spacer()
                    }
                    .padding(.vertical, Space.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
            }

            Text("Deleting removes your reflections, comments and memberships. Groups you created stay with the people still in them.")
                .font(.dwellSmall)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(LineSpacing.small)
        }
        .toast($toast)
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    deleting = true
                    defer { deleting = false }
                    do {
                        // Only sign out once the server has confirmed it.
                        // Swallowing this left someone believing an
                        // irreversible action had happened when it hadn't.
                        try await session.api.deleteAccount()
                    } catch {
                        toast = .failure("We couldn't delete your account. "
                                         + error.localizedDescription)
                        return
                    }
                    session.finishOnboarding()
                    await session.bootstrap()
                }
            }
        } message: {
            Text("This can't be undone. Everything you've written is removed.")
        }
    }

    private func row(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.dwellBody).foregroundStyle(t.textPrimary)
                Spacer()
                Text(value).font(.dwellBody).foregroundStyle(t.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .padding(.vertical, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(t.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle().fill(t.border).frame(height: 1)
    }

    private var languageName: String {
        let code = session.me?.preferredLanguage ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private var shortTimeZone: String {
        let id = session.me?.timezone ?? TimeZone.current.identifier
        return TimeZone(identifier: id)?.abbreviation() ?? id
    }

    private func seedToggles() {
        guard notifications.isEmpty else { return }
        // Restored rather than defaulted: these used to reset every time
        // Settings was rebuilt, so a choice never survived leaving the screen.
        let stored = UserDefaults.standard.dictionary(forKey: Self.notificationsKey) as? [String: Bool]
        notifications = Dictionary(uniqueKeysWithValues:
            notificationRows.map { ($0, stored?[$0] ?? true) })
        findByPhone = UserDefaults.standard.bool(forKey: Self.findByPhoneKey)
        contactSync = UserDefaults.standard.bool(forKey: Self.contactSyncKey)
    }

    private func updateLanguage(_ code: String) async {
        session.me = try? await session.api.updateProfile(
            name: nil, timezone: nil, preferredLanguage: code, pushToken: nil)
    }

    private func updateTimeZone(_ zone: String) async {
        session.me = try? await session.api.updateProfile(
            name: nil, timezone: zone, preferredLanguage: nil, pushToken: nil)
    }

    /// The languages the translation step can target. Kept short and real
    /// rather than listing every locale iOS knows.
    static let languages: [PickerSheet.Option] = [
        .init(id: "en", title: "English"),
        .init(id: "es", title: "Spanish"),
        .init(id: "fr", title: "French"),
        .init(id: "de", title: "German"),
        .init(id: "pt", title: "Portuguese"),
        .init(id: "hi", title: "Hindi"),
        .init(id: "mr", title: "Marathi"),
        .init(id: "zu", title: "Zulu"),
        .init(id: "ak", title: "Twi")
    ]

    static var timeZones: [PickerSheet.Option] {
        TimeZone.knownTimeZoneIdentifiers.map {
            .init(id: $0, title: $0.replacingOccurrences(of: "_", with: " "))
        }
    }
}

/// Figma: "Settings · Language Picker" / "Time Zone Picker" — a compact
/// searchable list, drawn at 301×336 as a popover rather than a full screen.
struct PickerSheet: View {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let title: String
    let options: [Option]
    let selected: String
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dwell) private var t
    @State private var query = ""

    private var filtered: [Option] {
        guard !query.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { option in
                Button {
                    onPick(option.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title).foregroundStyle(t.textPrimary)
                        Spacer()
                        if option.id == selected {
                            Image(systemName: "checkmark").foregroundStyle(t.accent)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
