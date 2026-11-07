---
name: hw-plan
description: >-
  Stage 02 of the hark-workflow loop: write the plan document in the repo (docs/plans/), design the PR chain (one PR
  per topic, stacked when they depend on each other), reserve ADR numbers without collisions, set size and cost
  budgets, open the plan as a draft docs PR and get the owner's approval (gate G0) before any code.
---

# hw-plan — plan doc, PR chain, budgets, owner gate G0 (stage 02)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the `repo` folder.
3. One action per step, in order.

## Step 1 — Size the work

| IF the change … | THEN |
|---|---|
| touches ≤ 5 files, one topic, no new data fields | One PR. Plan = the STATUS.md AC list + a short `docs/plans/<topic>.md`. Skip the chain table. |
| has 2+ topics that can ship alone | Several independent PRs, each based on `main`. |
| has parts that build on each other (data → UI → admin → push) | A **stacked chain**: PR A based on the plan branch, PR B on A, … |

## Step 2 — Reserve ADR numbers

1. Run: `node "<KIT>/scripts/hw.mjs" adr-next`
2. Copy the last line (`ADR-NEXT: ADR-<n>`) into STATUS.md log.
3. Give the plan PR number `<n>` and each chain PR the next numbers in order (`<n+1>`, `<n+2>`, …).
4. IF the output shows a "claimed:" line for a number you want → take a higher number. Never reuse a claimed number.

## Step 3 — Measure the baselines (only when the plan touches the public page load)

1. Size baseline. IF `.agents/workflow.env` has `SIZE_BASELINE_REF` equal to the current `origin/main` short SHA →
   use those numbers. ELSE:
   1. `git fetch origin`
   2. `git worktree add --detach .work/wt/_base origin/main`
   3. move into `.work/wt/_base`, run `node "<KIT>/scripts/hw.mjs" gate --only setup,build`
   4. run `node "<KIT>/scripts/hw.mjs" size` and copy the `SIZE:` line (raw and gzip bytes) into STATUS.md
   5. back in the main checkout: `git worktree remove .work/wt/_base`
   6. tell the owner the new numbers; they go into `SIZE_BASELINE_RAW/GZ/REF` in the next docs commit.
2. PageSpeed: run `node "<KIT>/scripts/hw.mjs" psi` (median of 3, mobile + desktop). Copy the `PSI:` line.
   IF it fails with a quota error → write "PSI: not measured (quota)" and use the project baseline from
   `.agents/workflow.env` (`PSI_BASELINE_*`).
3. Write budgets per PR into the plan (e.g. "PR A: ≤ +20 KB gzip"; "PSI mobile must stay ≥ 61").

## Step 4 — Write the plan document

1. Create the folder `<PLANS_DIR>/<topic>/` (default `docs/plans/<topic>/`).
2. Copy `<KIT>/resources/templates/plan.md` to `<PLANS_DIR>/<topic>/README.md`.
3. Fill every section. Rules:
   - AC table copied from STATUS.md, each with "How it is proven".
   - Out of scope written explicitly.
   - Cost section has numbers (reads / writes / listeners per visit; money = 0 unless the owner agreed).
   - Every setting the visitor sees is configurable by the admin (when the project has that rule).
   - Owner decisions: numbered, each with "recommended".
4. For a chain: one file per PR (`PR-A-<slug>.md`, …) with: sub-features, step-by-step order, files, tests, size
   budget, manual QA table, ADR number. Plus `STATUS.md` (checkbox per PR) and `HANDOFF.md` (how another agent
   continues) inside the plan folder — copy the structure from `examples/church-portal/` in the kit.
5. Write `plan_doc` and `chain` rows in STATUS.md (chain format: `A feat/x-a←docs/x-plan; B feat/x-b←feat/x-a`).

## Step 5 — Open the plan PR (docs only)

1. Create the plan branch worktree: `node "<KIT>/scripts/hw.mjs" worktree docs/<topic>-plan --base main`
2. Move into the printed folder. Copy the plan files there.
3. Add the ADR block for the plan: `node "<KIT>/scripts/hw.mjs" adr-new "<Plan title>" --id ADR-<n>`
4. Stage explicit paths only: `git add docs/plans/<topic> docs/memory-bank/10-decisions-and-history.md`
5. Commit: `git commit -m "docs(plan): <title> (ADR-<n>)"`
6. Push: `git push -u origin docs/<topic>-plan`
7. Run the skill `hw-open-pr` steps 3–6 (draft PR, body). Then `hw-ci-watch`. Bot reviews on a plan PR: optional,
   max 2 rounds (`hw-review-loop`).

## Step 6 — Owner gate G0

1. Send the owner (owner's language): the PR link, the chain table, the budgets, the numbered decisions.
2. Set `stage` = `02-plan`, `next_action` = `wait for G0`. Stop.
3. When the owner approves: write `owner_approval` = `G0 <quote> <time>`; set `stage` = `03-worktree`.
4. When the owner asks for changes: edit the plan files in the plan worktree, commit, push, reply. Stay in stage 02.

## Definition of done

- [ ] Plan doc in the repo with AC, scope/out-of-scope, chain, ADR numbers from `adr-next`, budgets, decisions.
- [ ] Draft plan PR open, CI green (`CI: GREEN` line in STATUS.md).
- [ ] `owner_approval` contains G0 with the owner's words and time.
