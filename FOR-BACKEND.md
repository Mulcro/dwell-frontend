# Backend integration status

All 21 questions answered 2026-09-28. Contract updated, deployed, and
**verified live from this machine** (`preview_group`, `get-passage`,
`plan_challenges`, password sign-in as `demo-alice`).

## ⚠️ Stale page warning

The sub-page **"Answers for the iOS client"** is dated 9/24 and **two of its
answers were superseded on 9/28**:

| Item | Sub-page says (stale) | Actually true |
|---|---|---|
| **Passages** | "the client calls YouVersion directly… there is no backend route and none is planned" | There **is** a route — `POST /functions/v1/get-passage`. The app key stays server-side. |
| **Plans** | "`plan_challenges` has exactly one row — Anchored" | Two rows: **When Life Gets Hard** (`…a1`), **The Psalms** (`…a2`). Anchored is gone. |

Everything else on that page still holds and is worth reading — items 3, 7 and
8 corrected real client bugs.

## Corrections applied to the client

Three assumptions were wrong. All fixed:

1. **`inactivity_prompt` would have trapped users.** `target_user_id` is set
   per member (not null) and the row is **never deleted**. The client was
   treating "a row exists" as "pending", which would have stranded people on
   that screen permanently. Now reads **`groups.prompt_pending`**, which
   `group-challenge-action` clears.
2. **`is_late` is timezone-independent** — absolute elapsed time from
   `max(day.opened_at, joined_at) + 24h`. The client's docs claimed
   `users.timezone` drove it. `users.timezone` is used for **nudge delivery
   hours only**.
3. **`moderation_status` never returns `pending`** — moderation is synchronous.
   The Pending screen and its route are deleted. On 502 the row is *deleted*,
   so retry is clean.

Also applied: group cap **2–7** (was 2–10), `four_per_week` + `custom` with
`custom_days`, `is_late` inline in the submit response, `Passage` reshaped to
the real `get-passage` payload (plain `content`, no verse array), and split
error parsing — `error` for Edge Functions, `message` for PostgREST.

## Still open — but these are for Mulero, not the backend

- [x] ~~**Enable `mailer_autoconfirm`.**~~ **Done — verified live 2026-09-28.**
      A fresh `POST /auth/v1/signup` now returns a usable account and
      `grant_type=password` signs it in immediately, with no confirmation
      step. Email sign-up works on the hosted project.
- [ ] **Apple Developer credentials** (Services ID, Team ID, Key ID, `.p8`).
      Apple sign-in isn't configured. Not needed for development, but **App
      Store rules require Sign in with Apple if Google ships**, so it's needed
      before submission.
- [ ] **Copy conflict for Taylor.** The Figma says "A shared plan with 2-10
      friends"; the backend caps groups at **7** and the 8th join is a 409.
      Client copy now says 2-7 so it isn't lying — the design needs the same
      change.

## Known gaps, accepted

- **Audio is not wired.** `audio_url` is always null; the backend found no
  audio endpoint. The reader's listen-along bar stays disabled.
- **Native Google sign-in won't work yet.** `external_google_additional_client_ids`
  wouldn't persist through the Management API, so use the **browser** flow
  (`signInWithOAuth`). `signInWithIdToken` will reject the iOS token.
- **Memories cannot show skipped days.** Confirmed intended product behaviour —
  the reflection lock is permanent, not "until the day ends". Render a locked
  placeholder, not an empty list.
- **`forming` is not only a pre-launch state.** A group dropping below 2
  members reverts to `forming` with its history intact.

## ✅ Integration done

`supabase-swift` 2.55.2 is in via SPM and `SupabaseDwellAPI` is implemented.
Every call has been **run against the live project** and decoded successfully
(`DWELL_SELFTEST=1` re-runs it): sign-in, `listPlans`, `getPlanDays`,
`get-passage`, `myGroup`, `members`, `users`, `dayInstances`, `reflections`,
`insights`, `leaderboard`.

The app picks the real backend automatically when `Config/Secrets.xcconfig`
carries a publishable key, and falls back to the mock otherwise.

One decoding note: Postgres returns three date shapes — timestamptz with
fractional seconds, without, and bare `date` (`day_instances.date`,
`leaderboard_entries.week_start`). A single ISO8601 strategy fails on the
third, so the client uses a custom one.

## 🔴 Three problems found in the demo seed

Discovered by running against `demo-alice@dwell.test`:

**1. `prompt_pending` is `true` on both active demo groups.**

```
Demo: Unlocked          active   prompt_pending=true
Demo: Below threshold   active   prompt_pending=true
```

That boolean is what gates the Continue / Pause / End screen. So the two most
demo-critical states would open on the inactivity prompt instead of the feed.
Almost certainly a seeding artifact — `seed-demo.sh` needs to clear it.

**2. One user is in four groups.** The MVP decision (9/19) was one group per
user, and the client assumed that. PostgREST doesn't guarantee row order
without an `ORDER BY`, so `myGroup()` was picking a *different* group between
launches. Fixed client-side (`order("created_at", ascending: false)`, plus a
`DWELL_GROUP` pin for demos), but the seed would be cleaner with one account
per state — otherwise a demo can't reliably land where it means to.

**3. Seeded states drift.** `Demo: Below threshold` now reads day 1 `missed`,
day 2 `open`, with Alice having posted on neither — because the crons kept
running after the seed. **Re-run `seed-demo.sh` shortly before demoing**, or
the states won't be what the script names.

Minor: every seeded group has `timezone: "UTC"` because the seed doesn't send
one. Harmless while frequency is `daily`, but it's exactly the trap rule 1 of
the contract warns about.

**4. The demo credentials no longer work.** As of 2026-09-28,
`demo-alice@dwell.test` with `dwell-demo-2026` returns **"Invalid login
credentials"** from `grant_type=password` — so `DWELL_SELFTEST=1` fails at the
first step, and any demo that leans on the seeded accounts will too. Either
the password changed or the accounts were dropped. **Re-run `seed-demo.sh` and
confirm the password before demoing.**

**Demo accounts:** `demo-alice@dwell.test` / `demo-bob@…` / `demo-carol@…`,
password `dwell-demo-2026` — *currently rejected, see 4 above*.

---

## New: display name is "Friend" for email sign-ups

`handle_new_auth_user` seeds `name = coalesce(raw_user_meta_data->>'name',
'Friend')`. The client now fills that in from the provider wherever it can:
YouVersion's `name` / `given_name`+`family_name` claims, and Google's
`full_name` / `name` user metadata, written over the placeholder once at
sign-in and never over a name the user has since chosen.

**Email/password sign-up has no such source.** The Figma sign-up screen
collects email and password only — no name field — so those users stay
literally called "Friend" on Home and in every member list, with nowhere in
the app to change it.

Three ways out, needs a decision:

1. **Add a name field to the sign-up screen** — a design change for Taylor,
   and the only option that asks the user directly.
2. **Add a profile editor** — belongs with the settings screen, which is part
   of the un-redesigned daily loop.
3. **Derive a provisional name from the email local part** — no new UI, but it
   produces whatever is left of the address, which is often not a name.

Deliberately not guessed in the client: showing someone a name they never
chose is worse than showing the placeholder.
