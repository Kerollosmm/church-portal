# Plan — <title>

> File: `docs/plans/<topic>/README.md` (one folder per plan; one file per PR for a chain: `PR-A-<slug>.md`, …).
> The owner approves this file (gate G0) before any code is written.

## 1. Goal (owner's words)
<one or two sentences, quoted>

## 2. Acceptance criteria (each one checkable by a test, a command or a screenshot)
| # | Criterion | How it is proven |
|---|---|---|
| AC1 | <visitor sees …> | widget test `<name>` + screenshot 390 px |
| AC2 | <admin can switch … off in /admin> | admin test `<name>` + rules test allow/deny |

## 3. Scope
- In: <bullets>
- **Out of scope** (will NOT be done in this plan): <bullets>

## 4. Design
- Data (collections / fields / defaults; the 4 places: model, admin schema, rules, seed):
- UI (pages, admin screens, strings ar/en):
- Config the admin controls (nothing hard-coded):
- Cost (reads / writes / listeners per visit, quota, money): <numbers>
- Size budget: bundle gzip Δ ≤ <N> KB · PSI must stay ≥ baseline <mobile x/x/x/x, desktop x/x/x/x>

## 5. PR chain (stacked: each PR is based on the previous PR's branch)
| # | PR | Branch | Base | ADR | Size budget |
|---|---|---|---|---|---|
| 0 | plan (this doc) | `docs/<topic>-plan` | `main` | ADR-<n> | 0 |
| 1 | A — <slug> | `feat/<topic>a-<slug>` | `docs/<topic>-plan` | ADR-<n+1> | +<k> KB gz |

ADR numbers: from `hw.mjs adr-next` on <date> (highest claimed ADR-<x>).

## 6. Tests per PR
- Unit: <logic> · Widget: <pages, 320/390/1280 px, RTL + LTR, switch on/off> · Rules (emulator): allow + deny · Regression: <bug>

## 7. Risks and rollback
- <risk> → <mitigation>. Rollback: <revert PR / admin switch off>.

## 8. Owner decisions needed (numbered, each with a recommended answer)
1. <question> — recommended: <answer>

## 9. Gates
G0 plan approved · G1 each PR visually approved (390 px) · G2 whole chain green · G3 owner says "merge" · G4 deploy verified
