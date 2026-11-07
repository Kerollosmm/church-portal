---
trigger: model_decision
description: "How to report to the owner: finished work, blocked work, waiting-for-approval. Apply when you finish a stage that needs the owner, stop on a blocker, or the owner asks for status."
---

# Reporting to the owner

- Write in the owner's language (`OWNER_LANGUAGE`; STATUS.md `owner_language`). Template:
  `<KIT>/resources/templates/owner-report.md` (English + Arabic versions).
- First line = the outcome. Then short lines. The owner reads on a phone.
- Every number and status is copied from a command's verdict line (`GATE:`, `CI:`, `SIZE:`, `PSI:`, `DEPLOY:`).
- Times with their zone (e.g. 15:34 EET). Quote Arabic UI strings exactly «…».
- Questions for the owner: numbered, at most 3, each with your recommended answer.

## Blocked report (use exactly this shape)
```
BLOCKED at <stage>: <exact error, quoted>
Tried: 1) <attempt> → <result>  2) <attempt> → <result>
Need from you: <one concrete action or decision>
State: branch <name> @ <sha7> · PR #<n> (draft) · nothing pushed to main · no live data touched
```
