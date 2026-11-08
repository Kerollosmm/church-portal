---
name: hw-intake
description: >-
  Stage 01 of the hark-workflow loop: turn the owner's request into a clear goal, acceptance criteria, scope and
  out-of-scope, and ask the owner only the questions that change the result. Use for any new feature or change
  request before planning or coding.
---

# hw-intake — understand the request (stage 01)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run commands from the `repo` folder.
3. One action per step, in order.

## Steps

1. Copy the owner's request word for word into STATUS.md under "Owner decisions" with the time.
2. Read these files (skip a file that does not exist):
   1. `AGENTS.md` (root) and every `.agents/rules/*.md`
   2. `docs/memory-bank/00-README.md`, then the memory-bank files it names for the area (architecture, data model,
      features, admin, dev workflow, open tasks, decisions)
   3. `documentation/` file of the feature (human docs)
   4. any plan folder the owner named (e.g. `docs/plans/<x>/`)
3. Search the code for the area: use `grep_search` for 2–4 key words of the request. Write down the main files.
4. Write in STATUS.md (replace the placeholder under "Acceptance criteria"):
   - **Goal**: one sentence, in the owner's words.
   - **Acceptance criteria**: 3–8 lines `AC1 … AC8`. Each must be checkable by a test, a command or a screenshot.
   - **In scope** / **Out of scope**: bullets.
   - **Docs contradict code?**: list any place where the docs say something the code does not do.
5. Decide if questions are needed. A question is needed ONLY when a different answer changes what you build:

| Ask | Do not ask (decide yourself, write it in STATUS.md) |
|---|---|
| Which of two visible behaviours the owner wants | Things a standing rule already answers (e.g. "configurable from admin") |
| Wording that appears on the live site | Code structure, file names, test names |
| Anything that writes live data, costs money, or is hard to undo | Defaults you can change later in admin |
| Scope: "also do X?" when X is big | Small obvious fixes (list them as out-of-plan fixes) |

6. IF questions are needed → send ONE message to the owner (owner's language): at most 3 numbered questions, each with
   "Recommended: …". Set `stage` = `01-intake`, `next_action` = `wait for owner answers`. Stop.
7. IF no questions (or the owner answered) → write the answers in STATUS.md, then set `stage` = `02-plan`,
   `next_action` = `write the plan doc`.
8. Log: `node "<KIT>/scripts/hw.mjs" status log <TOPIC> "intake done: <n> AC, <k> questions"`

## Definition of done

- [ ] Goal, AC1…ACn, in/out of scope written in STATUS.md.
- [ ] Owner questions asked and answered (quoted with time), or "no questions needed" logged with the reason.
- [ ] `stage` = `02-plan`.

## Example (church-portal)

Request: «عايز زرار ذكّرني على كل حدث». Goal: "every event card has a «ذكّرني» button that saves a local reminder".
AC1 button visible on event cards when the admin switch `reminders` is on · AC2 hidden everywhere when off ·
AC3 reminder time shown in Africa/Cairo · AC4 320 px × 200 % text no overflow · AC5 admin edits the lead times list.
Question: "1. Default reminder lead: 30 min or 1 hour? Recommended: 1 hour (most services start on the hour)."
