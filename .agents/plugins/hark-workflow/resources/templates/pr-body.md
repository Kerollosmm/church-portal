<!-- Fill EVERY section. Write "none" instead of deleting a section. Numbers come from command output only. -->
**Chain:** ⬅ previous: <#n-1 (branch) | none — base is main> · ➡ next: <#n+1 | not opened yet>
**Plan:** `<docs/plans/…/PR-X-….md>` · **ADR-<nnn>** · **Draft — do not merge** (merged only after the owner says "merge"; chains bottom-up)

## What / why
<1–3 sentences: what changes for visitors / admins, and why. Link the owner's request.>

## Sub-features from the plan
| Plan item | Status | Where |
|---|---|---|
| <item> | done / deferred (why) | `<file>` |

## Acceptance criteria
- [ ] AC1 <text> — proof: <test name / screenshot>

## Out-of-plan fixes
<!-- Anything fixed that the plan did not list. One bullet each, or "none". -->
- **<problem>** — cause: <cause>; files: `<paths>`; proof: <test / output>

## Cost (reads / writes / listeners per visit, quotas, money)
<numbers, or "none: no new reads or writes">

## Tests
- Local gate: `GATE: PASS — …` (copy the line) · tests **<N> passed** · rules **<x>/<x>** · seed diff clean
- New tests: `<name>` (regression for <bug>), `<name>` (320 px × 200 % text), `<name>` (RTL + LTR), `<name>` (switch off hides it)

## CI · Preview
- CI on `<sha7>`: <GREEN (k checks) | RED: job> · Preview: <url from the bot comment>

## Size
`<SIZE_FILE>` raw <bytes> (<Δ>) · gzip-9 <bytes> (<Δ>) · budget <+N B gz> → <OK | OVER>

## PageSpeed (median of 3, after the preview / dev deploy)
mobile <p/a/bp/seo> · desktop <p/a/bp/seo> · baseline mobile <…> desktop <…>

## Reviews
- CodeRabbit: round <r> — <k> findings: <x> fixed (<sha7>), <y> replied (not applicable: why) | rate-limited at <time>
- Sentry: round <r> — <clean 🎉 | k fixed>
- Rounds used: <r>/2

## Screenshots (390 px Arabic · 1280 px English; 320 px for banners / sheets)
| 390 px ar | 1280 px en |
|---|---|
| ![](<raw url>) | ![](<raw url>) |

## Docs (same PR)
memory bank `<files>` · documentation/ (Arabic) `<files>` · documentation/en `<files>` · ADR-<nnn> · open tasks <ticked / added> · STATUS ticked

## Risks and rollback
- Live data touched: **no** · Rules backward compatible with main: <yes/why> · Rollback: <revert / admin switch>

## Owner actions needed
1. <decision with my recommendation> (or "none")
