---
name: hw-start
description: >-
  Entry point of the hark-workflow loop. Use it FIRST for any request about the repository: a new feature, a bug, a
  plan to carry out, "continue", "status", a PR to review, a QA simulation. It creates or reads STATUS.md, decides the
  current stage, and runs (or delegates) the right one of the 18 hw-* skills until the work is live and verified. Also the
  persona-switch fallback for the parent-agent when sub-agents are not available.
---

# hw-start — pick the stage, keep STATUS.md, drive the loop

## Before you start (every time)

1. Find `<KIT>`: the folder that contains `plugin.json`, two levels above this `SKILL.md`. It is also the `kit` row of
   STATUS.md and the `HW_KIT=` value in the session message. In every command below, replace `<KIT>` with that path.
   Keep the double quotes.
2. Run commands from the repository root unless a step says otherwise.
3. One action per step. Do the steps in order.

## Step 1 — Check the machine (once per session)

1. Run: `node "<KIT>/scripts/hw.mjs" doctor`
2. IF the last line is `DOCTOR: FAIL` → fix the FAIL rows (install the tool) or report BLOCKED. Stop.
3. IF the row `config` says MISSING → run the skill `hw-bootstrap` first, then come back here.

## Step 2 — Find or create STATUS.md

1. Look for open STATUS files: list the folder `.work/` (each subfolder with a `STATUS.md` is one topic).
2. Decide with this table:

| Situation | Action |
|---|---|
| The owner says "continue" / "كمّل" and one STATUS exists | Use that topic. |
| Several exist | Use the one whose `goal` matches the request. Not sure → ask the owner which (list them). |
| New request | Pick a short kebab topic (e.g. `install-banner`, `pr51-review`). Run: `node "<KIT>/scripts/hw.mjs" status init <topic> --goal "<owner's words>"` |

3. Read the whole STATUS.md. The `stage` and `next_action` rows tell you where you are.

## Step 3 — Pick the stage

### 3a — The 18 skills (stage map)

| Stage | Skill | Does | Comes after | Goes to |
|---|---|---|---|---|
| — | `hw-start` | routes, keeps STATUS.md, delegates (this skill) | — | any stage |
| 00 | `hw-bootstrap` | sets up a repo: workflow.env, AGENTS.md, memory bank, rules, baselines | doctor says config MISSING | back to `hw-start` |
| 01 | `hw-intake` | goal, AC, scope, owner questions | new request | 02 |
| 02 | `hw-plan` | plan doc, PR chain, ADR numbers, budgets, owner gate G0 | 01 | 03 |
| 03 | `hw-worktree` | one worktree per PR; chain sync | G0 approved | 04 |
| 04 | `hw-implement` | code + tests for one PR | 03 | 04b |
| 04 | `hw-fix-bug` | root cause + regression test (inside 04, or alone for a bug) | bug found | 04b |
| 04b | `hw-docs-sync` (mode A, in-PR) | memory bank, ADR, user docs, open tasks, history — same PR | 04 | 05 |
| 05 | `hw-local-gate` | full local gate + size before every push | 04b, or any fix | 06 (first time) / back to 07 or 08 |
| 06 | `hw-open-pr` | push + draft PR with full body | 05 | 08 |
| 07 | `hw-review-loop` | CodeRabbit + Sentry, triage, fix with tests, reply every thread, max 2 rounds | CI green | 08 / 09 / 10 |
| 08 | `hw-ci-watch` | green CI on the head; red → logs, reproduce, fix | every push | 07 (first time) / 09 / 10 |
| 09 | `hw-dev-test` | merge into dev, dev channel deploy, test on dev (optional) | reviews done, owner wants dev | 10 |
| 10 | `hw-owner-approval` | 390 px screenshots, explicit approval recorded | 07–09 done | 11 (owner said merge) |
| 11 | `hw-merge` | squash with head-SHA guard; chains bottom-up | recorded merge approval | 12 |
| 12 | `hw-deploy-verify` | CI + deploy on main, live smoke, PSI, Sentry | 11 | 13 |
| 13 | `hw-docs-sync` (mode B, after-merge) | docs landed on main, live facts, final report | 12 | done |
| side | `hw-pr-review` | review someone else's PR, verdict report | owner: "review PR #n" | done |
| side | `hw-qa-sim` | emulator-only QA phase, one report per phase | owner: "simulate / QA" | done (fixes → new topic) |

### 3b — Routing table

Use the FIRST row that matches. The stage skill does the work; this skill only routes.

