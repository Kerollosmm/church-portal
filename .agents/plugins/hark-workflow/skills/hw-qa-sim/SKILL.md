---
name: hw-qa-sim
description: >-
  Runs a QA / simulation phase on a local build against the Firebase emulator ONLY (never the live project): a frozen
  clock and fixture data, every owner write going through the real security rules, a PASS / PARTIAL / FAIL (or N/A)
  result with evidence for every checklist item, and one report per phase from qa-phase-report.md. No code fixes
  during QA; findings become fix PRs. Use when the owner asks to simulate, test phases, or "try a season / day".
---

# hw-qa-sim — emulator-only QA, one report per phase

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Topic = `qa-<name>` (e.g. `qa-holy-week`). IF there is no STATUS → `node "<KIT>/scripts/hw.mjs" status init qa-<name> --goal "<owner's words>"`.
3. Get the phase list and the checklist of each phase from the owner's request or the plan (`docs/plans/…`). Copy
   them into STATUS.md. Unclear item → ask the owner before starting (max 3 questions).
4. One action per step, in order. ONE phase per run.

## Hard rules

- **Never touch live.** No live Firestore reads or writes from the app under test, no live admin, no seed scripts, no
  deploys, no Seed workflow. The Firebase project id MUST start with `demo-` (a demo project can never reach a real
  backend). An item that can only be checked on live → **N/A (needs live)**, listed for `hw-deploy-verify`.
- No code fixes, no commits, no pushes, no PRs during QA. You report; fixes come after, through the normal loop.
- Every owner write in the scenario goes through the real `firestore.rules` on the emulator (log ALLOW/DENY).
- Evidence for every row: a test name + log file, a screenshot you looked at, or a data file. "Looks fine" is not
  evidence.

## Step 1 — Fresh, clean environment

1. `git fetch origin`
2. Code under test (default `origin/main`; or the PR branch the owner named):
   `git worktree add --detach .work/wt/qa-<name>-<phase> origin/<branch>`. Write the sha7 in STATUS.md.
3. Move into it. Run the project setup (`flutter pub get`).
4. Pick private ports (avoid clashes with other runs), e.g. Firestore emulator `18080`. Set for this shell:
   `FIRESTORE_EMULATOR_HOST=127.0.0.1:18080` and `NO_PROXY=127.0.0.1,localhost`.
5. Start the emulator with a demo project:
   `npx firebase-tools emulators:start --only firestore --project demo-qa-<name> --config <firebase.json>`
   (or the project's rules-test script). Wait for "All emulators ready".
6. Check: the emulator UI / `curl http://127.0.0.1:18080/` answers. IF the project id does not start with `demo-` →
   STOP.

## Step 2 — Data and clock

1. Load the fixture data into the emulator (seed JSON / fixture file named in the plan). Never the live export.
2. Apply the owner's scenario writes (e.g. a season window, parallel services, a preset) **through the rules** with an
   authenticated admin test user. Save the ALLOW/DENY lines to `.work/qa-<name>/<phase>/data/rules_log.txt`.
   An unexpected DENY is a finding.
3. Freeze the clock in the test harness (e.g. a fixed `now` injected into the time helper, `--dart-define`, a test
   clock). Write the exact frozen time WITH zone (e.g. `Thu 29 Apr 2027 18:30 Africa/Cairo`). Never change a live
   setting to move time.
4. Save a snapshot of the emulator state after setup: `.work/qa-<name>/<phase>/data/state_frozen.json`.

## Step 3 — Run the checks

1. Sim tests (widget / integration tests that drive the real app at 390 px) may be copied into the worktree's `test/`
   while running. They are removed at the end (the worktree must be clean).
2. For each checklist item, in order:
   1. Run the check (test, screenshot, data query on the emulator).
   2. Screenshots at 390 px (owner's language) — and 1280 px / 320 px when the item is about layout. Save under
      `.work/qa-<name>/<phase>/png/`. Open each PNG and LOOK: overflow, clipped text, banned colours, RTL/LTR, times in
      the project zone (a UTC time on screen is a FAIL).
   3. Write the row: expected · seen (quote Arabic UI text exactly «…») · result · evidence path.
3. Result rule:

| Result | When |
|---|---|
| **PASS** | everything expected is seen, evidence saved |
| **PARTIAL** | the main behaviour works but a sub-point fails or is missing (e.g. right text, wrong digits «٢ أيام» vs «يومين») |
| **FAIL** | the expected behaviour is not there, wrong, crashes, overflows, or writes something it must not |
| **N/A** | the scenario cannot produce it (say why), or it needs live (say "needs live") |

4. Regression sweep at the end: no overflow, no exception in the logs, no banned colour pixels, no sample markers on
   public pages. Each is a row.
5. Zero-write checks: when an item says "no writes" (e.g. auto-revert), compare emulator `updateTime`s before/after.

## Step 4 — Report (one per phase)

1. Copy `<KIT>/resources/templates/qa-phase-report.md` to `.work/qa-<name>/<phase>/report.md`.
2. Fill: environment (emulator, port, demo project id, build sha7, data file), scenario, how clock and data were set,
   the matrix (all rows, PASS/PARTIAL/FAIL/N/A), findings (each with repro steps and suspected `file:line`).
3. Score line at the top: `<p> PASS, <q> PARTIAL, <f> FAIL, <x> N/A of <total>`.
4. Verdict line: `PHASE <P#> PASS` (only PASS/N/A) · `PHASE <P#> PARTIAL (<q>)` · `PHASE <P#> FAIL (<f> findings)`.
5. Log the score and verdict in STATUS.md.

## Step 5 — Clean up

1. Stop the emulator (Ctrl+C or kill its Java process). Check the port is free.
2. Remove copied sim tests; `git status --short` in the worktree must be empty.
3. `git worktree remove .work/wt/qa-<name>-<phase>` (from the main checkout). The main checkout is untouched.

## Step 6 — Hand to the owner

1. Send the owner (owner's language): score, verdict, the top findings, the report path.
2. Ask: "Start fix PRs for findings <list>? Next phase <P#+1> after you review?" — recommended answer included.
3. `next_action` = `wait for the owner to review phase <P#>`. Stop. The next phase starts only after the owner says so.
4. Findings the owner accepts → each one a fix PR through `hw-start` (bug → `hw-fix-bug` with a regression test), or an
   open task.

## Definition of done

- [ ] Demo project id (`demo-…`) and emulator port in the report; zero live writes stated.
- [ ] Every checklist item has a row with PASS / PARTIAL / FAIL / N/A and evidence; screenshots looked at.
- [ ] Score + verdict line in the report and in STATUS.md.
- [ ] Emulator stopped, worktree clean and removed.
- [ ] Owner informed; next phase waits for the owner.
