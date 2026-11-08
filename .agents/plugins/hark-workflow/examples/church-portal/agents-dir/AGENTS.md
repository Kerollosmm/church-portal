# church-portal — project rules for every agent (overlay of the hark-workflow kit)

Installed as `.agents/AGENTS.md` (always on). These rules come from the owner (Kerollos Melad) and beat the kit
defaults. The repo's own `AGENTS.md` (golden rules, commands) and `docs/memory-bank/` still apply: read them first.
Entry point: skill `hw-start` (or the `parent-agent`). Settings: `.agents/workflow.env`.

## 1. Talking to the owner

1. Reply to the owner **in Arabic** (simple Arabic). Code, paths, commands, field names stay in English.
2. **Absolute dates and times only**, zone **Africa/Cairo**: «السبت ٧ نوفمبر ٢٠٢٦، ١٠:١٩ م (القاهرة)» /
   `2026-11-07 22:19 Africa/Cairo`. Never "today", "tomorrow", "in 2 hours" without the date.
3. **Files go to the owner as Google Drive links only** (reports, screenshots, APKs, exports). Never paste a local
   path, a sandbox path or an attachment the owner cannot open.
4. At most 3 numbered questions, each with your recommendation.

## 2. Live data and Firebase (Spark plan)

1. **No live data writes without the owner's explicit approval, one item at a time** (one document, one setting,
   one admin save, one workflow run). Quote the approval with date + time in STATUS.md before you act. An approval
   for one item never covers the next one.
2. Never run `tool/seed_firestore.js` for real (only `--dry-run`), the **Seed Firestore** workflow, the deploy or
   commemoration workflows by hand, `tool/publish_hosting_file.js`, `firebase deploy`, `hosting:channel:deploy` or
   any `firebase firestore:*` command. The production deploy happens only through a merge to `main`.
3. Pushing to `dev` deploys **rules + indexes to the LIVE project** (project-wide). It needs the owner's OK
   (skill `hw-dev-test`) and dev rules must stay backward compatible with main's app.
4. **Spark plan**: no Cloud Functions, no Cloud Storage; **no new listeners, no polling, no new collections**.
   Settings are top-level keys of `settings/features`. **Prefer static JSON on Hosting** for public data
   (like `/data/today.json`). Every ADR states its Firestore read / write / listener cost.
5. Tests use the emulator (`demo-*` project id) or fakes. QA simulations never touch live (`hw-qa-sim`).

## 3. UI and admin

1. **Everything configurable in `/admin`**: a new label, switch, limit or text gets an admin field (model +
   `lib/ui/admin/admin_schema.dart` + `firestore.rules` + `tool/gen_seed.py` + tests). Admin stays web-only.
2. **Palette roles only** (`context.pal.*`); the test «no hard-coded colour in lib/ui» must pass. **No violet /
   purple anywhere.** The home hero's look and motion stay as they are.
3. Arabic-first RTL + English; strings in `lib/core/l10n.dart` (`[ar, en]`); 48 dp targets; 320 px at 200 % text
   without overflow. Owner screenshots at **390 px** (Arabic) and 1280 px (English).
4. Never invent church content (times, names, phones, doctors, photos): unverified = `sample: true`.

## 4. Git, PRs and the chain

1. Branch per PR, **one worktree per PR**, one agent per worktree. Never push or commit on `main`; never force-push;
   never rebase pushed work (catch up with `git merge --no-ff origin/<base>`).
2. Stage **explicit pathspecs** only. **Never commit `tool/rules_test/node_modules`, `*-debug.log`**, `build/`,
   keys, `.jks`, service-account JSON (gate step `extra-2` fails if one is tracked).
3. PRs open as **drafts**. A stacked chain (A → B → C → D → E, each based on the previous branch): **no merges until
   the whole chain is approved by the owner; then merge bottom-up** (skill `hw-merge`), retargeting each PR to `main`
   and merging `origin/main` into it first.
4. Reviews: `@coderabbitai review` + `@sentry review`; **max 2 bot rounds per PR**; reply on every thread (fix
   commit or reason). CodeRabbit rate limit → `hw.mjs bots-wait <n>`; never spam requests.
5. Every PR carries in the **same PR**: tests, memory-bank updates (03/04/05/06/07/08/11 as relevant), the Arabic
   `documentation/` file (+ `README.md` index, `operations.md` when operational), `documentation/en/`, and its
   **ADR** in `docs/memory-bank/10-decisions-and-history.md` (+ timeline row).
6. **ADR numbers**: run `node "<KIT>/scripts/hw.mjs" adr-next` before writing one. Phase 2 has claimed
   **ADR-056 … ADR-061** (056 plans, 057 A, 058 B, 059 C, 060 D, 061 E): never reuse them; new work takes the
   number `adr-next` prints.
7. Budgets: `main.dart.js` **+20 KB gzip per PR** (Phase 2 total ≤ +60 KB) vs `SIZE_BASELINE_*`; PageSpeed mobile
   not below **61** (baselines mobile 61/100/100/100, desktop 60/100/100/100, median of 3).
8. Anything that loops twice (red CI job, review ping-pong, flaky test) → stop and report.

## 5. Phase 2 chain (state on 7 Nov 2026 — check STATUS.md / `docs/plans/phase2/HANDOFF.md` for the current one)

| PR | Branch | Base | ADR |
|---|---|---|---|
| 0 plans (#50) | `docs/phase2-plans` | `main` | 056 |
| A install banner + prefs (#51) | `feat/p2a-install-prefs` | `docs/phase2-plans` | 057 |
| B Android APK + local notifications (#52) | `feat/p2b-android-local-notifications` | `feat/p2a-install-prefs` | 058 |
| C admin notification manager + FCM + deep links | `feat/p2c-notification-manager` | B | 059 |
| D web push + PWA + iPhone | `feat/p2d-web-push` | C | 060 |
| E responsive + size audit | `fix/p2e-responsive-size` | D | 061 |
