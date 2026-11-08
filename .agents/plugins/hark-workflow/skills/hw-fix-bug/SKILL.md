---
name: hw-fix-bug
description: >-
  Fixes a bug at its root cause with a regression test that fails before the fix and passes after. Use when something
  is broken (wrong output, crash, overflow, empty page, CI failure caused by code) — alone for a quick fix PR, or
  inside hw-implement for bug items.
---

# hw-fix-bug — reproduce, find the cause, fix, prove (inside stage 04)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. IF there is no STATUS → run `hw-start` first. Work in the `worktree` folder.
3. One action per step, in order.

## Steps

1. **Write the symptom** in STATUS.md: what is seen, where (page / width / language / data), since when, how often.
2. **Reproduce with a test.** Write the smallest test that shows the bug. Name it after the bug:
   `regression: <what was wrong>`. Run only that test.
   - IF it fails the way the owner described → good, continue.
   - IF it passes → the test does not reproduce the bug. Change the input (width, language, empty data, time zone,
     switch state) and try again. After 2 tries → STOP and report what you tried.
3. **Find the cause.** Read the code path from the test up to the line that produces the wrong value. Write in STATUS.md:
   `cause: <file:line> — <why it is wrong>`. Do not change code before this line is written.
4. **Fix the cause** — not the symptom. Examples:

| Symptom fix (wrong) | Cause fix (right) |
|---|---|
| Hide the empty-state message | Wait for the server answer instead of treating an empty local cache as "no data" |
| Clip the overflowing text | Let the row wrap / use flexible widths at 320 px × 200 % text |
| Catch and ignore the exception | Validate the input where it enters |

5. Run the regression test → it must pass. Copy the pass line into STATUS.md.
6. Run the tests of the whole area (same folder / feature). All green.
7. Stage explicit paths and commit: `git add <fix files> <test file>` then
   `git commit -m "fix(<area>): <what> — regression test"`.
8. Log: `node "<KIT>/scripts/hw.mjs" status log <TOPIC> "bug fixed: cause <file:line>; test <name> red→green; commit <sha7>"`

## Definition of done

- [ ] Cause line (file:line + why) in STATUS.md.
- [ ] Test output: fails before (or reasoned reproduction), passes after; test name in the log.
- [ ] Commit SHA logged. The PR body will list it (in-plan or out-of-plan fix).
