---
name: hw-dev-test
description: >-
  Stage 09 of the hark-workflow loop (only for projects with a dev environment): merge the PR branch into the dev
  branch with --no-ff, let the dev workflow deploy security rules and a Firebase Hosting preview channel, and test on
  the dev URL. Dev rules must stay backward compatible with main; a push to main reverts the rules, so the dev deploy
  is re-run afterwards; a new channel URL must be added to reCAPTCHA / App Check and Auth domains. Use when the owner
  wants to try a PR (or a chain) on real infrastructure before merge.
---

# hw-dev-test — try it on the dev channel before merge (stage 09)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the main checkout (`repo` row) unless a step names a worktree.
3. Read `.agents/workflow.env`: `DEV_BRANCH` (e.g. `dev`), `DEV_URL`, `DEV_WORKFLOW` (the dev workflow FILE name,
   e.g. `deploy-dev.yml`), `HOSTING_CHANNEL` (e.g. `dev`). Read the project's dev doc (e.g. `docs/DEV-ENVIRONMENT.md`).
   `DEV_WORKFLOW` empty → use the file name of the workflow in `.github/workflows/` that deploys `DEV_BRANCH`.
4. IF `DEV_BRANCH` is empty or the dev workflow does not exist → this project has no dev environment. Set `dev_test`
   = `n/a`, `stage` = `10-owner-approval`. Stop.
5. One action per step, in order.

## Facts you must keep in mind (church-portal setup; check your project's dev doc)

| Fact | Consequence |
|---|---|
| The dev channel is a channel of the SAME Hosting site; the dev workflow deploys `firestore.rules` + indexes to the **live** Firebase project | dev rules ARE the production rules while they are deployed |
| dev uses the **live** Firestore data | a save in the dev admin writes live data → only the owner does it, or you with the owner's quoted OK |
| A push to `main` runs the production deploy, which redeploys **main's** rules | dev's new rules are gone → new fields are denied on the dev URL until the dev workflow runs again |
| A Hosting channel expires N days after its last deploy (30 on church-portal); a deleted / expired channel gets a NEW URL hash | the new domain must be added to Firebase Auth → Authorized domains AND the reCAPTCHA (App Check) key → Domains, or sign-in and App Check fail on dev |
| `dev` is never merged into `main`; no PR from `dev` to `main` | final merges still go PR by PR (`hw-merge`) |

## Step 1 — Owner OK

