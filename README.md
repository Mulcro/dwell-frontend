# Dwell — iOS client

SwiftUI client for **Dwell** (GLOO Hackathon 2026, team SEYI): friends commit
to a shared Bible plan, the day stays sealed until enough of the group posts,
and an AI companion stays present throughout.

Built against the [Client API Contract], [MVP Spec] and [Backend Design Doc]
in Notion. Visual language comes from the SEYI Figma file, page "Define".

## Run

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # first time only
open Dwell.xcodeproj                                          # ⌘R
```

`Config/Secrets.xcconfig` is gitignored and holds `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. Never a `sb_secret_…` key: that bypasses RLS and
would give every app user full database access — `DwellConfig.keyLooksLikeASecret`
catches it at launch.

**With a key present the app talks to the real backend.** Without one it runs
on `MockDwellAPI`. `DWELL_FORCE_MOCK=1` pins it to the mock either way.

Debug helpers:

```sh
DWELL_SELFTEST=1                 # exercise every API call, write results to the container
DWELL_GROUP="Below threshold"    # pin which seeded group to load
DWELL_STEP=stats                 # open a specific onboarding step
DWELL_SCENARIO="Day unlocked"    # seed the mock backend
```

Demo accounts: `demo-alice@dwell.test` (also bob, carol), password
`dwell-demo-2026`.

Debug builds open on **Day 3, you haven't posted**. The `scenarios` pill
(top-right) jumps the whole app to any of 15 states — it reseeds the mock
backend and lets the real router decide what to show.

Launch straight into one:

```sh
SIMCTL_CHILD_DWELL_SCENARIO="Day unlocked — feed" \
  xcrun simctl launch booted com.dwell.app
```

## Architecture

```
Dwell/
  DesignSystem/   Theme, Tokens, Typography — rebuilt for the 2026-09-28 redesign
  Components/     Buttons, Inputs, OnboardingChrome, SkyBackground,
                  StateViews (loading/empty/error), Haptics, SwipeBack
  Core/
    Models/       1:1 mirror of the Postgres schema + 7 enums
    API/
      DwellAPI.swift          the whole backend surface, one protocol
      MockDwellAPI.swift      in-memory; 15 scenarios; enforces the real rules
      SupabaseDwellAPI.swift  stub — every method annotated with its route
      Seed.swift              Anchored 7-day plan, matching plan_days exactly
    Session/
      SessionStore            auth + group + day + my reflection
      Router                  challenge_status × day_status × my post → screen
      Loadable                idle / loading / loaded / failed
  Features/
    Onboarding/   the redesigned flow, 12 screens
    Home/         placeholder until the daily loop is redesigned
```

`Archive/LegacyUI/` holds the previous daily-loop build — complete and wired
to the API layer, in the superseded dark design language. It comes back
screen by screen as the new comps land.

### The API boundary

`DwellAPI` mirrors the Backend Design Doc section by section — the 5 client
Edge Functions as async methods, the 8 PostgREST tables as typed reads/writes,
the 2 realtime channels as `AsyncStream`s, plus the mock PlanService and
passage fetch. Models decode straight off PostgREST (`CodingKeys` carry the
real column names), so going live means filling in `SupabaseDwellAPI` and
changing one line in `DwellApp.swift`. No screen knows which backend it has.

`MockDwellAPI` enforces the rules that matter to the UI rather than just
returning fixtures — the reflection lock, threshold math against members who
joined before the day opened, `is_late` from the rolling 24h window, and
moderation gating on approval. If a screen would break against real RLS, it
breaks against the mock first.

### The router

One state machine, in `Core/Session/Router.swift`:

```
!signed in                       → Auth
signed in, no group              → Create / Join
forming                          → Forming (waiting for #2)
active + inactivity prompt       → Continue / Pause / End
active + no post                 → Today → Reader → Compose → Review
active + post pending            → Pending
active + post flagged            → Flagged
active + posted, below threshold → Waiting (sealed)
active + threshold met           → Feed → Detail → Pulse
paused                           → Paused
completed                        → Completion → Journey
abandoned / expired_incomplete   → Fallback recap
```

## Design system

Rebuilt 2026-09-28 from the Figma redesign (page "Define", the 402×874 frames):

| Token | Value |
|---|---|
| Ink / buttons / primary text | `#282828` |
| Accent | `#00C0E8` |
| Surface | `#FFFFFF`, raised `#F7F7F7` |
| Border | `#787878` @ 20%, strong `#D9D9D9` |
| Hero | SF Pro Bold 48 / lh 57.6 / tracking −0.96 |
| Title | SF Pro Semibold 32 / lh 38.4 |
| Body | Inter Regular 16 / lh 22.4 |
| Radii | 8 / 12 / 16 / 32 / pill |

Screens are drawn at 402pt — the iPhone 16 Pro logical width — so values are
1:1 with no scaling. The redesign is light-only; `DwellTheme.lockLight` pins
the app to light rather than rendering an undesigned dark palette.

## Content

Seeded with the redesign's plans — **When Life Gets Hard** and **The Psalms: A
Roadmap to Resilience**, both 7 days. These differ from the backend's seeded
"Anchored" plan; see FOR-BACKEND.md.

## Contract conformance

Aligned to the Client API Contract (2026-09-24):

- `frequency` (`daily` / `weekdays` / `three_per_week`) is a live control
  again — the MVP Spec's daily-only note is superseded.
- `create-group` sends `timezone`; omitting it silently gives the group UTC
  and breaks weekday/MWF day math.
- The user's own row is PATCHed on first sight of the `'UTC'`/`'en'`
  placeholders, since `preferred_language` is what group-mates' translations
  target.
- `inactivity_prompt` is a fifth insight type and drives the Continue /
  Pause / End route.
- Errors map to the contract's status table. Two are states rather than
  failures: **409** (already posted, or day closed) and **502** (AI down,
  nothing saved — the UI offers a retry).
- `preview_group` returns an array; empty means unknown token, not an error.

## Known gaps

- **[FOR-BACKEND.md](FOR-BACKEND.md)** — open questions and blockers, including
  three new conflicts the redesign introduced (email/password auth, frequency
  values, plan catalogue).
- **[DESIGN-GAPS.md](DESIGN-GAPS.md)** — what the redesign covers, what's still
  in the old language, and the open design questions.
- **[INTERACTION-GAPS.md](INTERACTION-GAPS.md)** — feel and mechanics; what's
  deferred (Dynamic Type, VoiceOver, localization).
- **Inter** isn't bundled — body text falls back to the system face. Drop the
  files into `Dwell/Fonts` and add `UIAppFonts`. SF Pro *is* the system face,
  so headlines and buttons are already correct.
- **The real backend is wired.** `SupabaseDwellAPI` is implemented against
  `supabase-swift` 2.55.2 and verified live. The mock remains for offline work
  and for driving states the seed doesn't cover.

[Client API Contract]: https://app.notion.com/p/3e5d36984c6e81faaecad797886ff45d
[MVP Spec]: https://app.notion.com/p/3d1d36984c6e81c9bf88d4555ed223ce
[Backend Design Doc]: https://app.notion.com/p/3ded36984c6e81c59f8bdaa7a1902589