| # | IF … | THEN run skill | Agent (when delegating) |
|---|---|---|---|
| 1 | `blocked` = yes | report the block to the owner (rule `reporting`); stop | parent |
| 2 | `doctor` row `config` is MISSING, or the owner says "set up the kit / workflow" | `hw-bootstrap` | orchestrator |
| 3 | request is "review PR #n" (someone else's PR) | `hw-pr-review` | pr-reviewer |
| 4 | request is "simulate / QA / test phases" | `hw-qa-sim` | qa-tester |
| 5 | request is "is it live? / verify the deploy" for merged work | `hw-deploy-verify` | release-verifier |
| 6 | stage `01-intake` (new request) | `hw-intake` | planner |
| 7 | stage `02-plan` or plan not approved (`owner_approval` lacks "G0") — a one-file bug fix may skip the plan doc: intake AC are enough | `hw-plan` | planner |
| 8 | stage `03-worktree` (plan approved, PR branch missing) | `hw-worktree` | orchestrator |
| 9 | stage `04-implement` and the item is a bug | `hw-fix-bug` | implementer |
| 10 | stage `04-implement` | `hw-implement` | implementer |
| 11 | stage `04b-docs` | `hw-docs-sync` (mode A, in-PR) | docs-keeper |
| 12 | stage `05-local-gate` | `hw-local-gate` | implementer |
| 13 | stage `06-open-pr` | `hw-open-pr` | implementer |
| 14 | stage `08-ci-watch` | `hw-ci-watch` | release-verifier |
| 15 | stage `07-review-loop` | `hw-review-loop` | reviewer-fixer |
| 16 | stage `09-dev-test` | `hw-dev-test` | release-verifier |
| 17 | stage `10-owner-approval` | `hw-owner-approval` | parent |
| 18 | stage `11-merge` AND `owner_approval` has `merge #<n>` with the owner's words | `hw-merge` | release-verifier |
| 19 | stage `11-merge` but no recorded merge approval | `hw-owner-approval` (never merge without it) | parent |
| 20 | stage `12-deploy-verify` | `hw-deploy-verify` | release-verifier |
| 21 | stage `13-docs-final` | `hw-docs-sync` (mode B, after-merge) | docs-keeper |
| 22 | stage `done` | report to the owner; stop | parent |

Red CI caused by code: `release-verifier` returns FAILED with the diagnosis (it never edits code) → delegate
`hw-ci-watch` Step 3 to `implementer` in the same worktree.

The normal order for one PR is: 03 → 04 → 04b → 05 → 06 → 08 → 07 → 08 → (09) → 10 → 11 → 12 → 13.
Every fix (review, CI, owner change) goes back through 05 (gate) and 08 (CI) before the next stage.
For a chain, repeat 03–10 for each PR (next PR only when the owner allows), then 11 → 12 → 13 once for the whole
chain, bottom-up. After ANY push to main in a project with a dev environment, run `hw-dev-test` Step 7 (re-deploy
dev rules) when dev still holds unmerged work.

## Step 4 — Run the stage

Choose ONE mode:

| IF | THEN |
|---|---|
| You are the `parent-agent` AND the tool `invoke_subagent` exists | Delegate (Step 5). |
| Otherwise (IDE, no sub-agents, or delegation failed twice) | Persona mode: open `<KIT>/agents/<agent>.md`, read its "Role", "Checklist" and "Never" sections, then run the stage skill yourself as that agent. Write `persona: <agent>` in the log line. |

## Step 5 — Delegate (parent-agent only)

1. Copy `<KIT>/resources/templates/subagent-brief.md` into `.work/<topic>/brief-<stage>.md` and fill every `<…>`.
2. Call `invoke_subagent` with one sub-agent: `TypeName` = the agent name from the table (e.g. `implementer`;
   if the tool answers that the type is unknown, retry once with `hark-workflow:implementer`), `Role` = the stage
   name, `Prompt` = the full text of the brief, `Workspace` = `inherit`.
3. Wait for its `send_message` reply. Do not do the stage yourself while it runs.
4. Check the reply against the stage skill's **Definition of done**:
   - every DoD line has evidence (a verdict line like `GATE: PASS`, a SHA, a URL);
   - STATUS.md shows the new `stage`.
5. Decide:

| Reply | Action |
|---|---|
| DONE and all evidence present | Log `<stage> DONE (<agent>) — <evidence>`. Go to Step 3. |
| DONE but evidence missing | `send_message` to the same sub-agent: "Evidence missing for: <lines>. Run the commands and send the verdict lines." Count it as a retry. |
| FAILED / BLOCKED | Increase `retries_this_stage`. IF it is now 3 → set `blocked` yes, report to the owner, stop. ELSE send a new brief with the error and one concrete hint. |
| QUESTIONS_FOR_OWNER not "none" | Ask the owner (Step 6) and wait. |

6. Reset `retries_this_stage` to 0 when a stage is DONE.

## Step 6 — Talking to the owner

1. Use the owner's language (`owner_language`). Template: `<KIT>/resources/templates/owner-report.md`.
2. Ask at most 3 questions, numbered, each with your recommended answer.
3. Write the owner's answer, quoted, with the time, under "Owner decisions" in STATUS.md before you continue.

## Stop conditions

- The owner must decide something → ask, stop, wait.
- `blocked` = yes → report, stop.
- Stage `done` → final report, stop.

## Definition of done (this skill)

- STATUS.md exists and its `stage` / `next_action` match what you did.
- Every stage you ran has a log line ending with evidence.