1. Check STATUS "Owner decisions" for the owner's OK to test this PR on dev (e.g. "جرّبها على dev", "try it on dev").
2. IF missing → ask (owner's language): "Deploy PR #<n> to the dev channel? It deploys its security rules to the live
   project (backward compatible: <yes + why>). Recommended: yes." Set `next_action` = `wait for dev OK`. Stop.
3. Quote the answer with time under "Owner decisions".

## Step 2 — Rules must be backward compatible with main

1. `git fetch origin`
2. `git diff origin/main origin/<branch> -- firestore.rules` (or the project's rules files). Read every change.
3. Check each changed rule against this table:

| Change | Allowed on dev? |
|---|---|
| new function / new key gated separately (e.g. `installPushKeys()` beside `legacyFeatureKeys()`) | yes |
| a write main's app makes is now denied (tightened, renamed or removed legacy key, new required field) | **NO** — fix the rules in the PR first (back to `hw-implement`) |
| new collection with its own rules | yes |
| `allow` widened for a legacy path | only with an ADR and the owner's OK |

4. Check the rules test suite has cases for the **legacy** writes (main's admin saves) and they pass on the PR head
   (row `gate` has `rules` in PASS). IF there are no legacy cases → add them in the PR first.
5. Log: `dev rules check: backward compatible — <one line why>`.

## Step 3 — Merge into dev (no rebase, no force)

1. Create or reuse the dev worktree: `node "<KIT>/scripts/hw.mjs" worktree <DEV_BRANCH> --existing`. Move into the
   printed folder. Then `git fetch origin` and `git merge --ff-only origin/<DEV_BRANCH>` (catch up with what others
   pushed to dev). IF `--ff-only` fails → local dev has commits that are not on origin: STOP and report.
2. `git merge --no-ff origin/main -m "Merge main into <DEV_BRANCH>"` (dev must contain current production).
3. `git merge --no-ff origin/<branch> -m "Merge <branch> (PR #<n>) into <DEV_BRANCH>"`.
   Chain: merge only the TOP branch the owner wants to test (it contains the lower ones).
4. IF conflicts → resolve each file by keeping both sides correctly, `git add <file>` (explicit), `git commit --no-edit`.
   Conflict in rules → the result must still satisfy Step 2.
5. Run the gate in the dev worktree: `node "<KIT>/scripts/hw.mjs" gate --no-build --status <TOPIC>` → `GATE: PASS`.
6. `git push origin <DEV_BRANCH>` (normal push). Copy the new sha7.

## Step 4 — Wait for the dev deploy

1. Run: `node "<KIT>/scripts/hw.mjs" deploy-verify --sha <dev sha7> --workflow <DEV_WORKFLOW> --url <DEV_URL> --status <TOPIC>`
2. Read the last line:

| Line | Do |
|---|---|
| `DEPLOY: VERIFIED <sha7> …` | Step 5 |
| `DEPLOY: NOT VERIFIED` + `deploy run … failure` | `node "<KIT>/scripts/hw.mjs" ci-logs <dev sha7>`; fix like `hw-ci-watch` Step 3 (fix lands in the PR branch, then merge into dev again) |
| `FAIL GET <url> -> 404` | the channel URL changed → Step 5 |

## Step 5 — Check the channel URL

1. Run: `node "<KIT>/scripts/hw.mjs" dev-channel-url --status <TOPIC>` (reads the `::notice::dev channel: <url>` the
   latest successful dev run printed; falls back to the job logs).
2. `DEV-URL: SAME <url> …` → Step 6. `DEV-URL: NOT FOUND` → open the run page, read the URL there, continue.
3. `DEV-URL: CHANGED <url> …` (new hash):
   1. Tell the owner (it is a console change on the live project): "The dev channel got a new URL <url>. Please add
      `<host>` to Firebase Console → Authentication → Settings → Authorized domains, and to the reCAPTCHA key
      `<key name>` → Domains (App Check). Without it, sign-in and App Check fail on dev." Do it yourself ONLY with the
      owner's quoted OK and console access.
   2. After the owner confirms → update `DEV_URL` in `.agents/workflow.env` and the dev doc in the next docs commit.

## Step 6 — Test on dev

1. Smoke: `node "<KIT>/scripts/hw.mjs" deploy-verify --url <DEV_URL> --path / --path /admin` (no workflow wait) → OK lines.
2. Screenshots at 390 px of the changed pages: `node "<KIT>/scripts/hw.mjs" screenshot <DEV_URL>/<path> --width 390`.
   IF `SCREENSHOT: NO-CHROME` → give the owner the printed `/browser …` line.
3. Walk the AC list: for each AC that needs the real backend, write PASS / FAIL + evidence in STATUS.md.
4. Feature switches that must be ON for the test live in live data → the owner turns them on in the dev admin (or you,
   with the owner's quoted OK). Write who changed which switch, and when.
5. Ask the owner to test on the dev URL (their phone, real sign-in). Give the URL and what to look at.
6. `status set <TOPIC> dev_test "<DEPLOY: line> · <k>/<m> AC pass · <DEV_URL>"`.

## Step 7 — After ANY push to main (any merge, by anyone)

The production deploy put main's rules back. Re-run the dev deploy:
1. `node "<KIT>/scripts/hw.mjs" dispatch <DEV_WORKFLOW> --ref <DEV_BRANCH> --status <TOPIC>` → `DISPATCH: … -> run <id>`.
   (`DISPATCH: SENT … no run visible` → use `wait-run latest --workflow <DEV_WORKFLOW> --branch <DEV_BRANCH>`.)
2. `node "<KIT>/scripts/hw.mjs" wait-run <id> --status <TOPIC>` (max 30 min).
3. `RUN: <id> … SUCCESS` → log `dev rules restored, run <id>`, then `dev-channel-url` (Step 5). Anything else →
   `ci-logs <dev sha7>`. (`deploy-verify` only follows push runs, so it does not see this manual run.)

## Next stage

`stage` = `10-owner-approval`, `next_action` = `screenshots + ask the owner for approval`.

## Never

Merge `dev` into `main` · open a PR from `dev` · force-push `dev` · tighten a legacy rule on dev · save in the dev
admin without the owner's OK · run the Seed workflow / seed script against the project.

## Definition of done

- [ ] Owner's dev OK quoted; rules backward-compatibility line logged.
- [ ] `GATE: PASS` on the dev merge commit; `DEPLOY: VERIFIED <dev sha7>` line.
- [ ] Channel URL checked (same, or the owner added the new domain to Auth + reCAPTCHA).
- [ ] `dev_test` row filled with AC results and the URL.
