---
trigger: always_on
description: "Standing rules and mandatory Hark Workflow for church-portal. Automatically active on every turn."
---

# church-portal standing rules & Hark Workflow

## Mandatory Workflow (Always On)
For EVERY feature, bugfix, refactor, rule modification, or docs change in this project:
1. **Always follow `hark-workflow` automatically**: Default to the `orchestrator` agent persona and execute the `ship-change` loop (or `fix-bug` for bugs). Never make ad-hoc, unverified changes directly.
2. **Intake & Acceptance Planning**: Before touching code, write/update the status note in `.work/<branch>/status.md` with:
   - Restatement of goal in owner's words.
   - Files to change (including the 4-places rule if a field is touched).
   - Checkable acceptance criteria bullets (320/400/1400 px responsive, RTL Arabic & LTR English, feature toggles on/off).
   - Risks & edge cases.
3. **Branching**: Always work on a feature branch (`feat/`, `fix/`, `docs/`, `chore/`). Never push or commit directly on `main`. Never force-push.
4. **Local Gate**: Must pass `scripts/verify.sh` (or `verify.sh --quick` for intermediate commits) before pushing.
5. **Synchronous Documentation**: Update `docs/memory-bank/`, human documentation (`documentation/`), and ADR (`scripts/new_adr.sh`) in the exact same PR as the code change.
6. **PR Review & Deployment Verification**: Open PR as draft, trigger review bots (`@coderabbitai review`, `@sentry review`), resolve all findings, ensure CI green on head SHA, squash-merge, and verify production deployment via `scripts/verify_deploy.sh` (HTTP 200 + bundle string checks).

## Project Standing Rules (Owner Directives)
1. **Everything is configurable from `/admin`; nothing user-facing is hard-coded.** A new label, switch, limit or piece of content gets an admin field (model + `admin_schema.dart` + `firestore.rules` + `tool/gen_seed.py` + tests).
2. **Never invent church content** (times, names, phones, doctors, photos). Unverified data stays `sample: true`; sources go in `docs/CONTENT_SOURCES.md`.
3. **Never run `seed_firestore.js --force` or the Seed workflow** on production without the owner's explicit OK — it overwrites admin edits. Do not seed `clinics` at all (it would recreate the 11 deleted sample clinics).
4. **Feature toggles**: Anything public belongs to a section in `Sections` and disappears everywhere when off (home, nav, drawer, footer, directory, sitemap, assistant prompt).
5. **Images are optional everywhere**; a card without an image looks exactly as before.
6. **Sentry (ADR-034)** via `ErrorReporting.capture`; never send form text, assistant questions, user ids, e-mails, IPs or query strings; the admin switch `settings/features.errorReporting` must keep working; replay off.
7. **Strings in `lib/core/l10n.dart` (`[ar, en]`)**, Arabic-first RTL. Time logic through `CairoTime` (Africa/Cairo).
8. **Documentation (ADR-035)**: `documentation/` (Arabic) and `docs/memory-bank/` are updated in the same PR as every feature change, using the real admin labels from `admin_page.dart`, `admin_schema.dart` and `l10n.dart`.
9. **Firestore rules budget (1,000 expressions)**: Keep new feature keys out of the legacy allow-list on large settings docs (`settings/features`); branch on `changed.hasOnly(legacyKeys)`. Use `'key' in changed` rather than `changed.hasAny(['key'])`. Always include worst-case whole-doc emulator tests.
10. **Deferred imports for secondary UI**: Multi-step guides, heavy bottom sheets, and secondary preference pages must use deferred loading (`deferred as ...`) with dedicated string tables to keep bundle growth within the +20 KB gzip budget.
11. **Argon Advisor (Advisory-Only Subagent)**: When encountering complex, hard, or high-risk tasks, invoke the Advisor subagent (using the Argon model) strictly for advice, design verification, and analysis. Never assign implementation tasks or file editing to the Advisor.
