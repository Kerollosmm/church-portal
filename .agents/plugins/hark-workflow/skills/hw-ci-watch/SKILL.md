---
name: hw-ci-watch
description: >-
  Stage 08 of the hark-workflow loop: wait for every CI check and commit status on the PR head, and when one is red,
  read the failing job's log with hw.mjs ci-logs, reproduce the failure locally, fix the cause with a test, and push.
  Never re-runs a red job blindly (at most one re-run, only for a proven infrastructure failure). Use after every push
  to a PR branch.
---

# hw-ci-watch — green CI on the exact head, or a real fix (stage 08)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run every command from the `worktree` folder. `<n>` = PR number (row `pr`).
3. Check the head: `git rev-parse --short HEAD` equals row `head_sha`, and `git status --short` is empty.
   IF the local head is newer than the pushed one → run `hw-local-gate`, then `git push origin <branch>` first.
4. One action per step, in order.

## Rules

- "Green" means green on the **current head SHA**. A green run on an older commit proves nothing.
- Never re-run a failed job just to see if it passes. A test that fails once and passes on re-run is a flaky test →
  it gets fixed, not ignored.
- At most ONE re-run per head, and only for an infrastructure failure from the table in Step 4.
- Never edit a workflow file to skip, ignore, or `continue-on-error` a failing step to make CI green.

## Step 1 — Wait

1. Run: `node "<KIT>/scripts/hw.mjs" wait-ci <n> --status <TOPIC>`
   (waits up to 45 minutes; checks every 30 s; prints one row per check)
2. Read the last line and the exit code:

| Last line | Do |
|---|---|
| `CI: GREEN on <sha7> (k checks/statuses)` | Step 5 |
| `CI: RED on <sha7> — failed: <names>` | Step 2 |
| `CI: TIMEOUT after …s — still running: <names>` | run `wait-ci` once more. Second timeout → check the Actions page link from `pr-status <n>`; a job stuck "queued" is infra (Step 4) |
| `CI: NONE — no checks or statuses …` | the workflows did not start. Check: is the base branch one the workflow listens to (`on: pull_request: branches:`)? A PR based on a chain branch may get no CI → write it in STATUS.md and tell the owner; run the full local gate as the evidence |

## Step 2 — Read the failing log

1. Run: `node "<KIT>/scripts/hw.mjs" ci-logs <n>`
2. For each failed job it prints: workflow / job, the failed step, the error lines, the last 80 lines, and saves the
   full log in `.work/_logs/ci-<job id>.log`.
3. Write in STATUS.md: `CI red: <job> / <step> — <first real error line>`.
4. Open the saved log if the printed lines do not show the cause (search for `Error`, `FAILED`, `Expected:`).

## Step 3 — Reproduce locally, then fix

1. Run the same thing locally (from the worktree):

| Failed job / step (typical names) | Local command |
|---|---|
| analyze | `node "<KIT>/scripts/hw.mjs" gate --only setup,analyze` |
| test / flutter test | `node "<KIT>/scripts/hw.mjs" gate --only setup,tests` (or the single test file) |
| firestore-rules / rules-test | `node "<KIT>/scripts/hw.mjs" gate --only rules` |
| seed drift / gen_seed | `node "<KIT>/scripts/hw.mjs" gate --only seed` |
| build / fingerprint | `node "<KIT>/scripts/hw.mjs" gate --only setup,build,post-build` |
| preview deploy | read the log: usually a Hosting / auth error → not your code; Step 4 |

2. Decide:

| Local result | Do |
|---|---|
| fails the same way | good: fix the cause (`hw-fix-bug`), test first |
| passes locally but fails in CI | find the difference: versions (Flutter/Node/Java pinned in the workflow?), env vars, time zone (CI runs in UTC!), file order, a missing committed file (`git status` — did you forget to add a new file?), a cache |
| the failure is in a file this PR did not touch | check `main`: does it fail there too (`wait-ci <main sha>` / Actions page)? Yes → not yours; tell the owner, do not fix it in this PR unless asked |

3. Real causes seen on church-portal:
   - **Time zone:** tests that pass in Cairo fail in CI because the runner is UTC. Use the project time helper and set
     the clock / zone in the test; never `DateTime.now()` in logic.
   - **Firestore rules 1000-expression limit:** the rules suite failed only for the largest real `settings/features`
     document. Fix the rules structure (see `hw-local-gate` rules table), not the test.
   - **`CHANNEL` env var:** a workflow `env: CHANNEL: dev` made `subosito/flutter-action` install Flutter's **dev**
     channel (it reads `$CHANNEL`). Name such variables `HOSTING_CHANNEL`, never `CHANNEL`.
   - **Forgotten file:** a new test helper or asset not staged → CI cannot find it. `git status --short` must be empty.
4. Fix → run `hw-local-gate` (full) → `GATE: PASS` → commit with explicit paths → `git push origin <branch>`.
5. Update `head_sha`. Go to Step 1.
6. Same job red twice for the same reason after your fixes → STOP. `blocked` = yes, blocked report.

## Step 4 — Infrastructure failure: one re-run only

A re-run is allowed ONLY when the log shows one of these, and only once per head:

| Log shows | Infra? |
|---|---|
| `HTTP 5xx`, `ECONNRESET`, `ETIMEDOUT`, `Could not resolve host`, pub.dev / npm registry download error | yes |
| runner lost / "The operation was canceled" without a test failure / job queued > 30 min | yes |
| any test failure, analyzer error, rules test failure, build error | **no — never re-run** |

1. Find the run id in the job URL printed by `ci-logs` (`…/actions/runs/<run id>/job/…`).
2. Re-run the failed jobs: `node "<KIT>/scripts/hw.mjs" ci-rerun <run id>`

| Last line | Do |
|---|---|
| `CI-RERUN: STARTED run <id> …` | log `CI re-run (infra: <error line>) run <id>`; then `node "<KIT>/scripts/hw.mjs" wait-run <id>` → Step 1 |
| `CI-RERUN: REFUSED — … already attempt 2` | it was re-run before: the failure is real. Step 2. |
| `CI-RERUN: NOT NEEDED` | the run is green now. Step 1. |

3. Red again after the re-run → it is not infra. Go to Step 2. Never a second re-run (the command refuses it).

## Step 5 — Green: record it

1. `node "<KIT>/scripts/hw.mjs" status set <TOPIC> ci "<CI: GREEN line>"`
2. Find the preview URL (when the project deploys PR previews): in `pr-status <n>` bot comments, or
   `node "<KIT>/scripts/hw.mjs" api GET "repos/{repo}/issues/<n>/comments?per_page=100"` → the comment from the deploy
   bot / github-actions with `web.app` (Firebase) or the preview host. Copy the exact URL (it has a random hash).
3. Update the PR body section "CI · Preview" with the green line and the preview URL (`pr-edit <n> --body-file …`).
4. Next stage:

| Came from | Next |
|---|---|
| `06-open-pr` (first CI on the PR) | `07-review-loop` |
| `07-review-loop` (fix push) | back to `07-review-loop` Step 7 (reply) or Step 8 |
| review loop finished | `09-dev-test` if the owner wants the dev environment; else `10-owner-approval` |

## Definition of done

- [ ] `CI: GREEN on <sha7>` in row `ci`, and `<sha7>` equals row `head_sha` and the PR head.
- [ ] Every red run on the way has a log line: job, error line, cause, fixing sha7 (or the one infra re-run).
- [ ] Preview URL in STATUS.md and the PR body (when the project has previews).
