---
name: hw-merge
description: >-
  Stage 11 of the hark-workflow loop: squash-merge an approved PR with a head-SHA guard (hw.mjs merge refuses if the
  head moved or CI is not green), and merge a stacked chain bottom-up, retargeting and catching up each next PR with
  main before merging it. Runs ONLY with the owner's recorded merge approval for that PR. Use when STATUS.md
  owner_approval contains "merge" for the PR (or the whole chain).
---

# hw-merge — squash, head-SHA guard, chains bottom-up (stage 11)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the main checkout (`repo` row) unless a step names a worktree.
3. One action per step, in order.

## Hard gate — check BEFORE anything else

Read row `owner_approval`. Merge PR `#<n>` only when ALL are true:

| Check | Else |
|---|---|
| there is an entry `merge #<n> «<owner's words>» <time zone> @ <sha7>` for this PR (or a chain-wide merge order that names this chain) | STOP. Do not merge. Ask the owner (`hw-owner-approval`). |
| the owner's words were written in THIS conversation (not copied from an old STATUS) | STOP. Ask again. |
| chain: every PR of the chain has an approval entry | STOP. Merge nothing. |

Never merge because "everything is green". Never merge someone else's PR. Never use admin override.

## Step 1 — Order

1. Single PR → the list is just `#<n>`.
2. Chain → bottom-up order from STATUS row `chain`: plan PR (if any) → A → B → C … The lowest PR first. Never merge a
   higher PR before the one below it is merged.
3. Write the order in STATUS.md log: `merge order: #p, #a, #b, …`.

## Step 2 — For each PR in order (one at a time)

### 2.1 Check the state

1. Run: `node "<KIT>/scripts/hw.mjs" pr-status <n>`
2. Read the last line `PR-STATUS: …` and decide:

| Seen | Do |
|---|---|
| `CI GREEN`, `open threads 0`, head sha7 = approved sha7 | 2.2 |
| head sha7 ≠ approved sha7 | 2.4 (head moved) |
| `CI RED` / `RUNNING` | `hw-ci-watch`; come back when green on this head |
| `open threads <k>` > 0 | reply/resolve first (`hw-review-loop` Step 7) |
| base is not `main` and the PR below is merged | 2.3 (retarget) |
| `mergeable: false` / `dirty` | 2.3 step 3–6 (catch up with main) |

### 2.2 Make it ready and merge

1. IF the PR is a draft: the owner's merge order includes "ready". Run
   `node "<KIT>/scripts/hw.mjs" pr-ready <n> --approval "<owner's exact words> <time zone>"` → `PR-READY: #<n> READY FOR REVIEW`.
   (Error / `STILL DRAFT` → ask the owner to press "Ready for review" on the PR page.)
2. Run: `node "<KIT>/scripts/hw.mjs" merge <n> --sha <approved sha7> --approval "<owner's exact words> <time zone>"`
3. Read the last line:

| Line | Do |
|---|---|
| `MERGE: #<n> squashed as <sha7> (<full sha>) — approval: …` | 2.5 |
| `ERROR: head moved: …` | 2.4 |
| `ERROR: CI not green …` | `hw-ci-watch`, then retry 2.2 once |
| `ERROR: PR is still a draft` | do 2.2 step 1, retry once |
| `HTTP 405` / "not mergeable" / "Base branch was modified" | 2.3 step 3–6, then retry once |
| `HTTP 403` / branch protection "review required" | STOP. Tell the owner: GitHub requires a human review/approval on the PR page. |

### 2.3 Retarget and catch up (chains, and any PR behind main)

1. After the PR below was merged, retarget this PR to main: `node "<KIT>/scripts/hw.mjs" pr-edit <n> --base main`.
2. Move into this PR's worktree (`hw-worktree` Step 2 with `--existing` if it is gone).
3. `git fetch origin`
4. `git merge --no-ff origin/main -m "Merge main (after #<lower>) into <branch>"`. Never rebase.
   The lower PR was squashed, so its commits come back as one squash commit; conflicts are usually the same lines on
   both sides → keep the version that equals the lower branch's final content. `git add <file>`, `git commit --no-edit`.
5. Run `hw-local-gate` → `GATE: PASS`. Push: `git push origin <branch>`. Then `hw-ci-watch` → `CI: GREEN on <new sha7>`.
6. Check whether the approval carries over: `git diff <approved sha7> HEAD --stat`
   - prints NOTHING → the code is the same as approved. Log `approval carried to <new sha7>: only merge of main
     after #<lower>, empty diff vs <approved sha7>` and use `<new sha7>` in 2.2.
   - prints files → new code. Go to 2.4.

### 2.4 Head moved (new code since approval)

1. List the new commits: `git log --oneline <approved sha7>..origin/<branch>`.
2. STOP merging. Ask the owner again (`hw-owner-approval` Step 5) with the commit list. Merge only after a new
   approval line with the new sha.

### 2.5 After each merge

1. `status set <TOPIC> merge_sha "<existing value> ; #<n> → <sha7>"`; log the `MERGE:` line.
2. The push to main starts the production deploy. Run `hw-deploy-verify` Step 1–2 for this merge sha before the next
   PR of the chain (a broken deploy stops the chain).
3. Project with a dev environment → main's rules are back in production; dev's are gone. Note it: the dev deploy is
   re-run once the chain is done (`hw-dev-test` Step 7).
4. Next PR in the order → 2.1.

## Step 3 — Cleanup (after the WHOLE list is merged)

1. Do NOT delete a branch while another open PR uses it as its base (deleting it closes that PR).
2. When all are merged and the owner agrees: `git worktree remove <path>` for each PR worktree (from the main checkout).
   Remote branch deletion only with the owner's OK.

## Next stage

`stage` = `12-deploy-verify`, `next_action` = `full deploy verification of <last merge sha7>`.

## Definition of done

- [ ] Each merged PR: approval line (owner's words + time + sha) AND a `MERGE: #<n> squashed as <sha7>` line.
- [ ] Chain merged bottom-up; each "approval carried" line shows an empty diff, or a new approval exists.
- [ ] Deploy run checked after each merge; `merge_sha` row filled.
