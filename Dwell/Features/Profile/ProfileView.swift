import SwiftUI
import PhotosUI

/// Figma: "Profile · Group & Stats".
///
/// The member avatars and count are drawn, but nothing behind them is — there
/// is no member-list screen in the file, so the row is presentational for now
/// (see the design notes page). Same for the code chip: it is shown, not
/// shareable, because no post-setup share treatment exists yet.
/// `fullScreenCover(item:)` needs something Identifiable; `UIImage` isn't.
private struct CroppableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var showSettings = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var toast: Toast?
    @State private var cropping: UIImage?

    private var group: DwellGroup? { session.group.value ?? nil }

    /// Cover art for the current plan, if the catalogue has any.
    private var planArt: URL? {
        guard let path = session.plan?.imagePath else { return nil }
        return session.api.planImageURL(path: path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 300, fadeFrom: 0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    identity
                    statsStrip
                    groupCard
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.sm)
                .padding(.bottom, TabBarMetrics.clearance)
            }
            .scrollIndicators(.hidden)
            .refreshable { await session.reload() }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .toast($toast)
        .fullScreenCover(item: Binding(
            get: { cropping.map(CroppableImage.init) },
            set: { if $0 == nil { cropping = nil } })) { wrapper in
            AvatarCropper(image: wrapper.image,
                          onCancel: { cropping = nil },
                          onUse: { cropped in
                              cropping = nil
                              Task { await upload(cropped) }
                          })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onBack: { showSettings = false })
        }
    }

    private var header: some View {
        HStack {
            Text("Profile")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Settings")

            Button { } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Help")
        }
    }

    private var identity: some View {
        HStack(spacing: Space.lg) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    PhotoAvatar(name: session.me?.name ?? "You",
                                url: session.me.map { session.avatarURL(for: $0.id) } ?? nil,
                                size: 96)
                    ZStack {
                        Circle().fill(t.background)
                        if uploadingAvatar {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(t.textPrimary)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(PressScale())
            .disabled(uploadingAvatar)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(session.me?.name ?? "You")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                if let place = placeLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15))
                        Text(place)
                    }
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// There is no city on `users` — only an IANA timezone — so this shows the
    /// zone's locality rather than inventing a location.
    private var placeLabel: String? {
        guard let zone = session.me?.timezone, zone != "UTC" else { return nil }
        return zone.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ")
    }

    private var groupCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(group?.name ?? "No group")
                    .font(.dwellCardTitleStrong)
                    .foregroundStyle(t.textPrimary)
                Spacer(minLength: Space.sm)
                if let code = group?.inviteToken {
                    Text("Code: \(code)")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.accent)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, Space.sm)
                        .background(t.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }

            HStack(spacing: Space.md) {
                PlanCoverThumb(title: session.plan?.title ?? "", imageURL: planArt, size: 56, corner: Radius.sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Plan")
                        .font(.dwellBody)
                        .foregroundStyle(t.textSecondary)
                    Text(session.plan?.title ?? "—")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                }
                Spacer(minLength: 0)
            }

            progress

            HStack(spacing: Space.md) {
                MemberAvatarRow(members: session.members.map {
                    (name: session.memberProfiles[$0.userId]?.name ?? "Member",
                     url: session.avatarURL(for: $0.userId),
                     posted: false)
                }, size: 40)
                Text("\(session.members.count) Member\(session.members.count == 1 ? "" : "s")")
                    .font(.dwellCardTitle)
                    .foregroundStyle(t.textPrimary)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private var progress: some View {
        let total = session.plan?.dayCount ?? 7
        let day = session.currentDay?.dayIndex ?? 0
        return VStack(alignment: .leading, spacing: Space.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.surfaceRaised)
                    Capsule().fill(t.accent)
                        .frame(width: geo.size.width * fraction(day, total))
                }
            }
            .frame(height: 8)

            HStack {
                Text("Challenge Progress")
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                Spacer()
                Text(day > 0 ? "Day \(day) of \(total)" : "Not started")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.accent)
            }
        }
    }

    /// Where you stand in the challenge.
    ///
    /// The score is `leaderboard_entries.participation_score` — computed
    /// server-side, so it is the one number here the client isn't deriving.
    /// There are no rows until the first Monday 00:00 UTC, so that tile falls
    /// back to days read, which is always true.
    ///
    /// Everything is read from what the session already holds; the version
    /// this replaces cost one request per day just to count your own posts.
    private var statsStrip: some View {
        HStack(spacing: Space.md) {
            if let score = session.myScore {
                statTile("\(score)", session.myRank.map { "Score · #\($0)" } ?? "Score")
            } else {
                statTile("\(session.completedDayIds.count)", "Days read")
            }
            statTile("\(session.currentStreak)", "Day streak")
            statTile("\(session.myReflections.count)", "Reflections")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private func fraction(_ day: Int, _ total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return min(max(CGFloat(day) / CGFloat(total), 0), 1)
    }

    /// Streak and reflection count come from the caller's own rows. Highlights
    /// are a YouVersion concept requiring their authenticated HighlightsClient,
    /// which isn't wired — so it stays at zero rather than showing a number we
    /// can't source.
    /// Picking hands off to the cropper rather than uploading straight away —
    /// an avatar is shown in a circle everywhere, so framing it is the user's
    /// call, not a centre-crop's.
    private func load(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            toast = .failure("That image couldn't be read.")
            return
        }
        cropping = image
    }

    /// Downscales and re-encodes before upload — which also strips the GPS
    /// data a library photo carries.
    private func upload(_ image: UIImage) async {
        uploadingAvatar = true
        // The upload and the moderation pass both happen inside this call, and
        // together they take long enough that silence reads as nothing having
        // happened.
        let started = ContinuousClock.now
        toast = .working("Checking your photo…")
        defer { uploadingAvatar = false }

        guard let data = image.jpegData(compressionQuality: 0.9),
              let prepared = ImagePrep.jpeg(from: data, maxLongEdge: 800) else {
            toast = .failure("That image couldn't be read.")
            return
        }

        var outcome: Toast
        var accepted = false
        do {
            try await session.setAvatar(fileURL: prepared.fileURL, mime: prepared.mime)
            // Moderation is synchronous — a success here means it already
            // passed, so saying "under review" would be untrue.
            outcome = .success("Profile photo updated")
            accepted = true
        } catch {
            outcome = .failure(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: prepared.fileURL)

        await holdFor(minimum: .seconds(2.6), since: started)
        accepted ? Haptics.posted() : Haptics.warning()
        toast = outcome
    }

    /// Keeps a progress message on screen long enough to actually be read.
    ///
    /// The call often returns faster than the message registers, which left the
    /// check looking like it had been skipped — and that someone's photo was
    /// reviewed before their group sees it is worth communicating.
    private func holdFor(minimum: Duration, since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        guard elapsed < minimum else { return }
        try? await Task.sleep(for: minimum - elapsed)
    }

}
