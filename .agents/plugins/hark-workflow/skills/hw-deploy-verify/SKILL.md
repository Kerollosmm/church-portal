---
name: hw-deploy-verify
description: >-
  Stage 12 of the hark-workflow loop: after a merge to main, prove the release is live and healthy — CI and the deploy
  workflow green on the merge commit, live pages return 200, the new strings are in the live bundle (and removed ones
  are gone), a read-only smoke test of the changed features, PageSpeed vs the baseline, and no new Sentry issues.
  Use right after hw-merge, or when the owner asks "is it live?".
---

# hw-deploy-verify — is it really live and healthy? (stage 12)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the main checkout. `<sha>` = the merge sha7 (row `merge_sha`;
   for a chain, the LAST one — earlier ones were checked in `hw-merge` 2.5).
3. Read `.agents/workflow.env`: `CI_WORKFLOW`, `DEPLOY_WORKFLOW`, `LIVE_URL`, `LIVE_PATHS`, `BUNDLE_PATH`,
   `PSI_BASELINE_MOBILE`, `PSI_BASELINE_DESKTOP`.
4. One action per step, in order. Everything here is **read-only** on live. Never "fix" live by hand.

## Step 1 — CI on main

1. Run: `node "<KIT>/scripts/hw.mjs" wait-ci <sha> --status <TOPIC>`
2. `CI: GREEN on <sha>` → Step 2. `CI: RED …` → Step 7 (incident). `CI: NONE` → note it (some repos run CI on PRs
   only) and continue.

## Step 2 — Deploy run + live pages + bundle strings

1. Pick 1–3 strings that ONLY the new code has (a new UI label from the l10n table, a new route) → `--expect`.
   Pick strings this PR removed → `--absent`. Copy them exactly from the code (Arabic too).
2. Run:
   `node "<KIT>/scripts/hw.mjs" deploy-verify --sha <sha> --expect "<new string>" --absent "<removed string>" --status <TOPIC>`
   (waits for the `DEPLOY_WORKFLOW` push run, prints each job, GETs every `LIVE_PATHS` path, downloads the bundle
   and its deferred `main.dart.js_*.part.js` parts and searches them.)
3. Read the last line:

| Line | Do |
|---|---|
| `DEPLOY: VERIFIED <sha> — …` | `status set <TOPIC> deploy "<line>"`; Step 3 |
| `deploy run … failure` | `node "<KIT>/scripts/hw.mjs" ci-logs <sha>`; Step 7 |
| `FAIL bundle has «…» (0)` | the CDN may still serve the old build: wait 5 min, run again once. Still 0 → is the string in a deferred part that is not referenced? Check the build locally (`grep` in `build/web`). Then Step 7 |
| `FAIL GET … -> 404/500` | Step 7 |

## Step 3 — Live smoke test (read-only)

1. For each AC of this release that is visible without signing in: open the live page and check it.
   Screenshot at 390 px: `node "<KIT>/scripts/hw.mjs" screenshot "<LIVE_URL>/<path>" --width 390 --out .work/<TOPIC>/png/live-<page>-390.png`.
   Open each PNG and look at it.
2. Features behind a switch that is OFF on live: check they are hidden everywhere (the switch-off promise).
   Do NOT turn a switch on to test it — that is a live write; the owner decides.
3. Admin-only checks: ask the owner to try them (you never save in the live admin without the owner's OK).
4. Times: check one displayed time against the project zone (e.g. Africa/Cairo); a UTC time on screen is a bug.
5. Write a table in STATUS.md: `| AC | live result | evidence (png / string) |`.

## Step 4 — PageSpeed vs the baseline

1. Run: `node "<KIT>/scripts/hw.mjs" psi --status <TOPIC>` (median of 3 runs, mobile + desktop).
2. Decide:

| Line | Do |
|---|---|
| `PSI: OK — …` | `status set <TOPIC> psi "<line>"`; Step 5 |
| `PSI: BELOW BASELINE — …` by ≤ 3 points on performance only | run once more (PSI varies). Still below → record it and tell the owner as a note |
| below by > 3 points, or accessibility / best-practices / SEO dropped | regression: compare the SIZE line of this PR, find the heavy change (new eager import, big image, font). Write a follow-up PR proposal for the owner. Do not hot-fix on main |
| `ERROR: PSI HTTP 429` (quota) | write `PSI: not measured (quota) at <time zone>`; tell the owner they can run https://pagespeed.web.dev/ ; continue |

3. When the owner accepts new numbers as the baseline → `PSI_BASELINE_*` in `.agents/workflow.env` changes in the next
   docs PR (never on main directly).

## Step 5 — Sentry: no new issues

1. Wait at least 30 minutes after the deploy (real visitors need time to hit the new code). Meanwhile do Step 6.
2. Run: `node "<KIT>/scripts/hw.mjs" sentry-issues --since <deploy time, ISO with zone, e.g. 2026-11-07T18:05+02:00> --env production --status <TOPIC>`
   (needs `SENTRY_ORG` / `SENTRY_PROJECT` in `.agents/workflow.env` and a `SENTRY_TOKEN` in the environment; the
   token is never written anywhere.)
3. Decide from the last line:

| Seen | Do |
|---|---|
| `SENTRY: NOT CHECKED — …` | ask the owner to look (Sentry → Issues → env `production` → `is:unresolved firstSeen:-1h`), or log `Sentry: not checked (<reason>)`. Never claim "no new issues" without a list. |
| `SENTRY: 0 new issues since …` | log the line |
| a new issue in code this release touched | Step 7 (incident) — open a fix PR with a regression test (`hw-fix-bug`) |
| a new issue unrelated to this release | note it for the owner as a follow-up |

## Step 6 — Dev environment after the production deploy

IF the project has a dev environment: main's rules replaced dev's. Re-run the dev deploy (`hw-dev-test` Step 7:
`dispatch` + `wait-run`) when dev still holds unmerged work. Log the `RUN:` line.

## Step 7 — Incident (anything red on live)

1. Do not panic-fix on main. Do not deploy by hand (`firebase deploy` is blocked).
2. Write in STATUS.md: what is broken, since when (zone), evidence line.
3. Tell the owner at once (blocked report shape, owner's language) with two options and your recommendation:
   a) revert PR: new worktree `fix/revert-<topic>` from main, `git revert --no-edit <squash sha>` (a squash commit has
      one parent, so no `-m`), gate → push → draft PR → CI → owner says merge; b) forward fix PR with a regression test. Admin switch OFF is option c) when the
      feature has one (the owner flips it).
4. Set `blocked` = yes until the owner decides.

## Next stage

`stage` = `13-docs-final`, `next_action` = `after-merge docs check`.

## Definition of done

- [ ] `CI: GREEN on <sha>` (or `CI: NONE` noted) and `DEPLOY: VERIFIED <sha>` in STATUS.md.
- [ ] Live smoke table with evidence for every visible AC; switch-off features hidden.
- [ ] `PSI:` line (or "not measured (quota)") in row `psi`.
- [ ] Sentry line based on a list you actually saw (or "not checked" + reason).
