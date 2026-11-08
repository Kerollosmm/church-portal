---
name: hw-open-pr
description: >-
  Stage 06 of the hark-workflow loop: push the PR branch and open a DRAFT pull request with the full body template
  (chain links, plan, ADR, AC with proof, out-of-plan fixes, cost, gate line, size, docs, risks, owner actions).
  Use after the local gate passed for the first time on a PR branch. Never marks the PR ready and never merges.
---

# hw-open-pr — push + draft PR with a complete body (stage 06)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run every command from the `worktree` folder.
3. Check: STATUS row `gate` starts with `GATE: PASS` AND its sha7 equals `git rev-parse --short HEAD`.
   IF not → run `hw-local-gate` first.
4. One action per step, in order.

## Steps

1. **Check the branch.** `git branch --show-current` must print the STATUS `branch` (not `main`).
2. **Check the base is current.** `git fetch origin` then `git log --oneline HEAD..origin/<base> | head -5`.
   - IF it prints commits → `git merge --no-ff origin/<base> -m "Merge <base> into <branch>"`, then run
     `hw-local-gate` again. Never rebase.
   - IF it prints nothing → continue.
3. **Push.** `git push -u origin <branch>` (a normal push; never `--force`).
   - IF the hook denies it (protected branch) → you are on the wrong branch. STOP and fix with `hw-worktree`.
   - IF `rejected (fetch first)` → someone else pushed. `git fetch origin`, `git merge --no-ff origin/<branch>`,
     gate again, push again. Never force.
4. **Write the body.** Copy `<KIT>/resources/templates/pr-body.md` to `.work/<TOPIC>/pr-body.md`. Fill EVERY section:

| Section | Where the value comes from |
|---|---|
| Chain | STATUS `chain` row. Single PR → "none — base is main". |
| Plan · ADR | STATUS `plan_doc`; ADR number reserved in `hw-plan` (never invent a new one here). |
| What / why | the goal in STATUS.md, 1–3 sentences, visitor/admin view. |
| Sub-features | the plan's list; each "done" has a file path; "deferred" has a reason. |
| Acceptance criteria | AC lines from STATUS.md, each with its proof (test name / screenshot). |
| Out-of-plan fixes | STATUS "Out-of-plan fixes" (problem, cause, files, proof) or "none". |
| Cost | the plan's numbers (reads / writes / listeners per visit). |
| Tests | the exact `GATE: PASS — …` line; the names of the new tests. |
| CI · Preview | write "pending" now; filled in `hw-ci-watch`. |
| Size | the exact `SIZE:` line. |
| PageSpeed | "pending (after preview)" unless measured. |
| Reviews | "round 0/2 — not requested yet". |
| Screenshots | "pending (stage 10)" now. |
| Docs | file list from the docs commit (`git show --stat <docs sha>`). |
| Risks | live data touched: **no** · rules backward compatible: yes/why · rollback. |
| Owner actions | numbered, each with your recommendation, or "none". |

   Write "none" instead of deleting a section. Numbers only from command output.
   Field names, defaults and labels must match the code (open the file and copy them). A wrong field name or default
   in the body is a review finding (it happened on PR #51: `installBannerEnabled` vs the real key, "Later 7 days" vs
   the real 3).
5. **Title.** `<type>(<area>): <what> (ADR-<n>)`. Chain: start with `[<X>/<total>]`, e.g. `[A/4] feat(install): …`.
6. **Open the draft.** Run:
   `node "<KIT>/scripts/hw.mjs" pr-create --base <base> --head <branch> --title "<title>" --body-file .work/<TOPIC>/pr-body.md`
   Read the last line: `PR: #<n> DRAFT head <sha7> …`.
   - IF `HTTP 422 … A pull request already exists` → find its number:
     `node "<KIT>/scripts/hw.mjs" api GET "repos/{repo}/pulls?state=open&head=<owner>:<branch>"` (read `"number"`),
     then update it with `node "<KIT>/scripts/hw.mjs" pr-edit <n> --body-file .work/<TOPIC>/pr-body.md`.
7. **Chain links.** IF this PR is part of a chain AND the previous PR exists → edit the previous PR body so its
   "next" field points to `#<n>`: `node "<KIT>/scripts/hw.mjs" pr-edit <prev> --body-file <its body file>`.
8. **Record.** `status set <TOPIC> pr "#<n> <url>"`, `status set <TOPIC> head_sha "<sha7>"`,
   `status log <TOPIC> "<PR: line>"`.
9. **Next stage.** `stage` = `08-ci-watch`, `next_action` = `wait for CI on <sha7>`.

## Never

- Never mark the PR "ready for review" yourself. Only when the owner says so.
- Never merge (that is `hw-merge`, gated by the owner).
- Never put a secret, a token, a private e-mail or live user data into the PR body.

## Definition of done

- [ ] `PR: #<n> DRAFT head <sha7>` line in the STATUS log; `pr` and `head_sha` rows filled.
- [ ] `head_sha` equals `git rev-parse --short HEAD` and `git status --short` is empty.
- [ ] Every body section filled or "none"; field names checked against the code.
- [ ] `stage` = `08-ci-watch`.
