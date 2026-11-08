---
name: hw-review-loop
description: >-
  Stage 07 of the hark-workflow loop: get AI reviews (CodeRabbit + Sentry) on the PR head, triage every finding as
  valid or invalid, fix the valid ones with tests, reply on EVERY thread (fixed in <sha> or the reason), resolve, and
  stop after at most 2 rounds. Handles the CodeRabbit rate limit by waiting the time it states. Use after CI is green
  on a new PR head, or when bot comments arrive.
---

# hw-review-loop — bot reviews, triage, fix, reply (stage 07, max 2 rounds)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run every command from the `worktree` folder. `<n>` = the PR number (row `pr`).
3. Read row `review_round`. IF it is `2` and all threads are answered → skip to Step 8.
4. One action per step, in order.

## Rules

- **Max 2 rounds** (`REVIEW_MAX_ROUNDS`). A round = request → wait → triage → fix → push → reply. Round 3 only when
  the owner asks for it in this conversation (quote it).
- **Every thread gets a reply.** Fixed → "Fixed in `<sha7>`: <one line> (test: `<name>`)". Not fixed → the reason.
  Never leave a thread silent. Never resolve without a reply.
- **Every fix has a test** that fails without the fix (skill `hw-fix-bug`). A fix without a test is not a fix.
- Do not trust a bot blindly. Bots are often right about bugs and often wrong about the project's own rules.
- Bot requests and replies on your own PR are allowed. Nothing else is posted without the owner.

## Step 1 — Which bots are active (once per repo)

1. Run: `node "<KIT>/scripts/hw.mjs" bots`
2. Read the last line `BOTS: active …`. Use only the active bots. IF `active none` → log "no review bots on this
   repo", set `review_round` = `0 (no bots)`, go to Step 8.

## Step 2 — Request the round

1. Check CI is green on the head (row `ci` says `CI: GREEN on <head_sha>`). IF not → run `hw-ci-watch` first.
   Reviewing a red head wastes a round.
2. Add 1 to `review_round`: `node "<KIT>/scripts/hw.mjs" status set <TOPIC> review_round "<r>"`
3. Run: `node "<KIT>/scripts/hw.mjs" review-request <n>`
   (posts `@coderabbitai review` and `@sentry review`; the PR may be a draft — that is fine.)
4. Copy the `REVIEW-REQUEST: …` line into the log.

## Step 3 — Wait for the reviews

1. Wait 5 minutes. Then run: `node "<KIT>/scripts/hw.mjs" pr-status <n>`
2. Read "latest bot comments" and "reviews". Decide:

| You see | Do |
|---|---|
| a CodeRabbit review / comments newer than your request, AND a Sentry comment ("no issues" or findings) | go to Step 4 |
| one bot answered, the other not yet | wait 5 more minutes, check again (max `REVIEW_STALL_MINUTES` = 10 min total per bot) |
| a bot comment marked `RATE-LIMITED` | Step 3b |
| nothing after 10 minutes | post the request once more for the silent bot only: `review-request <n> --bots "<bot>"`. Still nothing after 10 more minutes → log "<bot> did not answer" and continue with what you have |
| CodeRabbit says "Review skipped" / "draft" | post `@coderabbitai review` once more (`review-request <n> --bots coderabbitai`); it reviews on explicit request |

### Step 3b — CodeRabbit rate limit (wait the time it gives, never spam)

1. Run: `node "<KIT>/scripts/hw.mjs" bots-wait <n>` (reads the newest CodeRabbit limit notice in the PR
   conversation AND in review-thread replies; ready time = notice time + the wait it states + 1 min; no time stated →
   60 min).
2. Read the last line:

| Last line | Do |
|---|---|
| `BOTS-WAIT: WAIT until <time zone> (<m> min) …` | log `CodeRabbit rate-limited; retry at <time zone>` (copy it). Continue with 3. |
| `BOTS-WAIT: READY …` | go to 5 now. |
| `BOTS-WAIT: NONE …` | not rate-limited (any more). Back to Step 3. |

   A line `chat limit: …` means thread replies that mention the bot used the hourly chat quota (see the note below).
3. Do not post anything that mentions `@coderabbitai` before the ready time. Each extra request restarts the limit.
4. Use the wait: handle Sentry's findings (Step 4–6) meanwhile.
5. At the ready time → `review-request <n> --bots coderabbitai` once. Go back to Step 3.
6. Rate-limited twice in this round → STOP waiting. Log it, continue with Sentry's findings, and tell the owner in the
   final report ("CodeRabbit rate-limited at <time>").

Note: the CodeRabbit **chat** limit is hourly too. Replies that start a conversation with the bot (questions,
`@coderabbitai` mentions) use it; on PR #51 it stopped answering after about 24 acknowledgements. Write your thread
replies as plain statements, without `@coderabbitai`, unless you need the bot to re-check.

## Step 4 — Collect and triage every finding

