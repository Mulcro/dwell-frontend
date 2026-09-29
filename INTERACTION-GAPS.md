# Interactive experience — audit

What the app needs beyond correct screens to feel like a shipped product.
Status as of 2026-09-24.

## Done

| Item | Where |
|---|---|
| **Launch screen** — paper background, no white flash | `Config/Info.plist` → `LaunchBackground` colorset |
| **Splash** — anchor mark traces in, wordmark follows, held 0.9s minimum so a fast boot still reads as an opening | `Features/SplashView.swift` |
| **App icon** — anchor on accent violet, generated, matches the splash mark | `Tools/make-icon.swift` |
| **Haptics** — one vocabulary: tap, select, posted, warning, and a reserved two-beat for the day unlocking | `Components/Haptics.swift` |
| **Route transitions** — spring between states, nudge banner slides in, all suppressed under Reduce Motion | `RootView.swift` |
| **Swipe-back** — left-edge drag on Reader / Compose / Review. The app draws its own nav bars, so there's no system pop gesture to inherit; this calls the same closure the back button does rather than reaching into UINavigationController | `Components/SwipeBack.swift` |
| **Pull-to-refresh** — Today, Feed, Memories | `.refreshable` |
| **Foreground refresh** — returning from background re-reads the day | `RootView.swift` `scenePhase` |
| **Draft persistence** — a half-written reflection survives backing out | `ComposeView` `@AppStorage` |
| **Optimistic comments** — appear instantly, roll back and restore your text on failure | `ReflectionDetailView.send()` |
| **Share sheet** — real `ShareLink` with the invite URL and a written message | `Components/ShareInvite.swift` |
| **Deep links** — `dwell://join/CODE` and `https://dwell.to/CODE` prefill the join field | `RootView.InviteLink` |
| **Retry affordance** — 502 (AI down, nothing saved) offers a retry instead of reading as data loss | `ReviewPostView` |
| **Keyboard dismissal** — interactive on every scroll surface | `.scrollDismissesKeyboard` |

## Blocked on assets from the team

| Item | What's needed |
|---|---|
| **Fonts** | Geist and Instrument Serif `.otf`/`.ttf`. Drop into `Dwell/Fonts`, add `UIAppFonts` to `Config/Info.plist` — `DwellFont` already resolves them by name and falls back until then. **Biggest single visual gap from the Figma.** |
| **Imagery** | Every image is still the design's hatch placeholder. At minimum the ambient welcome image and a day image would lift the demo. |

## Not done — deliberate

Scheduled after the hackathon unless priorities change.

| Item | Why it matters |
|---|---|
| **Dynamic Type** | Every size is fixed (`DwellFont` uses absolute points). An accessibility failure and an App Store review risk. The fix is `relativeTo:` on each token — contained to `Typography.swift`. |
| **VoiceOver labels** | Zero accessibility modifiers outside the splash. Glyph buttons (`✕ ← ◈ ⚙ ▸`) are unlabeled; hatch placeholders announce nothing. |
| **Localization** | Every string is hardcoded English, in an app whose core feature is multilingual groups. No `.lproj`, no `String(localized:)`. |
| **RTL** | Follows from localization. |
| **Speech recognition** | On-device Apple Speech per the spec. Compose has a "Simulate transcript" stand-in. |
| **Audio playback** | The listen-along bar is inert until the Audio Bible endpoint is wired. |
| **Permission priming** | Mic and notifications are never requested or explained. |
| **Skeleton loaders** | Spinners everywhere; skeletons read better on content-heavy screens. |
| **Past-day browsing** | You can't reopen Day 2 to reread it, though `dayInstances` is already loaded. |
| **Profile editing** | Name, language and timezone are display-only. |
| **Live timestamps** | "3h" is computed once and never ticks. |
