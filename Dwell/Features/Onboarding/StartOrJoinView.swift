import SwiftUI

/// Figma: "Start or Join Group". The fork — create, or enter a code.
///
/// Reached from "Start a new plan" on a finished group, the same screen is
/// "Challenge End · What's Next": the group's name, a same-crew option, the
/// create and join cards, and the archive of finished challenges.
struct StartOrJoinView: View {
    /// True when reached from "Start a new plan" on a finished group: not a
    /// step in a walk, so no progress bar — just the back arrow.
    var standalone: Bool = false
    /// nil when this is where the flow began — a signed-in user with no
    /// group has no earlier step to go back to.
    var onBack: (() -> Void)?
    var onCreate: () -> Void = {}
    /// What's Next only: a new group for the same people. Each challenge is
    /// its own group (KAN-29), so this is create with the name carried over.
    var onSameCrew: () -> Void = {}
    var onJoined: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var code = ""
    @State private var preview: GroupPreview?
    @State private var message: String?
    @State private var joining = false
    @State private var archived: [GroupSummary] = []
    @State private var viewing: GroupSummary?

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 340, fadeFrom: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                if standalone, let onBack {
                    OnboardingBackBar(onBack: onBack)
                } else {
                    OnboardingHeader(progress: 0.42, onBack: onBack)
                }

                if standalone {
                    whatsNext
                } else {
                    Text("Start a group, or join one.")
                        .font(.dwellTitle)
                        .lineSpacing(LineSpacing.title)
                        .foregroundStyle(t.textPrimary)
                        .padding(.top, Space.lg)
                        .padding(.bottom, Space.xl)

                    makeGroupCard

                    joinCard.padding(.top, Space.lg)

                    Spacer()
                }

                if !standalone || preview != nil {
                    PrimaryButton(title: joining ? "Joining…" : "Continue",
                                  enabled: preview != nil,
                                  loading: joining) {
                        Task { await join() }
                    }
                    .padding(.top, standalone ? Space.md : 0)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
        .task(id: standalone) {
            guard standalone else { return }
            let groups = (try? await session.api.myGroups()) ?? []
            archived = groups.filter { $0.challengeStatus.isEnded }
            // DWELL_ARCHIVE=1 opens the first archived recap, for screenshots.
            if ProcessInfo.processInfo.environment["DWELL_ARCHIVE"] == "1" {
                viewing = archived.first { $0.id != session.group.value??.id }
            }
        }
        .fullScreenCover(item: $viewing) { group in
            ArchivedRecapView(group: group, onClose: { viewing = nil })
        }
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

    // MARK: - What's Next

    private var whatsNext: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(session.group.value??.name ?? "What's next")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.lg)

                Text("Keep going?")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)

                ForEach(session.continuations) { invite in
                    // The flow is still open here, so close it once the
                    // session has moved onto the new group.
                    ContinuationCard(invite: invite, onJoined: { session.finishOnboarding() })
                }

                sameCrewRow
                makeGroupCard
                joinCard

                if !archived.isEmpty {
                    Text("Archived challenges")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                        .padding(.top, Space.md)

                    ForEach(archived) { group in
                        archiveRow(group)
                    }

                    Text("Archived groups stay readable forever. Nobody can post into them again.")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Not the comp's "Keep your rhythm, threshold and day windows": the
    /// backend makes this a fresh group that everyone rejoins with a new
    /// code, and the rhythm is chosen again.
    private var sameCrewRow: some View {
        Button(action: onSameCrew) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Same crew, new plan")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Text("Same name, a new plan. Everyone rejoins with a fresh code.")
                        .font(.dwellSmall)
                        .foregroundStyle(t.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.textSecondary)
            }
            .padding(Space.lg)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
    }

    private func archiveRow(_ group: GroupSummary) -> some View {
        HStack(spacing: Space.md) {
            PlanCoverThumb(title: group.planTitle,
                           imageURL: group.planImagePath.flatMap { session.api.planImageURL(path: $0) },
                           size: 64,
                           corner: Radius.md)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Text("\(group.memberCount) members · \(group.reflectionCount) reflections")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer(minLength: Space.sm)
            Button("View") { viewing = group }
                .font(.dwellBodyMd)
                .foregroundStyle(t.textPrimary)
                .buttonStyle(PressScale())
        }
        .padding(Space.md)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
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