1. Run: `node "<KIT>/scripts/hw.mjs" threads <n>` → every open thread with `thread <id> · comment <id>`.
2. Also read the review bodies in `pr-status <n>`: CodeRabbit puts **"outside diff range"** and **nitpick** comments
   in the review text, not in threads. They need an answer too (Step 7, PR comment).
3. Make a table in STATUS.md, one row per finding:
   `| # | bot | file:line | comment id | thread id | summary | verdict | action |`
4. Fill `verdict` with this table:

| The finding … | Verdict |
|---|---|
| shows a real bug (wrong value, crash, data loss, security hole, wrong time zone, a write the rules deny) | **valid** |
| points to a missing test for code you changed | **valid** |
| is right but outside this PR's topic and big | **valid-later** → open task + follow-up line for the owner |
| contradicts a project rule (e.g. "hard-code this" when the rule says "configurable from admin") | **invalid** — cite the rule |
| is about code this PR did not touch and is not broken | **invalid** — "out of scope, unchanged by this PR" |
| is wrong about the facts (you checked the code / a test proves the opposite) | **invalid** — give the proof |
| is a style nit with no effect | **invalid** or tiny fix (your choice; still reply) |

5. Real examples that were **valid** on church-portal: reminder time shown in UTC instead of Africa/Cairo (display
   through the project's time helper, `CairoTime`); recurring reminders deleted after the first occurrence; storage
   write failure reported as success; settings dropped after a preset expired; a default lead time in the past saved.

## Step 5 — Fix the valid ones

For each valid finding, one at a time:
1. Write the failing test first (`hw-fix-bug` step 2). Name it after the finding.
2. Fix the cause. Run the test → green.
3. `git add <explicit paths>` and `git commit -m "fix(<area>): <finding summary> (review)"`.
4. Write the sha7 in the table row.

Then:
5. Run `hw-local-gate` (full gate). Must print `GATE: PASS`.
6. IF this PR is in a chain → after pushing, propagate to the higher branches (`hw-worktree` Step 3).
7. Push: `git push origin <branch>`. Update `head_sha`.

## Step 6 — Wait for CI on the new head

Run `hw-ci-watch` (Steps 1–3 only) on the new head. Red → fix first, then reply.

## Step 7 — Reply on every thread, then resolve

For each table row:
1. Write the reply into a file `.work/<TOPIC>/reply-<comment id>.md`:
   - valid: `Fixed in <sha7>: <what changed>. Test: <test name>.`
   - valid-later: `Agreed, out of this PR's scope. Tracked as open task "<title>" in <OPEN_TASKS_FILE>.`
   - invalid: `Not changed: <reason>. <proof: rule / test / file:line>.`
2. Post it: `node "<KIT>/scripts/hw.mjs" reply <n> <comment id> --body-file .work/<TOPIC>/reply-<comment id>.md`
3. Copy the `REPLY: <id> <url>` into the row.
4. Resolve fixed and valid-later threads: `node "<KIT>/scripts/hw.mjs" resolve <thread id>`. Leave an invalid thread
   open when the bot may answer; resolve it after the bot agrees or after the round ends.
5. Findings from review bodies (outside diff / nitpicks): one PR comment that answers all of them, by number:
   `node "<KIT>/scripts/hw.mjs" comment <n> --body-file .work/<TOPIC>/review-body-replies.md`
6. Check: `node "<KIT>/scripts/hw.mjs" threads <n>` → `THREADS: 0 open` (or only invalid threads you replied to).
7. Log: `round <r>: <k> findings — <x> fixed (<sha7s>), <y> invalid (replied), <z> later; THREADS: <line>`.

## Step 8 — Next round or stop

| Situation | Do |
|---|---|
| round 1 done and you pushed fixes | go to Step 2 (round 2) on the new head |
| round 1 done, no fixes needed, bots clean | stop the loop |
| round 2 done | stop. Do NOT request round 3. New findings of round 2: fix the valid ones with tests, push, reply — no new request |
| a bot keeps arguing an invalid point | reply once with proof; do not argue again; list it for the owner |

When stopping:
1. `status set <TOPIC> review_open_threads "<THREADS: line>"`
2. Update the PR body "Reviews" section (`pr-edit <n> --body-file …`): rounds used `<r>/2`, fixed / replied counts.
3. `stage` = `08-ci-watch` if the last push has no green CI yet; else `09-dev-test` (when the project has a dev
   environment and the owner wants it) or `10-owner-approval`.

## Definition of done

- [ ] `review_round` ≤ 2 (or the owner's quoted OK for more).
- [ ] Every finding has a row with verdict and a `REPLY:` id; every fix has a sha7 and a test name.
- [ ] `THREADS: 0 open` (or only replied invalid threads, listed for the owner).
- [ ] CI green on the final head; `GATE: PASS` for that head in STATUS.md.
- [ ] PR body "Reviews" section updated.
