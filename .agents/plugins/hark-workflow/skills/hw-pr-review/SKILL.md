---
name: hw-pr-review
description: >-
  Reviews someone else's pull request end to end: check it out in its own worktree (read-only), run the local gate,
  read CI and failing logs, judge every open bot comment, compare the code with its plan, check the size budget and
  the PR body facts, and write a verdict with the pr-review-report template. Use when the owner says "review PR #n"
  for a PR you did not write. Posts nothing on GitHub and pushes nothing unless the owner asks.
---

# hw-pr-review — review a PR you did not write

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Topic = `pr<n>-review`. IF `.work/pr<n>-review/STATUS.md` is missing → run
   `node "<KIT>/scripts/hw.mjs" status init pr<n>-review --goal "review PR #<n>"`. Read it.
3. Run commands from the main checkout unless a step names a worktree.
4. One action per step, in order.

## Rules

- Review only. Do not commit, push, comment, approve, request changes or merge on GitHub — unless the owner asks in
  this conversation (quote it). A "fix run" on their PR is a different task: the owner must ask for it.
- Every finding has proof: a test output, a command line, a `file:line` quote. No proof → not a finding.
- Severity: **blocker** = breaks live / loses data / security / CI red · **major** = wrong behaviour users see, plan
  item missing, wrong docs facts · **minor** = style, naming, small cleanup.

## Step 1 — Read the PR

1. Run: `node "<KIT>/scripts/hw.mjs" pr-status <n>`. Copy the `PR-STATUS:` line.
2. Write in STATUS.md: title, author, head branch + sha7, base branch + sha7, draft or not, review time with zone.
3. Read the PR body. Find the plan link (`Plan:` line) and the claims (size, tests, field names, defaults).

## Step 2 — Check out (read-only worktrees)

1. Head (same repo and forks): `node "<KIT>/scripts/hw.mjs" pr-checkout <n>` → a detached, read-only worktree.
2. The last line `PR-CHECKOUT: #<n> <sha7> -> <folder> (… = PR head)` proves the sha7 equals the PR head (exit 1 and
   "it moved" → run it again). Write the folder in STATUS row `worktree`.
3. Base (for size): `git worktree add --detach .work/wt/pr<n>-base origin/<base branch>`.

## Step 3 — Local checks

1. In the head worktree: `node "<KIT>/scripts/hw.mjs" gate --keep-going --status pr<n>-review`
   (`--keep-going` runs every step even after a failure, so you see all problems.) Copy the `GATE:` line.
2. For each FAIL step: open `.work/_logs/gate-<step>.log`, copy the first real error line and the test names.
3. Size (when `SIZE_FILE` is set):
   1. In the base worktree: `node "<KIT>/scripts/hw.mjs" gate --only setup,build` then
      `node "<KIT>/scripts/hw.mjs" size` → copy raw and gzip bytes.
   2. In the head worktree: `node "<KIT>/scripts/hw.mjs" size --baseline-raw <base raw> --baseline-gz <base gz> --budget-gz <plan budget bytes>`
   3. Compare with the PR body's claim and the plan budget (PR #51 claimed +67 KB gz against a +20 KB budget →
      major; fixed later with deferred imports to +18.6 KB).

## Step 4 — CI and failing logs

1. From `pr-status`: list every check with its state.
2. IF any is red → `node "<KIT>/scripts/hw.mjs" ci-logs <n>`; copy the failing job, step and error line.
3. Reproduce the red job locally (`hw-ci-watch` Step 3 table). Explain the cause in one line.
   Example (PR #51): `firestore-rules` 126 pass / 4 fail → the `settings/features` rule hit Firestore's 1000-expression
   limit for the largest real documents → real admin saves would be denied on live → **blocker**.

## Step 5 — Bot comments

1. `node "<KIT>/scripts/hw.mjs" threads <n>` → every open thread. Also read review bodies in `pr-status` (outside-diff
   and nitpick comments).
2. For each open finding: open the code, decide **real** or **not real**, with proof. Real ones go into the report
   with severity. Typical real ones: time shown in UTC instead of the project zone; recurring items expiring after the
   first occurrence; a failed write reported as success; settings lost after an expiry.

## Step 6 — Plan vs code

1. Open the plan file. List every sub-feature / step for this PR.
2. For each: `grep_search` the code. Mark **yes / partial / no / extra** with `file:line`.
3. "extra" = code the plan says is NOT in this PR (e.g. quiet-hours UI added though the plan defers it) → major
   (scope creep) unless the PR body explains it as an out-of-plan fix.
4. Check the project rules too (configurable from admin, both languages, switch off hides everywhere, images
   optional, time helper, palette).

## Step 7 — PR body accuracy

Compare every fact in the body with the code: field names, defaults, list values, admin labels, test counts,
screenshots present, owner approval present. Each mismatch is a finding (PR #51: wrong field names
`installBannerEnabled`/`pushEnabled`, "Later 7 / Close 30" vs code 3/30, admin hint says 14 but code 30).

## Step 8 — Write the verdict

1. Copy `<KIT>/resources/templates/pr-review-report.md` to `.work/pr<n>-review/review.md`. Fill every section.
2. Verdict rule:

| Findings | Verdict |
|---|---|
| any blocker (CI red, live break, data loss, security) | **REQUEST CHANGES** |
| majors only | **REQUEST CHANGES** (or COMMENT when the owner said majors may follow) |
| minors only, all checks green | **APPROVE** (with the minor list) |

3. "What must happen before merge": numbered, concrete (e.g. "rules suite 130/130 green", "size ≤ +20 KB gz",
   "390 px screenshots + owner approval").
4. `status set pr<n>-review stage done`; log `review written: <verdict>, <b> blockers, <m> majors, <k> minors`.
5. Send the owner a short summary (owner's language): verdict, blockers, top majors, the file path. Ask: "Post this
   review on the PR? / Start a fix run?" with your recommendation.

## Step 9 — Clean up

`git worktree remove .work/wt/pr<n>-base` (keep the head worktree if a fix run may follow).

## Definition of done

- [ ] `GATE:` line from the head worktree; size numbers for base and head (when configured).
- [ ] CI state per check; every red job has a cause line.
- [ ] Every open bot finding judged real / not real with proof.
- [ ] Plan table and PR-body accuracy list filled.
- [ ] `review.md` with verdict and "before merge" list; owner informed; nothing posted or pushed without the owner.
