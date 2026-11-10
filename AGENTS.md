# AGENTS.md — guide for coding agents

**Read [`docs/memory-bank/`](docs/memory-bank/00-README.md) first, and update it in the same PR as every change.**
**Human documentation (English): [`documentation/en/`](documentation/en/README.md)** — Architecture, operations, master feature reference.
**Human manual (Arabic): [`documentation/`](documentation/README.md)** — one file per feature + `operations.md`;
update it in the same PR as any feature change (golden rule 11).

## What this is

Public, Arabic-first (RTL) + English portal for the Coptic Orthodox **Church of Saints Maximus & Domadius and the Strong
Anba Moussa the Black** (كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود), end of Street 45,
El-Asafra Qebly, Alexandria. Flutter (web + Android, iOS-ready) + Firebase (Firestore, Hosting, Auth for admins only,
App Check, Firebase AI Logic/Gemini). Live: <https://maximos-domadios-church.web.app> (Hosting site `maximos-domadios-church`; the old
`asafra-church-portal.web.app` 301-redirects there) · Firebase project `asafra-church-portal` · hidden admin at `/admin`.
Branding: the parish seal in `assets/branding/` — regenerate every icon with `tool/gen_branding.sh` (ADR-018). It is a light public directory, **not** a church management system.

## Golden rules

1. **Never invent church content** (times, names, phones, doctors, photos). Unverified data stays `sample: true`;
   sources go in `docs/CONTENT_SOURCES.md`.
2. **Business logic is pure Dart in `lib/domain/`** with unit tests. All time logic goes through `CairoTime`
   (Africa/Cairo); weekdays are ISO 1–7; times are `"HH:mm"`. Recurring reminders («كل مرة») never expire and roll forward weekly in Cairo time; lead times must clamp to valid future intervals.
3. **A field change touches four places together**: model (`lib/domain/models.dart` / `features.dart`), admin schema
   (`lib/ui/admin/admin_schema.dart`), `firestore.rules`, seed (`tool/gen_seed.py`) — plus tests.
   **Firestore rules budget (1,000 expressions):** Keep new feature keys out of the legacy allow-list on large settings docs (`settings/features`); branch on `changed.hasOnly(legacyKeys)` so standard saves never evaluate new schemas. Use `'key' in changed` rather than `changed.hasAny(['key'])`. Always include worst-case whole-doc emulator tests.
4. **The seed is generated**: edit `tool/gen_seed.py`, run `python3 tool/gen_seed.py`, commit `assets/seed/seed.json`
   and `tool/known_seed_ids.json`/`retired_seed_ids.json`. Removing a seeded id ⇒ add it to `retired`.
5. **Strings** go in `lib/core/l10n.dart` (`[ar, en]`); content renders with `context.pick(ar, en)`; import widgets
   from `package:material_ui/material_ui.dart`.
6. **Feature toggles**: anything public belongs to a section in `Sections` and must disappear when it is off
   (home, nav, drawer, footer, directory, assistant prompt).
7. **Security**: never commit secrets (service-account JSON, keys). Never run `seed_firestore.js --force` / the Seed
   workflow with `force` on production without explicit approval — it overwrites admin edits.
8. Keep `flutter analyze` clean and all tests green; PRs are squash-merged after CI passes.
9. **Images are optional** everywhere (`image` map, `media/{id}` inline bytes on the Spark plan — ADR-017). A card
   without an image must look exactly as before; never make an image required or seed one.
10. **Error reports (Sentry, ADR-034)** go through `ErrorReporting.capture(e, st, section: …)` — never send form text,
   assistant questions, user ids, e-mails, IPs or query strings; the admin switch `settings/features.errorReporting`
   must keep working (`beforeSend` returns null when off).
11. **Documentation (ADR-035):** a PR that adds, removes or changes a feature, an admin screen / switch, a workflow or
   an operational step also updates the matching Arabic file in `documentation/` (feature files, `architecture.md`,
   `operations.md`, index in `documentation/README.md`) — in the same PR, like the memory bank. Write it in simple
   Arabic; keep code identifiers, paths and collection / field names in English; use the real admin labels from the
   code (`admin_page.dart`, `admin_schema.dart`, `lib/core/l10n.dart`).
