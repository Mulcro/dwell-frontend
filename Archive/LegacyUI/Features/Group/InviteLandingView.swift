import SwiftUI

/// The browser-hosted invite page, backed by `/preview-group` — the one public
/// unauthenticated call in the API (§1.1).
struct InviteLandingView: View {
    let inviteToken: String
    var onBack: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var preview: Loadable<GroupPreview?> = .idle

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Button(action: onBack) {
                    Text("⌂").foregroundStyle(t.textSecondary)
                }
                .buttonStyle(.plain)
                Text("dwell.to/\(inviteToken)")
                    .font(.dwellMonoSm)
                    .foregroundStyle(t.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(t.surfaceAlt)

            LoadableView(state: preview, retry: { Task { await load() } }) { info in
                if let info {
                    body(for: info)
                } else {
                    EmptyStateView(
                        title: "This invite has expired",
                        message: "Ask whoever sent it for a fresh link or code.")
                }
            }
        }
        .task { await load() }
    }

    private func body(for info: GroupPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Avatar(size: 44).padding(.top, Space.xxl)

            Text("You've been invited to\n\(info.name)")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .padding(.top, Space.lg)

            VStack(spacing: 0) {
                row("Plan", info.planTitle)
                Rectangle().fill(t.border).frame(height: 1)
                row("Rhythm", "Daily, your own 24-hour window")
                Rectangle().fill(t.border).frame(height: 1)
                row("Unlocks at", "Half the group posted")
            }
            .padding(.horizontal, Space.lg)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .padding(.top, Space.xl)

            Text("Post your first reflection right here in the browser. Install later if you want reminders.")
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(4)
                .padding(.top, Space.xl)

            Spacer()

            DwellButton(title: "Join the group") {
                Task {
                    _ = try? await session.api.joinGroup(inviteToken: inviteToken)
                    await session.bootstrap()
                }
            }

            Text("Reflections are private until you post them.")
                .font(.dwellCaption)
                .foregroundStyle(t.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Space.md)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.dwellFootnote).foregroundStyle(t.textSecondary)
            Spacer()
            Text(value)
                .font(.dwellFootnoteMd)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Space.md)
    }

    private func load() async {
        preview = .loading
        do { preview = .loaded(try await session.api.previewGroup(inviteToken: inviteToken)) }
        catch { preview = .failed(error.localizedDescription) }
    }
}
