---
name: hw-implement
description: >-
  Stage 04 of the hark-workflow loop: implement one PR of the approved plan in its own worktree with small commits,
  explicit pathspecs, tests first for bugs, regression tests, the project's config and palette rules, and every
  edge case (widths, RTL/LTR, switch on/off). Use after the worktree exists and the plan is approved.
---

# hw-implement — code + tests for one PR (stage 04)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run every command from the `worktree` folder.
3. Check: `git branch --show-current` prints the STATUS `branch`. IF it prints `main` → STOP, run `hw-worktree`.
4. One action per step, in order.

## Step 1 — Load the plan for this PR

1. Open the plan file for this PR (`plan_doc` row; chain: the `PR-<X>-….md` file).
2. Make a numbered TODO list in STATUS.md log: one line per sub-feature, in the plan's step-by-step order.
3. Read the project rules again: `.agents/rules/*.md` and `AGENTS.md` "Golden rules". Note the rules that apply
   (for example: the 4 places of a data field, palette roles only, strings in the l10n table, time helper).

## Step 2 — For each TODO item, in order

Repeat this loop. One item at a time.

1. **Test first when it is a bug**: follow skill `hw-fix-bug` steps 2–4 (failing test → cause → fix).
2. **Feature**: write the pure logic + its unit test, then the UI, then the widget test.
3. Apply the edge-case table:

| The item touches … | You MUST add / run |
|---|---|
| visible UI | widget test at 320 px × 200 % text (no overflow), 390 px and 1280 px; Arabic RTL and English LTR |
| something tied to a switch / section | test switch ON shows it AND switch OFF hides it everywhere (page, nav, drawer, footer, directory, sitemap, assistant) |
| a data field | the 4 places together: model + admin schema + security rules + seed generator, plus tests for each |
| security rules | emulator tests for an ALLOWED write and a DENIED write; old clients' writes still allowed |
| lists / optional fields | empty, one, many; item without image looks exactly as before |
| times / dates | the project's time-zone helper, never the device clock directly |
| colours | palette roles only (no literal colour values); respect banned colours in project rules |
| user-facing text | the l10n table in both languages; content editable in admin when the project says so |

4. Run the focused tests for the item (e.g. `flutter test test/<file>_test.dart`). IF red → fix. Same failure twice
   → STOP, log BLOCKED with the output.
5. Stage ONLY the files of this item, by path: `git add lib/a.dart test/a_test.dart`
   (never `git add -A`, never `git add .`; check with `git status --short` that nothing else is staged).
6. Commit: `git commit -m "<area>: <what> (ADR-<n>)"`
7. Log: `node "<KIT>/scripts/hw.mjs" status log <TOPIC> "item <k> done: <what> — commit <sha7>"`

## Step 3 — Out-of-plan problems

| You found … | Do |
|---|---|
| A small bug in a file you already touch | Fix it with a test. Add it to STATUS.md "Out-of-plan fixes" (problem, cause, files, proof). It goes in the PR body. |
| A bug elsewhere / big change | Do NOT fix. Write it in STATUS.md as a follow-up for the owner. |
| The plan is wrong or impossible | STOP. Write the problem and 2 options with a recommendation. Ask the owner. |

## Step 4 — Hand over

1. Set `stage` = `04b-docs`, `next_action` = `docs for this PR (hw-docs-sync in-PR)`.
2. Do NOT push yet (the local gate comes after the docs).

## Never

Edit files on `main` · stage unrelated files · commit generated build output, `node_modules`, logs, keys ·
hard-code what the owner wants configurable · write to live data · change the plan silently.

## Definition of done

- [ ] Every TODO item has a commit SHA in the log.
- [ ] Each item has the tests from the edge-case table (names in the log).
- [ ] `git status --short` shows nothing unintended. `stage` = `04b-docs`.
