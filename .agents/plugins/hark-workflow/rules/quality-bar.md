---
trigger: model_decision
description: "The quality bar for any code change: tests first for bugs, edge cases, root cause, configurable not hard-coded, docs in the same PR, small PRs. Apply whenever you write, change, review or merge code."
---

# Quality bar — a PR is not done until every line is true

| # | Rule | How to prove it |
|---|---|---|
| Q1 | A bug gets a failing test FIRST, then the fix of the cause (not the symptom). | test fails on the old code, passes on the new; both outputs in STATUS.md |
| Q2 | Every behaviour change has a test. | test name in the PR body |
| Q3 | Business logic is pure (no UI / network in the logic layer) and unit-tested. | unit test file |
| Q4 | UI changes are checked at 320 px with 200 % text, 390 px and 1280 px, RTL and LTR. | widget tests / screenshots |
| Q5 | A feature switch OFF hides the feature everywhere; ON brings it back. | test for both states |
| Q6 | Empty / one / many; missing optional fields (a card without an image looks exactly as before). | tests |
| Q7 | Security-rules changes ship with emulator tests for ALLOWED and DENIED writes. | rules test output |
| Q8 | Nothing user-facing is hard-coded when the project says "configurable from admin". | admin field + test |
| Q9 | Strings live in the project's l10n table, both languages. | grep shows no literal UI text |
| Q10 | Memory bank, human docs and an ADR are updated in the SAME PR. | file list in the PR body |
| Q11 | One topic per PR. Out-of-plan fixes are listed in the PR body (problem, cause, files, proof). | PR body |
| Q12 | The full local gate passes before every push (`GATE: PASS`). | verdict line in STATUS.md |
| Q13 | No dead code, no commented-out code, no TODO without an open-task entry. | review |
