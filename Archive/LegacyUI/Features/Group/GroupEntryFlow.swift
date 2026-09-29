import SwiftUI

/// Signed in, no group yet: create one or join with a code.
struct GroupEntryFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var step: Step = .choose

    enum Step: Equatable { case choose, pickPlan, setup(UUID), joining }

    var body: some View {
        switch step {
        case .choose:
            GroupEntryView(
                onCreate: { step = .pickPlan },
                onJoined: { Task { await session.bootstrap() } })

        case .pickPlan:
            PlanPickerView(
                onBack: { step = .choose },
                onPick: { plan in step = .setup(plan.id) })

        case .setup(let planId):
            GroupSetupView(planId: planId,
                           onBack: { step = .pickPlan },
                           onCreated: { Task { await session.bootstrap() } })

        case .joining:
            LoadingView(label: "Finding your group")
        }
    }
}

struct GroupEntryView: View {
    var onCreate: () -> Void = {}
    var onJoined: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var code = ""
    @State private var preview: GroupPreview?
    @State private var error: String?
    @State private var joining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("New here").padding(.top, Space.xl)

            Text("Start a group, or step into one")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .padding(.top, Space.sm)

            Button(action: onCreate) {
                Panel(accented: true) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Create a group")
                            .font(.dwellTitleSm)
                            .foregroundStyle(t.accent)
                        Text("Pick a plan, set the rhythm, invite 2–10 people.")
                            .font(.dwellBody)
                            .foregroundStyle(t.textSecondary)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Space.xl)

            Panel {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Join with a code")
                        .font(.dwellTitleSm)
                        .foregroundStyle(t.textPrimary)

                    InviteCodeField(code: $code)
                        .onChange(of: code) { _, new in
                            if new.count == 6 { Task { await lookUp(new) } }
                        }

                    if let preview {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preview.name)")
                                .font(.dwellBodyMd)
                                .foregroundStyle(t.textPrimary)
                            Text(preview.planTitle)
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                        }
                        DwellButton(title: joining ? "Joining…" : "Join \(preview.name)") {
                            Haptics.tap()
                            Task { await join() }
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.dwellCaption)
                            .foregroundStyle(t.textSecondary)
                    }
                }
            }
            .padding(.top, Space.md)

            Spacer()

            Text("A group is 2–10 people. You can be in one at a time.")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .task(id: session.pendingInviteToken) {
            // Arrived via dwell://join/CODE or a dwell.to link.
            guard let token = session.pendingInviteToken else { return }
            code = token
            await lookUp(token)
            session.pendingInviteToken = nil
        }
    }

    private func lookUp(_ token: String) async {
        error = nil
        do {
            preview = try await session.api.previewGroup(inviteToken: token)
            if preview == nil { error = "That code doesn't match a group." }
        } catch {
            preview = nil
            self.error = error.localizedDescription
        }
    }

    private func join() async {
        joining = true
        defer { joining = false }
        do {
            _ = try await session.api.joinGroup(inviteToken: code)
            Haptics.posted()
            onJoined()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}

/// Six-box invite-code entry backed by a real (hidden) text field.
struct InviteCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .opacity(0.01)
                .onChange(of: code) { _, new in
                    code = String(new.uppercased().filter(\.isLetter).prefix(6))
                        + String(new.uppercased().filter(\.isNumber).prefix(6))
                    code = String(new.uppercased().prefix(6))
                }

            HStack(spacing: Space.sm) {
                ForEach(0..<6, id: \.self) { index in
                    let char = index < code.count
                        ? String(Array(code)[index]) : nil
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(index == code.count && focused ? t.accent : t.border,
                                          lineWidth: 1)
                        Text(char ?? "—")
                            .font(.dwellCode)
                            .foregroundStyle(char == nil ? t.textTertiary : t.textPrimary)
                    }
                    .frame(height: 52)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
    }
}
