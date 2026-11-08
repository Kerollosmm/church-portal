# QA / simulation report — phase <P#> «<name>» (<date time zone>)

- Environment: **emulator / local build only** (no live writes) · build <sha7> · data: <seed / fixture file>
- Scenario: <what is simulated, e.g. Holy Week 2027 day 3 at 18:00 Africa/Cairo, clock = …>
- How the clock / data were set: <test harness, --dart-define, fixture> (never by writing live settings)

| # | Check | Expected | Seen | Result | Evidence |
|---|---|---|---|---|---|
| 1 | <home hero shows …> | <…> | <…> | PASS / PARTIAL / FAIL / N/A (<reason>) | <screenshot path / test name> |

**Findings** (each → a fix PR or an open task):
1. [severity] <what> — repro: <steps> — suspected cause: <file:line>

Result meanings: **PASS** = as expected, with evidence · **PARTIAL** = works but with a gap (say which) · **FAIL** =
wrong or broken · **N/A** = cannot be checked here (e.g. "needs live", "needs a real phone") — list it for `hw-deploy-verify` / the owner.

Counts: PASS <a> · PARTIAL <b> · FAIL <c> · N/A <d>

**Verdict:** PHASE <P#> PASS | PARTIAL | FAIL (<n> findings) — PASS only when there is no FAIL and no PARTIAL. Next phase
only after the owner reviews this report.
