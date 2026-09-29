# Design status

Updated 2026-09-28, after the redesign.

## What the redesign covers

Taylor rebuilt onboarding at 402×874 in a new visual language — white surfaces,
sky photography, SF Pro + Inter, near-black buttons, cyan accent. All of it is
built:

Splash · Welcome · Sign Up · Log In modal · YouVersion Sign In · Bible
Engagement Stats · Start or Join Group · Build New Group · Frequency &
Threshold · Invite Friends · Share Group Invite · Enable Notifications

## What is not designed yet

**The entire daily loop.** Today, Reader, Compose, Review, the locked/waiting
states, Feed, reflection detail, group pulse, weekly recap, memories,
completion, journey, and the lifecycle screens (forming, paused, inactivity
prompt, fallback recap) exist only in the *previous* dark design language.

Those builds are preserved in `Archive/LegacyUI/` — they were complete and
working against the API layer. They're archived rather than deleted because
the structure (state-driven screens, the router, the mock rules) carries over;
only the visual layer changes. When the comps land, they get rebuilt against
the new design system.

`Dwell/Features/Home/HomeView.swift` is a placeholder so the app has somewhere
to arrive after onboarding. It follows the "Hi, Maya" home sketch visible in
the Figma flow board (Frame 2) but is not a faithful build of anything.

## Invented — no Figma source

| Screen | File | Why |
|---|---|---|
| Home placeholder | `Features/Home/HomeView.swift` | Somewhere to land after onboarding. |
| Loading / empty / error | `Components/StateViews.swift` | Every async surface needs all three. |

Both are marked in code.

## Open design questions

1. **Dark mode.** The redesign is light-only. `DwellTheme.lockLight` pins the
   app to light so it can't render an undesigned dark palette. Flip it off when
   dark comps exist.
2. **The CBE logo** on Bible Engagement Stats is a stand-in — needs the real
   asset exported.
3. **Custom frequency.** The design offers a "Custom" option with no screen
   behind it. What does picking it do?
4. **Sign Up "Description" fields** are placeholder text in the comp; I wrote
   real helper copy ("At least 8 characters.").