12. **Deferred imports for secondary UI:** Multi-step guides (e.g. sideload install guides), heavy bottom sheets, and secondary preference pages must use deferred loading (`deferred as ...`) with dedicated string tables to keep bundle growth within the +20 KB gzip budget.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                                # sandbox/proxy: NO_PROXY=127.0.0.1,localhost flutter test
flutter run -d chrome                       # runs on bundled seed data if Firebase is unreachable
flutter build web --release                 # [--dart-define=RECAPTCHA_SITE_KEY=...]
python3 tool/gen_seed.py                    # regenerate seed (CI fails if out of date)
cd tool/rules_test && npm ci && npm test    # Firestore rules tests in the emulator (Java 11+)
cd tool && npm install && node seed_firestore.js --dry-run
```

## Workflow (Hark Workflow — Mandatory & Auto-Enabled)

This repository strictly follows the **Hark Workflow (`hark-workflow`)** engineering loop for all development tasks. Agents must automatically adopt the `orchestrator` persona and trigger the corresponding skill without requiring explicit reminders:

- **Features / Changes**: Use the `/ship-change` skill end-to-end.
- **Bug Fixes**: Use the `/fix-bug` skill (reproduction test first → identify root cause → fix cause → verify fix → regression locked).
- **Documentation**: Use the `/docs-sync` skill (keep `docs/memory-bank`, `documentation/`, and ADR in sync in the same PR).
- **PR Review Loop**: Use the `/pr-review-loop` skill (`@coderabbitai review`, `@sentry review`, resolve threads).
- **Release Verification**: Use the `/verify-release` skill (verify CI on head SHA, squash-merge, monitor deploy jobs, verify live HTTP 200 and bundle strings).

### The Strict Execution Pipeline:
1. **Intake & Acceptance Plan**: Restate goal; verify against `AGENTS.md`, `.agents/rules/project-rules.md`, and memory bank; initialize `.work/<branch>/status.md` with checkable acceptance criteria before touching code.
2. **Branch**: Isolated branch (`feat/`, `fix/`, `docs/`, `chore/`) or `git worktree`. Never commit or push directly to `main`. Never force-push.
3. **Test-First Implementation**: Pure business logic in `lib/domain/` with unit tests; UI responsive across 320/400/1400 px; RTL/LTR and switch states covered.
4. **Local Gate**: Must pass `scripts/verify.sh` locally before push (`verify.sh --quick` runs on every commit via hook).
5. **Docs in Same PR**: Update `docs/memory-bank/`, `documentation/` (Arabic), and add an ADR (`scripts/new_adr.sh`).
6. **PR Review & Merge**: Open draft PR, run review bot triage, verify CI on head SHA, squash-merge.
7. **Deploy Verification & Smoke**: Verify deploy workflow run on merge SHA, live HTTP 200, and JS bundle regex assertions (`verify_deploy.sh`).
8. **Owner Report**: Submit concise report in `.work/<branch>/status.md` using the standard reporting format.

## Where to look

| Need | File |
|---|---|
| Overview / index | `docs/memory-bank/00-README.md` |
| Architecture, routes, providers | `docs/memory-bank/03-architecture.md` |
| Firestore fields & flags | `docs/memory-bank/04-data-model.md` |
| Rules, Hosting, App Check, Gemini | `docs/memory-bank/05-firebase.md` |
| Pages & business rules | `docs/memory-bank/06-features.md` |
| Admin dashboard | `docs/memory-bank/07-admin-dashboard.md` |
| Dev workflow, CI/CD, "add a section" checklist | `docs/memory-bank/08-dev-workflow.md` |
| Content verified vs pending | `docs/memory-bank/09-content-status.md` |
| Decisions & history | `docs/memory-bank/10-decisions-and-history.md` |
| Open tasks | `docs/memory-bank/11-open-tasks.md` |
| Church terms | `docs/memory-bank/12-glossary.md` |
| English documentation suite (Architecture, Operations, Features) | `documentation/en/README.md` |
| Arabic feature manual (owner / church office) | `documentation/README.md` |
| Deploy, admins, seed safety, Sentry, common problems (Arabic) | `documentation/operations.md` |
