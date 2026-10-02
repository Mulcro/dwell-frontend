# Working agreements

## Git workflow

**Never commit directly to `main`.** Every change goes:

1. Branch off `main` — `feature/<short-name>` or `fix/<short-name>`
2. Commit and push
3. Open a PR with `gh pr create`
4. **Mulero verifies it works on a device, then merges.** Don't merge your own PRs.

Push as you go rather than letting work pile up — the codebase is large enough that a
single enormous diff is no longer reviewable.

## Documentation lives in Notion, not in the repo

Specs, backend requests, design gaps, test cases and build plans belong in the
[GLOO Hackathon 2026](https://app.notion.com/p/39dd36984c6e80d19e4feca1f30095a6) Notion
space. Local `.md` files drift out of date the moment Notion is updated, and nobody
reads two sources.

`README.md` is the exception — it describes how to build and run the app.

## Build and deploy

Simulators and the physical iPhone both get every build:

```
xcodebuild -scheme Dwell -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -configuration Debug build
xcodebuild -scheme Dwell -configuration Debug -destination "platform=iOS,id=00008140-001A11DC1E28401C" -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-001A11DC1E28401C <path to Dwell.app>
```

Free signing expires device builds after 7 days.

## Backend gaps

When the design needs data the backend doesn't have: **build the UI against what exists,
degrade honestly when it's absent, and write the request in Notion.** Don't invent data
and don't leave a visibly broken screen. Prefer a capability probe so the feature lights
up when the backend lands, with no client release.

## Secrets

`Config/Secrets.xcconfig` and `.env` are gitignored and must stay that way. The Supabase
key in the app is the **publishable** key — never an `sb_secret_…` key, which bypasses RLS.
