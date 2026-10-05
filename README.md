# Dwell — iOS client

**Dwell is a daily Bible-reading app for small groups of friends.** Two to seven
people pick a reading plan, read the same passage each day, and post a short
reflection in text, voice or a photo. The day is **sealed**: you can't read
anyone's reflection until you've posted your own and half the group has posted.
Then it unlocks for everyone at once, and an AI companion called Eagle reflects
back what the group noticed together.

This repository is the **SwiftUI iOS client** (GLOO Hackathon 2026, team SEYI).
The backend, including the full AI pipeline, is
[Mulcro/dwell-backend](https://github.com/Mulcro/dwell-backend).

## What you see AI do in the app

- **Eagle's reply** under each of your reflections, in your language (Feed).
- **Translation**: reflections, replies and the Group Pulse appear in each
  reader's language and say "Translated from". Reflections and the Pulse also
  offer "See original"; replies show the label only. Eagle's reply is shown in
  the author's language (the backend stores its translations, but the app
  doesn't display them yet).
- **Group Pulse**: once a day unlocks, a headline about what the group noticed,
  and each member's stated intention (Home, Pulse).
- **Weekly and end-of-challenge recaps**: the thread the group kept coming
  back to, and a line on what each person brought (Recap).
- **Nudges** when you're falling behind, in-app.
- **Transcription** of voice reflections with Apple Speech
  (`Core/Speech/SpeechRecognizer.swift`): on-device wherever the language
  supports it, otherwise Apple's speech service. No server-side speech model.
- **Moderation** runs before anything you post reaches anyone else.

The backend README has the full map of models and design choices:
[How Dwell uses AI](https://github.com/Mulcro/dwell-backend#how-dwell-uses-ai).

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
  xcrun simctl launch booted com.mulero.dwell
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
      SupabaseDwellAPI.swift  the live backend, on supabase-swift 2.55.2
      Seed.swift              plan fixtures for the mock
    Session/
      SessionStore            auth + group + day + my reflection
      Router                  challenge_status × day_status × my post → screen
      Loadable                idle / loading / loaded / failed
  Features/
    Onboarding/   sign-in, create or join, plan picker, rhythm
    Home/         today's state: sealed, unlocked, finished, What's Next
    Reading/      the day's passage in YouVersion's SDK reader
    Reflect/      compose text, voice (with transcription) or photo
    Feed/         the unlocked day: reflections, Eagle, replies, reactions
    Pulse/        the Group Pulse card
    Recap/        weekly and end-of-challenge recaps, archived challenges
    Memories/     calendar and timeline of your reflections
    Stalled/      continue, pause or end a quiet challenge
    Profile/      account, picture, language, delete account
```

`Archive/LegacyUI/` is **not part of the app target** (only `Dwell/` is
compiled). It is the pre-redesign build, kept as a reference while screens were
ported to the new design.

### The API boundary

`DwellAPI` mirrors the Backend Design Doc section by section — the 5 client
Edge Functions as async methods, the 8 PostgREST tables as typed reads/writes,
the 2 realtime channels as `AsyncStream`s, plus the mock PlanService and
passage fetch. Models decode straight off PostgREST (`CodingKeys` carry the
real column names). `SupabaseDwellAPI` is the live implementation and
`MockDwellAPI` the offline one; no screen knows which backend it has.

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

Against the live backend, the picker shows the plans the backend lists: **Be
Still** (3 days), **Better Together** (7) and **Abide** (14), each with a
description, key verse, titled days and cover art. The offline mock seeds two
older 7-day plans instead (When Life Gets Hard, The Psalms).

The reading screen is YouVersion's own `BibleReaderView` from the YouVersion
Platform Swift SDK (`Core/API/YouVersionReader.swift`), handed each day's
reference.

## Contract conformance

Aligned to the Client API Contract (2026-09-24):

- `frequency`: the app offers `daily`, `four_per_week` and `custom` (chosen
  weekdays). `weekdays` and `three_per_week` also exist on the wire, so a group
  created elsewhere still decodes, but aren't offered in the picker.
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

- Dynamic Type, VoiceOver and full localization of the UI chrome are deferred.
- **Inter** isn't bundled — body text falls back to the system face. Drop the
  files into `Dwell/Fonts` and add `UIAppFonts`. SF Pro *is* the system face,
  so headlines and buttons are already correct.

[Client API Contract]: https://app.notion.com/p/3e5d36984c6e81faaecad797886ff45d
[MVP Spec]: https://app.notion.com/p/3d1d36984c6e81c9bf88d4555ed223ce
[Backend Design Doc]: https://app.notion.com/p/3ded36984c6e81c59f8bdaa7a1902589

## License

MIT — see [LICENSE](LICENSE).
