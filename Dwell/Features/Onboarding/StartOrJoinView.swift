import SwiftUI

/// Figma: "Start or Join Group". The fork — create, or enter a code.
struct StartOrJoinView: View {
    /// True when reached from "Start a new plan" on a finished group: not a
    /// step in a walk, so no progress bar — just the back arrow.
    var standalone: Bool = false
    /// nil when this is where the flow began — a signed-in user with no
    /// group has no earlier step to go back to.
    var onBack: (() -> Void)?
    var onCreate: () -> Void = {}
    var onJoined: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var code = ""
    @State private var preview: GroupPreview?
    @State private var message: String?
    @State private var joining = false

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 340, fadeFrom: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                if standalone, let onBack {
                    OnboardingBackBar(onBack: onBack)
                } else {
                    OnboardingHeader(progress: 0.42, onBack: onBack)
                }

                Text("Start a group, or join one.")
                    .font(.dwellTitle)
                    .lineSpacing(LineSpacing.title)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xl)

                makeGroupCard

                joinCard.padding(.top, Space.lg)

                Spacer()

                PrimaryButton(title: joining ? "Joining…" : "Continue",
                              enabled: preview != nil,
                              loading: joining) {
                    Task { await join() }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
        // A magic link (dwell://join/4K9QRT) lands the code here rather than
        // making someone retype what they just tapped. RootView parks it on
        // the session; this is the only place that consumes it.
        .task(id: session.pendingInviteToken) {
            guard let token = session.pendingInviteToken else { return }
            session.pendingInviteToken = nil
            code = token
            await lookUp(token)
        }
    }

    /// The create path is the louder of the two — sky behind it, a cluster of
    /// faces in the top-right, and the only filled button on screen.
    ///
    /// The photo goes in `.background` rather than a ZStack sibling: as a
    /// sibling its intrinsic size drives the stack and pushes the content out.
    private var makeGroupCard: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer(minLength: 0)
            Text("Make a group")
                .font(.dwellCardTitle)
                .tracking(-0.48)
                .foregroundStyle(t.textPrimary)
            Text("Pick a plan and set a rhythm.")
                .font(.dwellBody)
                .foregroundStyle(t.textSecondary)
            PrimaryButton(title: "Create", action: onCreate)
                .padding(.top, Space.md)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, minHeight: 204, maxHeight: 204, alignment: .bottomLeading)
        .background {
            // scaledToFill overflows the card hugely, and clipShape only
            // clips what's drawn, not what's tappable — the invisible
            // overflow sat over the header and ate the Back button's taps.
            ZStack(alignment: .topTrailing) {
                Image("SkyHero")
                    .resizable()
                    .scaledToFill()
                    .overlay(t.background.opacity(0.62))
                FaceCluster()
                    .padding(.top, Space.sm)
                    .padding(.trailing, Space.sm)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Join with a code")
                .font(.dwellCardTitle)
                .tracking(-0.48)
                .foregroundStyle(t.textPrimary)

            CodeInput(code: $code)
                .onChange(of: code) { _, new in
                    preview = nil; message = nil
                    if new.count == 6 { Task { await lookUp(new) } }
                }

            if let preview {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name)
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Text(preview.planTitle)
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                }
            } else if let message {
                Text(message).font(.dwellSmall).foregroundStyle(t.textSecondary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private func lookUp(_ token: String) async {
        do {
            preview = try await session.api.previewGroup(inviteToken: token)
            if preview == nil { message = "That code doesn't match a group." }
            else { Haptics.tap() }
        } catch {
            message = error.localizedDescription
        }
    }

    private func join() async {
        joining = true
        defer { joining = false }
        do {
            _ = try await session.api.joinGroup(inviteToken: code)
            Haptics.posted()
            // Deliberately does NOT bootstrap here. Loading the group before
            // the flow has marked itself still-running makes the router flip
            // to .home and straight back to .onboarding, which rebuilds this
            // whole flow and resets its step — landing the user back on this
            // screen with an empty code field. The caller sets the flag first,
            // then reloads.
            onJoined()
        } catch {
            Haptics.warning()
            message = error.localizedDescription
        }
    }
}

/// Overlapping faces, tucked into the create card's top-right corner.
struct FaceCluster: View {
    var size: CGFloat = 40

    /// Hand-placed so the cluster reads as a loose huddle, not a grid.
    private let layout: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-52,  -6, 0.92), (-20,  22, 0.80), ( 8,  -14, 0.88),
        ( 34,  16, 1.00), ( 16,  46, 0.72), (-40,  40, 0.66)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(layout.enumerated()), id: \.offset) { index, spot in
                PhotoAvatar(name: "Friend", index: index + 1, size: size * spot.scale)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: spot.x, y: spot.y)
            }
        }
        .frame(width: 130, height: 104)
        .accessibilityHidden(true)
    }
}

#Preview { StartOrJoinView() }
