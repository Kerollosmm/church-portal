# AGENTS.md — guide for coding agents

**Read [`docs/memory-bank/`](docs/memory-bank/00-README.md) first, and update it in the same PR as every change.**

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
   (Africa/Cairo); weekdays are ISO 1–7; times are `"HH:mm"`.
3. **A field change touches four places together**: model (`lib/domain/models.dart` / `features.dart`), admin schema
   (`lib/ui/admin/admin_schema.dart`), `firestore.rules`, seed (`tool/gen_seed.py`) — plus tests.
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

## Workflow

Branch from up-to-date `main` → change + tests + memory-bank update → PR → comment `@coderabbitai review` → CI
(`ci.yml`: analyze/test/build/seed-diff + rules emulator; `deploy.yml`: build + preview channel `pr-<n>`) green →
squash-merge → `main` auto-deploys Hosting + Firestore rules.

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
