---
name: hw-worktree
description: >-
  Stage 03 of the hark-workflow loop: create one git worktree per PR (never work on main), based on the right branch
  for a stacked chain, and keep chain branches in sync with merges (no rebase, no force-push). Use before
  implementing a PR, and whenever a lower PR of a chain changed.
---

# hw-worktree — one worktree per PR (stage 03)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the `repo` folder (the main checkout).
3. One action per step, in order.

## Rules

- The main checkout stays on `main` and clean. Only `git fetch` and `git worktree …` run there.
- One worktree per branch. One agent per worktree.
- Branch names: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, `chore/<slug>`. Never reuse a branch name.
- Never `git rebase`. Never `git push --force`.

## Step 1 — Pick name and base

| Case | Branch | Base |
|---|---|---|
| Single PR | `feat/<slug>` or `fix/<slug>` | `main` |
| First PR of a chain | `feat/<topic>a-<slug>` | the plan branch `docs/<topic>-plan` (or `main` when there is no plan PR) |
| Next PR of a chain | `feat/<topic>b-<slug>` | the previous chain branch |
| Continue an existing PR | its branch | (exists on origin) |

## Step 2 — Create

1. Run: `node "<KIT>/scripts/hw.mjs" worktree <branch> --base <base>`
   (existing PR branch: `node "<KIT>/scripts/hw.mjs" worktree <branch> --existing`)
2. Read the last line. IF `WORKTREE: CREATED` or `WORKTREE: EXISTS` → copy the printed folder path.
   IF `ERROR` → read the message. Network or sign-in problem → fix once (see README troubleshooting), retry once.
3. Write STATUS.md rows: `branch`, `worktree` (the path), `base`.
4. Move into the worktree folder for every later command of this PR.
5. Run the project setup once (Flutter: `flutter pub get`; Node: `npm ci`).
6. Log: `node "<KIT>/scripts/hw.mjs" status log <TOPIC> "<WORKTREE: line>"`
7. Set `stage` = `04-implement`.

## Step 3 — Sync a chain after a lower PR changed (propagation)

Do this in each higher worktree, bottom-up (B after A changed, then C, then D …):

1. `git fetch origin`
2. `git merge --no-ff origin/<lower-branch> -m "Merge <lower> fixes into <this>"`
3. IF conflicts → open each conflicted file, keep both changes correctly, `git add <file>` (explicit path), then
   `git commit --no-edit`. Run `hw-local-gate`.
4. `git push origin <this-branch>`
5. Log the new head SHA.

## Step 4 — Cleanup (only after the PR is merged AND the owner agreed)

1. `git worktree remove <path>` (from the main checkout).
2. Deleting remote branches: only after the whole chain is merged (deleting a base branch closes dependent PRs).

## Definition of done

- [ ] `WORKTREE: CREATED|EXISTS` line in STATUS.md log; rows `branch`, `worktree`, `base` filled.
- [ ] Setup ran in the worktree. `stage` = `04-implement`.
