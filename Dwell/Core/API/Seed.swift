import Foundation

/// Seed data for the mock backend. Mirrors the Backend Design Doc §3.4 seed
/// plan exactly — same plan id, same USFM refs, same order.
///
/// Passage text here is World English Bible (public domain). Real text is
/// always fetched live from the Passages API by ref; this stands in offline.
enum Seed {

    static let planId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let jamesPlanId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    static let groupId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    static let maya   = DwellUser(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!, name: "Maya Chen",     preferredLanguage: "en", timezone: "America/New_York", pushToken: nil, createdAt: .now)
    static let priya  = DwellUser(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!, name: "Priya Sharma",  preferredLanguage: "hi", timezone: "Asia/Kolkata",     pushToken: nil, createdAt: .now)
    static let jordan = DwellUser(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, name: "Jordan Reyes",  preferredLanguage: "en", timezone: "America/Los_Angeles", pushToken: nil, createdAt: .now)
    static let daniel = DwellUser(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C4")!, name: "Daniel Osei",   preferredLanguage: "ak", timezone: "Africa/Accra",     pushToken: nil, createdAt: .now)

    static var allUsers: [DwellUser] { [maya, priya, jordan, daniel] }

    static let anchored = PlanChallenge(
        id: planId,
        title: "When Life Gets Hard",
        sourceType: .youversionPlan,
        dayCount: 7,
        youversionPlanId: "mock-anchored-hope-7",
        youversionDeepLink: "https://www.bible.com/reading-plans/mock-anchored-hope-7"
    )

    /// A second entry so the plan picker has a real choice to make.
    static let james = PlanChallenge(
        id: jamesPlanId,
        title: "The Psalms: A Roadmap to Resilience",
        sourceType: .youversionPlan,
        dayCount: 7,
        youversionPlanId: "mock-psalms-7",
        youversionDeepLink: nil
    )

    static var plans: [PlanChallenge] { [anchored, james] }

    static let anchoredDays: [PlanDay] = [
        PlanDay(planChallengeId: planId, dayIndex: 1, passageRef: "HEB.6.19"),
        PlanDay(planChallengeId: planId, dayIndex: 2, passageRef: "ISA.40.31"),
        PlanDay(planChallengeId: planId, dayIndex: 3, passageRef: "ROM.5.3-5"),
        PlanDay(planChallengeId: planId, dayIndex: 4, passageRef: "LAM.3.22-23"),
        PlanDay(planChallengeId: planId, dayIndex: 5, passageRef: "ROM.8.28"),
        PlanDay(planChallengeId: planId, dayIndex: 6, passageRef: "1PE.3.15"),
        PlanDay(planChallengeId: planId, dayIndex: 7, passageRef: "REV.21.4-5")
    ]

    /// Theme line per day, used as the passage subtitle on Today.
    static let dayThemes: [String: String] = [
        "HEB.6.19":    "an anchor for the soul",
        "ISA.40.31":   "hope renews strength",
        "ROM.5.3-5":   "suffering builds hope",
        "LAM.3.22-23": "mercies new every morning",
        "ROM.8.28":    "God works for good",
        "1PE.3.15":    "a reason for the hope you have",
        "REV.21.4-5":  "all things new"
    ]

    /// Offline stand-ins shaped exactly like `get-passage`. The real client
    /// always calls the function; these only cover the mock.
    static let passages: [String: Passage] = [
        "HEB.6.19":    passage("HEB.6.19", "Hebrews 6:19",
            "We have this hope as an anchor for the soul, firm and secure. It enters the inner sanctuary behind the curtain,"),
        "ISA.40.31":   passage("ISA.40.31", "Isaiah 40:31",
            "But those who wait upon the LORD will renew their strength; they will mount up with wings like eagles; they will run and not grow weary; they will walk and not faint."),
        "ROM.5.3-5":   passage("ROM.5.3-5", "Romans 5:3–5",
            "Not only that, but we also rejoice in our sufferings, because we know that suffering produces perseverance; perseverance, character; and character, hope. And hope does not disappoint us, because God has poured out His love into our hearts through the Holy Spirit, whom He has given us."),
        "LAM.3.22-23": passage("LAM.3.22-23", "Lamentations 3:22–23",
            "Because of the LORD's loving devotion we are not consumed, for His compassions never fail. They are new every morning; great is Your faithfulness!"),
        "ROM.8.28":    passage("ROM.8.28", "Romans 8:28",
            "And we know that God works all things together for the good of those who love Him, who are called according to His purpose."),
        "1PE.3.15":    passage("1PE.3.15", "1 Peter 3:15",
            "But in your hearts sanctify Christ as Lord. Always be prepared to give a defense to everyone who asks you the reason for the hope that is in you. But respond with gentleness and respect,"),
        "REV.21.4-5":  passage("REV.21.4-5", "Revelation 21:4–5",
            "He will wipe away every tear from their eyes, and there will be no more death or mourning or crying or pain, for the former things have passed away. And the One seated on the throne said, \"Behold, I make all things new!\"")
    ]

    private static func passage(_ ref: String, _ reference: String, _ content: String) -> Passage {
        Passage(ref: ref, bibleId: 3034, reference: reference,
                translation: "BSB", content: content, audioURL: nil, cached: true)
    }
}
