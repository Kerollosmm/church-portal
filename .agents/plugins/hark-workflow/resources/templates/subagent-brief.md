# Brief for sub-agent `<agent-name>` — stage <NN-stage>

You start with NO memory of the conversation. Everything you need is below or in the files named here.

1. **Read first:** `<STATUS path>` (the State table), then the skill `<hw-skill>` (folder `<KIT>/skills/<hw-skill>/SKILL.md`)
   and follow it step by step.
2. **Goal of this stage:** <one sentence>
3. **Inputs:** repo `<path>` · worktree `<path>` · branch `<branch>` · base `<base>` · PR `#<n>` · plan `<plan file>` §<x>
4. **Acceptance criteria in scope:** AC<n>, AC<m> (text in the plan)
5. **Commands you will need:** `node "<KIT>/scripts/hw.mjs" <cmd>` … (exact lines from the skill)
6. **Do NOT:** push to main · force-push · rebase · write live data · run seed / deploy · edit files outside
   `<paths>` · merge · ask the owner (send questions back to me instead).
7. **Definition of done (all must be true, with evidence):**
   - [ ] <DoD line 1 from the skill>
   - [ ] STATUS.md updated (`stage`, `next_action`, evidence log line)
8. **Return to me with `send_message`, exactly this format:**
   ```
   STAGE: <NN-stage> RESULT: DONE | BLOCKED | FAILED
   EVIDENCE:
   - <verdict line copied from a command, e.g. GATE: PASS — … / CI: GREEN on abc1234>
   - <SHA / URL / file path>
   CHANGED: <files or "none">
   QUESTIONS_FOR_OWNER: <numbered list or "none">
   NEXT: <what the parent should do next>
   ```
   If you are blocked: stop, fill BLOCKED with the exact error text and what you tried (max 2 attempts).
