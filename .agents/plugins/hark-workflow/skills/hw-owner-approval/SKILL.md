---
name: hw-owner-approval
description: >-
  Stage 10 of the hark-workflow loop: show the owner the finished PR (390 px phone screenshots in the owner's language,
  1280 px desktop, 320 px for banners and sheets), the evidence lines, and the open decisions, then wait for an
  explicit written approval and record it word for word with the time and the head SHA. Use when CI is green, reviews
  are answered and (if used) dev testing is done. Silence, emoji or "nice" is not approval.
---

# hw-owner-approval — screenshots + explicit approval, recorded (stage 10)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the `worktree` folder. `<n>` = PR number.
3. Check all of these. IF one is false → go back to the named stage:

| Must be true | Else run |
|---|---|
| row `ci` = `CI: GREEN on <head_sha>` (same sha as the PR head now) | `hw-ci-watch` |
| row `gate` = `GATE: PASS … @ <head_sha>` | `hw-local-gate` |
| `review_round` ≥ 1 (or `0 (no bots)`) and `THREADS: 0 open` (or only replied invalid threads) | `hw-review-loop` |
| row `docs` filled (docs are in this PR) | `hw-docs-sync` (in-PR) |
| row `dev_test` filled, or `n/a` | `hw-dev-test` |

4. One action per step, in order.

## Step 1 — Take the screenshots

1. Pick the URL: the PR preview URL (row `ci` / PR body) or `DEV_URL` after `hw-dev-test`. Never the live site for
   unmerged work.
2. List the pages / states this PR changes (from the AC list). For each, take:

| Width | Language | When |
|---|---|---|
| 390 px (phone) | the owner's language (church-portal: Arabic, RTL) | always |
| 1280 px (desktop) | the other language (church-portal: English, LTR) | always |
| 320 px | owner's language, biggest text if possible | banners, bottom sheets, dialogs, anything that can overflow |

3. Command: `node "<KIT>/scripts/hw.mjs" screenshot "<url>/<path>?lang=<ar|en>" --width 390 --out .work/<TOPIC>/png/<page>-390-ar.png`
   (height defaults to 844; use `--width 1280 --height 800` for desktop, `--width 320 --height 640` for small).
4. Read each output line `SCREENSHOT: <file> (…)`.
   - IF `SCREENSHOT: NO-CHROME` → copy the printed `/browser …` line for the owner, OR render the screen in a widget
     test at that size and save the golden/PNG (write "widget-test render" next to it).
   - IF the state needs data or a switch that is off on preview → use a widget-test render; never write live data to
     get a screenshot.
5. Open every PNG and LOOK at it (view_file). Check: no overflow stripes, no clipped text, no wrong colours (project's
   banned colours), correct direction (RTL/LTR), times in the project zone (e.g. «٦:٣٠ م» Cairo, not UTC).
   A bad screenshot → it is a bug: back to `hw-implement` / `hw-fix-bug`.
6. Log: `screenshots: <k> files in .work/<TOPIC>/png/ (<list>)`.

## Step 2 — Send the approval request

1. Fill `<KIT>/resources/templates/owner-report.md` in the owner's language (row `owner_language`), status
   "Waiting for you". Include: PR link, what changes for visitors/admins, `GATE:` / `CI:` / `SIZE:` / `PSI:` lines,
   review summary (rounds `<r>/2`), dev URL (if any), the screenshots, open decisions with your recommendation.
2. End with ONE clear question. Examples:
   - Arabic: «هل توافق على طلب الدمج #<n> كما في الصور؟ للموافقة اكتب: "موافق على #<n>" أو "ادمج #<n>".»
   - English: "Do you approve PR #<n> as shown? To approve, reply: "approved #<n>" or "merge #<n>"."
3. Chain: ask about THIS PR only. Say "PR <X>/<total> of the chain; nothing is merged until you approve the whole chain."
4. Set `stage` = `10-owner-approval`, `next_action` = `wait for owner approval of #<n> @ <head_sha>`. Stop and wait.

## Step 3 — Read the answer

| Owner wrote … | Meaning | Do |
|---|---|---|
| "approved #<n>", "موافق", "موافق على #<n>", "تمام اعتمده", "looks good, approve" | **approval** (not yet merge) | Step 4, type `approved` |
| "merge #<n>", "ادمج", "ادمجه", "اعمل merge" | **approval + merge order** | Step 4, type `merge` |
| "ok", "👍", "nice", "حلو", a question, or no answer | **not approval** | answer the question; ask Step 2's question again, word for word. Do not continue |
| a change request ("make it bigger", «غيّر اللون») | changes | write it under "Owner decisions"; `stage` = `04-implement`; after the fix: gate → push → CI → (review round only if rounds left) → back here with NEW screenshots |
| approval with a condition ("merge after you fix X") | conditional | do X first (with test), show the proof, then record the approval quoting the whole sentence |

## Step 4 — Record the approval (word for word)

1. Copy the owner's message exactly (no translation, no shortening) and the time with zone.
2. Run: `node "<KIT>/scripts/hw.mjs" status set <TOPIC> owner_approval "<approved|merge> #<n> «<owner's exact words>» <YYYY-MM-DD HH:MM zone> @ <head_sha>"`
3. Add the same line under "Owner decisions" and in the log.
4. Chain: keep one approval line per PR (append to the row, separated by ` ; `).

## Step 5 — If the head changes after approval

The approval is for the code at `<head_sha>`. IF any new commit lands on the PR (a late bot fix, a merge of the base):
1. Tell the owner what changed (commit list + one line each) and show new screenshots if visible UI changed.
2. Ask again (Step 2). Record the new approval with the new sha. `hw-merge` refuses a head that differs from the
   recorded one.

## Next stage

| Approval type | Next |
|---|---|
| `merge` for this PR (single PR) | `stage` = `11-merge` |
| `approved` only | `next_action` = `wait for "merge"`; stop |
| chain, not all PRs approved | next PR of the chain: `stage` = `03-worktree` for it (when the owner allows) |
| chain, all PRs approved and the owner said merge | `stage` = `11-merge` |

## Definition of done

- [ ] Screenshot files listed in the log (390 px owner language; 1280 px; 320 px where needed), each looked at.
- [ ] Approval request sent with the evidence lines and one explicit question.
- [ ] `owner_approval` holds the owner's exact words, time with zone, PR number and head sha — or the stage is waiting.
