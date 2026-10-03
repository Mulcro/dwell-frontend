import SwiftUI

/// Figma: "02b · Dwell Plans" — the plan detail screen opened from the
/// picker's rows.
///
/// The comps carry a description, a key verse and a titled day list. The
/// backend has the day list's passages but none of the other columns yet, so
/// each section renders only when its data exists and lights up without a
/// client release when the columns land — raised in Notion as a backend
/// request.
struct PlanDetailView: View {
    let plan: PlanChallenge
    var onClose: () -> Void = {}
    var onStart: (PlanChallenge) -> Void = { _ in }

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var days: Loadable<[PlanDay]> = .idle

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 280, fadeFrom: 0.25)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        PlanCover(title: plan.title,
                                  imageURL: plan.imagePath.flatMap { session.api.planImageURL(path: $0) })
                            .frame(height: 200)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))

                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(plan.title)
                                .font(.dwellTitle)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(plan.dayCount) day\(plan.dayCount == 1 ? "" : "s")")
                                .font(.dwellSmallMd)
                                .foregroundStyle(t.textSecondary)

                            if let description = plan.planDescription {
                                Text(description)
                                    .font(.dwellBody)
                                    .foregroundStyle(t.textSecondary)
                                    .lineSpacing(LineSpacing.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, Space.xs)
                            }
                        }

                        if let verse = plan.keyVerse {
                            keyVerseCard(verse, ref: plan.keyVerseRef)
                        }

                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("What's inside")
                                .font(.dwellCardTitleStrong)
                                .foregroundStyle(t.textPrimary)

                            LoadableView(state: days, retry: { Task { await load() } }) { list in
                                dayList(list)
                            }
                        }
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)

                PrimaryButton(title: "Start with your group", accent: true) {
                    onStart(plan)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(t.textPrimary)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Back")

            Text("Plan details")
                .font(DwellFont.sf(20, .semibold))
                .foregroundStyle(t.textPrimary)

            Spacer()
        }
        .padding(.top, Space.sm)
    }

    private func keyVerseCard(_ verse: String, ref: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("“\(verse)”")
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(t.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let ref {
                Text(ref.uppercased())
                    .font(.dwellCaptionMd)
                    .tracking(1.2)
                    .foregroundStyle(t.accent)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dayList(_ list: [PlanDay]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { day in
                HStack(alignment: .top, spacing: Space.md) {
                    Text(String(format: "%02d", day.dayIndex))
                        .font(.dwellCaptionMd)
                        .foregroundStyle(t.accent)
                        .frame(width: 24, alignment: .leading)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.title ?? passageDisplay(day))
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if day.title != nil {
                            Text(passageDisplay(day))
                                .font(.dwellSmall)
                                .foregroundStyle(t.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.md)

                if day.id != list.last?.id {
                    Divider().overlay(t.border)
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    /// "PSA.46.1-11" → "Psalm 46:1–11". Falls back to the raw ref rather than
    /// guessing at a book it doesn't know.
    private func passageDisplay(_ day: PlanDay) -> String {
        guard let ref = YouVersionReader.reference(fromUSFM: day.passageRef) else {
            return day.passageRef
        }
        let book = Self.bookNames[ref.bookUSFM] ?? ref.bookUSFM.capitalized
        guard let start = ref.verseStart else { return "\(book) \(ref.chapter)" }
        guard let end = ref.verseEnd, end != start else { return "\(book) \(ref.chapter):\(start)" }
        return "\(book) \(ref.chapter):\(start)–\(end)"
    }

    /// USFM book codes → display names, for the day list only — the reader
    /// gets its names from YouVersion itself.
    private static let bookNames: [String: String] = [
        "GEN": "Genesis", "EXO": "Exodus", "LEV": "Leviticus", "NUM": "Numbers",
        "DEU": "Deuteronomy", "JOS": "Joshua", "JDG": "Judges", "RUT": "Ruth",
        "1SA": "1 Samuel", "2SA": "2 Samuel", "1KI": "1 Kings", "2KI": "2 Kings",
        "1CH": "1 Chronicles", "2CH": "2 Chronicles", "EZR": "Ezra", "NEH": "Nehemiah",
        "EST": "Esther", "JOB": "Job", "PSA": "Psalm", "PRO": "Proverbs",
        "ECC": "Ecclesiastes", "SNG": "Song of Songs", "ISA": "Isaiah", "JER": "Jeremiah",
        "LAM": "Lamentations", "EZK": "Ezekiel", "DAN": "Daniel", "HOS": "Hosea",
        "JOL": "Joel", "AMO": "Amos", "OBA": "Obadiah", "JON": "Jonah",
        "MIC": "Micah", "NAM": "Nahum", "HAB": "Habakkuk", "ZEP": "Zephaniah",
        "HAG": "Haggai", "ZEC": "Zechariah", "MAL": "Malachi",
        "MAT": "Matthew", "MRK": "Mark", "LUK": "Luke", "JHN": "John",
        "ACT": "Acts", "ROM": "Romans", "1CO": "1 Corinthians", "2CO": "2 Corinthians",
        "GAL": "Galatians", "EPH": "Ephesians", "PHP": "Philippians", "COL": "Colossians",
        "1TH": "1 Thessalonians", "2TH": "2 Thessalonians", "1TI": "1 Timothy",
        "2TI": "2 Timothy", "TIT": "Titus", "PHM": "Philemon", "HEB": "Hebrews",
        "JAS": "James", "1PE": "1 Peter", "2PE": "2 Peter", "1JN": "1 John",
        "2JN": "2 John", "3JN": "3 John", "JUD": "Jude", "REV": "Revelation",
    ]

    private func load() async {
        days = .loading
        do {
            let list = try await session.api.getPlanDays(planId: plan.id)
            days = .loaded(list.sorted { $0.dayIndex < $1.dayIndex })
        } catch {
            days = .failed(error.localizedDescription)
        }
    }
}
