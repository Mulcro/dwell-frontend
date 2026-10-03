import SwiftUI

/// Figma: "01b · How Dwell Works" — four pages between the stats and
/// Start-or-Join. The sealed day, transcription and translation, the rolling
/// 24-hour window, and Eagle are all load-bearing mechanics that nothing
/// stated up front until this sequence existed.
///
/// Each hero is a tableau built from the app's own components rather than an
/// exported image, so it keeps up when the design system moves. The people
/// are the seeded avatar set, not anyone real.
struct HowDwellWorksView: View {
    var onBack: () -> Void = {}
    var onDone: () -> Void = {}

    @Environment(\.dwell) private var t
    // DWELL_PAGE=<0-3> opens straight onto a page, for screenshots.
    @State private var page =
        Int(ProcessInfo.processInfo.environment["DWELL_PAGE"] ?? "") ?? 0

    private struct Page {
        let title: String
        let subtitle: String
        let verse: String
        let verseRef: String
    }

    private static let pages: [Page] = [
        Page(title: "The day opens when your group shows up.",
             subtitle: "Reflections stay sealed until you post yours.",
             verse: "“And let us consider how to spur one another on to love and good deeds.”",
             verseRef: "Hebrews 10:24"),
        Page(title: "Speak your language. Your group reads theirs.",
             subtitle: "Voice notes are transcribed and translated.",
             verse: "“…each one was hearing them speak his own language.”",
             verseRef: "Acts 2:6"),
        Page(title: "Your day runs on your clock.",
             subtitle: "Everyone gets 24 hours in their own time zone.",
             verse: "“His mercies never fail. They are new every morning.”",
             verseRef: "Lamentations 3:22–23"),
        Page(title: "Meet Eagle, your group's companion.",
             subtitle: "Eagle reads your reflections and helps your group go deeper together.",
             verse: "“They will mount up with wings like eagles; they will run and not grow weary.”",
             verseRef: "Isaiah 40:31"),
    ]

    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 320, fadeFrom: 0.25)

            VStack(spacing: 0) {
                // Stats sits at 0.3 and Build Group at 0.56; these four pages
                // walk the bar through the gap between them.
                OnboardingHeader(progress: 0.34 + 0.05 * Double(page),
                                 onBack: {
                                     if page > 0 { withAnimation { page -= 1 } }
                                     else { onBack() }
                                 })

                TabView(selection: $page) {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        pageBody(index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PrimaryButton(title: isLast ? "Get started" : "Continue", accent: true) {
                    if isLast { onDone() }
                    else { withAnimation { page += 1 } }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    private func pageBody(_ index: Int) -> some View {
        let p = Self.pages[index]
        return VStack(spacing: 0) {
            hero(index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Space.md) {
                Text(p.title)
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(p.subtitle)
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    Text(p.verse)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(t.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(p.verseRef.uppercased())
                        .font(.dwellCaptionMd)
                        .tracking(1.5)
                        .foregroundStyle(t.accent)
                }
                .padding(.top, Space.sm)
            }
            .padding(.bottom, Space.xl)
        }
    }

    // MARK: - Heroes

    @ViewBuilder
    private func hero(_ index: Int) -> some View {
        switch index {
        case 0: sealedHero
        case 1: voiceHero
        case 2: clockHero
        default: eagleHero
        }
    }

    /// A cluster of group members, most checked in, you still locked out.
    private var sealedHero: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                Circle().fill(.white.opacity(0.6)).frame(width: 250, height: 250)

                badged("Maya", index: 1, size: 76, badge: .check).offset(x: -102, y: -98)
                badged("Daniel", index: 4, size: 54, badge: .check).offset(x: 116, y: -82)
                badged("Jordan", index: 5, size: 50, badge: .check).offset(x: -96, y: 68)
                badged("Amara", index: 6, size: 66, badge: nil).offset(x: 126, y: 16)
                badged("Priya", index: 3, size: 124, badge: .lock)
            }

            HStack(spacing: Space.sm) {
                Image(systemName: "lock")
                    .font(.system(size: 12))
                    .foregroundStyle(t.textPrimary)
                Text("Day 5 · 3 of 5 posted")
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm + 2)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }

    /// A voice reflection as group-mates in another language see it.
    private var voiceHero: some View {
        VStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    PhotoAvatar(name: "Priya Sharma", index: 3, size: 36)
                    Text("Priya Sharma")
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                    Spacer()
                    Text("6 hours ago")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                }

                HStack(spacing: Space.md) {
                    ZStack {
                        Circle().fill(t.ink).frame(width: 34, height: 34)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(t.onInk)
                    }
                    VoiceWaveform(seed: 6, barCount: 40, height: 26)
                }

                Text("Hi everyone! Today's passage was Philippians 4:6–7: \"Do not be anxious about anything.\" Honestly, I kind of laughed when I read that, because worrying is all I've done this week…")
                    .font(.dwellSmall)
                    .foregroundStyle(t.textPrimary)
                    .lineSpacing(4)
                    .lineLimit(4)

                Text("Translated from Hindi")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)

                Text("Reply")
                    .font(.dwellButton)
                    .foregroundStyle(t.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(t.ink, in: Capsule())
            }
            .padding(Space.lg)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 24, y: 10)

            HStack(spacing: Space.sm) {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(t.textPrimary)
                Text("Hindi → English")
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm + 2)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .padding(.horizontal, Space.sm)
    }

    /// Three members, three clocks, one group.
    private var clockHero: some View {
        ZStack {
            Image(systemName: "clock")
                .font(.system(size: 110, weight: .thin))
                .foregroundStyle(t.accent)

            cityChip("Thane", "7:11 AM · Posted", index: 3, check: true)
                .offset(x: -72, y: -118)
            cityChip("Pittsburgh", "9:41 PM · 2h left", index: 1)
                .offset(x: 84, y: -62)
            cityChip("Accra", "1:41 AM · Day 5 begins", index: 4)
                .offset(x: -64, y: 96)

            Text("Late still counts")
                .font(.dwellSmallMd)
                .foregroundStyle(t.accent)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm + 2)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .offset(x: 92, y: 52)
        }
    }

    /// Eagle's orb, ringed by the four places it shows up.
    private var eagleHero: some View {
        ZStack {
            Circle().fill(t.accent.opacity(0.08)).frame(width: 210, height: 210)
            Circle().fill(t.accent.opacity(0.14)).frame(width: 140, height: 140)
            ZStack {
                Circle().fill(.white).frame(width: 88, height: 88)
                Image(systemName: "sparkle")
                    .font(.system(size: 36))
                    .foregroundStyle(t.accent)
            }
            .shadow(color: t.accent.opacity(0.35), radius: 24)

            eagleChip("Replies to your reflection").offset(x: -62, y: -126)
            eagleChip("Daily group pulse").offset(x: 92, y: -78)
            eagleChip("A gentle nudge").offset(x: -94, y: 66)
            eagleChip("Your challenge recap").offset(x: 78, y: 118)
        }
    }

    // MARK: - Pieces

    private enum Badge { case check, lock }

    private func badged(_ name: String, index: Int, size: CGFloat, badge: Badge?) -> some View {
        PhotoAvatar(name: name, index: index, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    ZStack {
                        Circle()
                            .fill(badge == .check ? t.accent : t.ink)
                            .frame(width: size * 0.32, height: size * 0.32)
                        Image(systemName: badge == .check ? "checkmark" : "lock.fill")
                            .font(.system(size: size * 0.14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
    }

    private func cityChip(_ city: String, _ detail: String, index: Int, check: Bool = false) -> some View {
        HStack(spacing: Space.sm) {
            PhotoAvatar(name: city, index: index, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(city)
                    .font(.dwellSmallMd)
                    .foregroundStyle(t.textPrimary)
                Text(detail)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
            if check {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(t.accent)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private func eagleChip(_ label: String) -> some View {
        HStack(spacing: Space.sm) {
            Circle().fill(t.accent).frame(width: 6, height: 6)
            Text(label)
                .font(.dwellSmall)
                .foregroundStyle(t.textPrimary)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

#Preview { HowDwellWorksView() }
