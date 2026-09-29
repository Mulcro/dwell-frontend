import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var showSettings = false
    @State private var showGroup = false
    @State private var showRecap = false
    @State private var stats: (reflections: Int, days: Int) = (0, 0)

    private var group: DwellGroup? { session.group.value ?? nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    groupCard

                    HStack(spacing: Space.md) {
                        Stat(value: "\(stats.days)", label: "days in")
                        Stat(value: "\(stats.reflections)", label: "reflections")
                        Stat(value: "\(session.members.count)", label: "in the group")
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        Eyebrow("Activity")
                        VStack(spacing: 0) {
                            row("Weekly recap") { showRecap = true }
                            Rectangle().fill(t.border).frame(height: 1)
                            row("Group management") { showGroup = true }
                            Rectangle().fill(t.border).frame(height: 1)
                            row("Settings") { showSettings = true }
                        }
                        .padding(.horizontal, Space.lg)
                        .background(t.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    }
                }
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Space.gutter)
        .task { await loadStats() }
        .sheet(isPresented: $showSettings) { SettingsView(onBack: { showSettings = false }) }
        .sheet(isPresented: $showGroup) { GroupManagementView(onBack: { showGroup = false }) }
        .sheet(isPresented: $showRecap) { WeekRecapView(onBack: { showRecap = false }) }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            Avatar(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.me?.name ?? "You")
                    .font(.dwellTitleSm)
                    .foregroundStyle(t.textPrimary)
                Text("\(session.me?.timezone.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? "") · \(languageName)")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Text("⚙").font(.system(size: 19)).foregroundStyle(t.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.sm)
    }

    private var languageName: String {
        let code = session.me?.preferredLanguage ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private var groupCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group?.name ?? "No group")
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                        Text(statusLabel)
                            .font(.dwellCaption)
                            .foregroundStyle(group?.challengeStatus == .active ? t.success : t.textSecondary)
                    }
                    Spacer()
                }
                Rectangle().fill(t.border).frame(height: 1)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Invite code")
                        Text(group?.inviteToken ?? "——————")
                            .font(.dwellCode)
                            .foregroundStyle(t.textPrimary)
                    }
                    Spacer()
                    Text(session.plan?.title.components(separatedBy: ":").first ?? "")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                }
            }
        }
    }

    private var statusLabel: String {
        guard let group else { return "—" }
        let day = session.currentDay?.dayIndex ?? 0
        switch group.challengeStatus {
        case .active:  return "Day \(day) · active"
        case .forming: return "Forming"
        case .paused:  return "Paused"
        case .completed: return "Completed"
        case .abandoned: return "Ended"
        case .expiredIncomplete: return "Closed out"
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.dwellBody).foregroundStyle(t.textPrimary)
                Spacer()
                Text("›").foregroundStyle(t.textTertiary)
            }
            .padding(.vertical, Space.md + 2)
        }
        .buttonStyle(.plain)
    }

    private func loadStats() async {
        guard let g = group else { return }
        guard let days = try? await session.api.dayInstances(groupId: g.id) else { return }
        var mine = 0
        for day in days {
            let list = (try? await session.api.reflections(dayInstanceId: day.id)) ?? []
            mine += list.filter { $0.userId == session.me?.id }.count
        }
        stats = (mine, days.count)
    }
}
