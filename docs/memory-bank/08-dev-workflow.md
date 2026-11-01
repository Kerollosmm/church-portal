# 08 — Development workflow

## Local setup

```bash
flutter --version            # stable channel (README: built with Flutter 3.47 / Dart 3.13; pubspec sdk ^3.13.7)
flutter pub get
flutter analyze
flutter test
flutter run -d chrome        # or: flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
flutter build web --release  # -> build/web (what Hosting serves)
```

- **Codespaces / devcontainer** (`.devcontainer/`): Ubuntu 24.04 + Node 20 + gh; `post-create.sh` clones Flutter
  stable to `~/flutter`, enables web, installs `firebase-tools` and `flutterfire_cli`, runs `flutter pub get` and
  `npm install` in `tool/`. Ports 8080 (web-server), 4000 (Emulator UI), 8085, 9099.
- Without network/Firebase the app runs on `assets/seed/seed.json` (nothing to configure for UI work).
- Useful `--dart-define`s: `RECAPTCHA_SITE_KEY=…`, `GEMINI_MODEL=…`, `APPCHECK_DEBUG=true`,
  `APPCHECK_DEBUG_TOKEN=<uuid>` (debug builds use the App Check debug provider automatically),
  `MEDIA_BACKEND=firestore|storage` (where uploaded images go; `storage` needs Blaze + the steps in ADR-017).
- Android: `flutter run -d <device>`; release builds are still **signed with the debug key**
  (`android/app/build.gradle.kts`) — not Play-Store ready.

## Commands

| Task | Command |
|---|---|
| Static analysis | `flutter analyze` (lints: `package:flutter_lints/flutter.yaml`; excludes build/android/ios/web) |
| Unit + widget tests | `flutter test` (`test/domain_test.dart`, `features_test.dart`, `feature_gate_test.dart`, `admin_test.dart`, `seed_test.dart`, `media_test.dart`). In a proxied sandbox set `NO_PROXY=127.0.0.1,localhost` or the test runner cannot reach its local websocket. |
| Regenerate seed | `python3 tool/gen_seed.py` → writes `assets/seed/seed.json`, `tool/known_seed_ids.json`, `tool/retired_seed_ids.json` (commit all three) |
| Rules tests (emulator, Java 11+) | `cd tool/rules_test && npm ci && npm test` (runs `firebase emulators:exec --only firestore --project demo-church-portal`) |
| Seed preview | `cd tool && npm install && node seed_firestore.js --dry-run` |
| Deploy (manual) | `flutter build web --release [--dart-define=RECAPTCHA_SITE_KEY=…] && firebase deploy` (or `--only hosting`, `--only firestore:rules,firestore:indexes`) |

## Seeding Firestore (`tool/seed_firestore.js`)

Auth: `GOOGLE_APPLICATION_CREDENTIALS=/path/key.json` or `gcloud auth application-default login`.

| Flag | Effect | Danger |
|---|---|---|
| *(none)* | `create()` each doc; **existing docs are skipped** (admin edits are safe). `settings` written last. | Safe |
| `--dry-run` | Print what would happen (checks existence) | Safe |
| `--only a,b` | Restrict to collections (`settings`, `clinics,meetings`…; `none` = no content, e.g. with `--admin`) | — |
| `--fill-missing` | For existing docs, add only absent **top-level** fields, in a transaction (never changes existing values) | Low — but adds seed values (e.g. a new section key) to live docs |
| `--force` | **Overwrites whole documents** (batched `set`) **and deletes retired ids** (`retired_seed_ids.json`) unless edited in /admin (`updatedAt`/`updatedBy` present) | **HIGH — replaces everything edited in /admin for the seeded ids.** Never use on production without explicit approval and a backup/export |
| `--force` + `--fill-missing` | Refused (exit 2) | — |
| `--admin <uid>[:email]` | Create/merge `admins/{uid}` as **owner** | Grants full rights |
| `--admin-email <email>` | Find or create the Auth user, make it owner | Grants full rights |
| `--project <id>` | Default `asafra-church-portal` or `$GCLOUD_PROJECT` | — |

All dates are validated before the first write; `startsAt/endsAt/date/createdAt` strings → Timestamps.

### Seed workflow (`.github/workflows/seed.yml`, manual "Run workflow")
Runs in the **`production` environment** with the service-account secret. Inputs (passed via env, validated —
`only` must match `[a-z_,]`, email `[A-Za-z0-9@._+-]`):
- `admin` — `UID:email` → `--admin`.
- `admin_email` — `--admin-email`, then a step calls the Identity Toolkit `accounts:sendOobCode`
  (`PASSWORD_RESET`) with the public web API key so Firebase emails a set-password link.
- `only` — `--only`. `fill_missing` (bool) — `--fill-missing`. `force` (bool) — `--force` (**DANGER**, see above).
- Safe recipe after a release that adds new **top-level** settings fields (or to create `settings/features` if it is
  missing): `only=settings`, `fill_missing=true`. Nested keys (e.g. a new entry inside `sections`) are not added.

## CI/CD (`.github/workflows/`)

### `ci.yml` — every push (all branches) and PR; concurrency `ci-<ref>`, cancel in progress
Job **analyze-test-build** (ubuntu, 30 min): checkout → `subosito/flutter-action@v2` (stable, cached) →
`flutter --version` → `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build web --release` →
validate `seed.json` parses (node) → **`python3 tool/gen_seed.py` and `git diff --exit-code`** on `seed.json`,
`retired_seed_ids.json`, `known_seed_ids.json` (fails if you hand-edited the JSON or forgot to regenerate).
Job **firestore-rules** (15 min): Java Temurin 21 + Node 22 → `npm ci` in `tool/rules_test` → `npm test` (emulator).

### `deploy.yml` — push to `main` and PRs (`FIREBASE_PROJECT_ID=asafra-church-portal`)
1. **build** (skipped for fork PRs): Flutter stable → `pub get` → `flutter test` → `flutter build web --release`,
   with `--dart-define=RECAPTCHA_SITE_KEY` only on push builds when the repo variable is set → artifact `web-build`
   (3 days).
2. **deploy-live** (push to main, needs build, environment `production`, URL the live site): download artifact →
   Node 22 → `./.github/actions/firebase-credentials` → `npx firebase-tools@latest deploy --only hosting:app,hosting:legacy-redirect`
   (app → `maximos-domadios-church`, 301 redirect config → old site `asafra-church-portal`) → remove key.
3. **deploy-rules** (push to main, independent of build; references `environment: production` since PR 1 — rules
   deploys need approval only once required reviewers are configured on that environment, an open task in
   `11-open-tasks.md`): credentials → `deploy --only firestore:rules,firestore:indexes`.
4. **preview** (same-repo PRs, needs build): `hosting:channel:deploy pr-<n> --only app --expires 7d --json` → parse URL → upsert
   one PR comment "Firebase Hosting preview" (github-script).

### `.github/actions/firebase-credentials` (composite)
Normalises the service-account secret (first JSON object only, validates, `$RUNNER_TEMP/sa.json` 0600, exports
`GOOGLE_APPLICATION_CREDENTIALS`, never echoes) and primes firebase-tools' API-enablement cache (see `05-firebase.md`).

### Secrets & variables
| Name | Kind | Used by |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` | secret | deploy-live, deploy-rules, preview, seed |
| `RECAPTCHA_SITE_KEY` | repository **variable** (optional, not set yet) | live web build |
| Environment `production` | GitHub environment | deploy-live, seed — add **required reviewers** (open task) |

## PR process

1. `git checkout main && git pull`, then a branch: `feat/…`, `fix/…`, `content/…`, `docs/…`.
2. Make the change **with tests** and **memory-bank updates** (see `00-README.md` update rules).
3. Run `flutter analyze`, `flutter test`; if you touched rules or seed: `python3 tool/gen_seed.py` and the rules tests.
4. Push, open a PR to `main` (squash-merge is the norm; history so far: PR #1–#3 squashed).
5. Comment **`@coderabbitai review`** to trigger CodeRabbit. Address valid findings in follow-up commits (previous PRs
   ended with "Address CodeRabbit/Codex review" commits). CodeRabbit can be rate limited — don't block on it forever.
6. Wait for **CI** (`analyze-test-build`, `firestore-rules`) and **Deploy/build + preview** to be green; check the
   preview URL comment.
7. Squash-merge. The push to `main` deploys Hosting + rules automatically.
8. If the change needs data (new seeded docs or new top-level fields), run the Seed workflow with
   `only=<collection>` (+ `fill_missing=true` for existing docs) — never `force` on production without approval.

## Conventions

- Business logic in `lib/domain/` (pure Dart, no Flutter/Firebase imports) with unit tests; UI in `lib/ui/`.
- Import widgets from `package:material_ui/material_ui.dart`.
- All user-visible strings in `lib/core/l10n.dart` `_strings` (`[ar, en]`), Arabic first; content fields as `…Ar/…En`
  pairs rendered with `context.pick`. Times always via `TimeRangeText` / `time_format.dart`.
- Times `HH:mm`, weekdays ISO 1–7, all schedule math through `CairoTime` (never `DateTime.now().weekday` directly).
- Models' `fromMap` must be tolerant (wrong types → defaults; never throw on bad data).
- Never invent church content; unknown facts stay `sample: true` and are documented in `docs/CONTENT_SOURCES.md`.
- Seed changes only in `tool/gen_seed.py`; removing a seeded id ⇒ add it to `retired`.
- Line length ~120 (devcontainer ruler). Keep `flutter analyze` clean.
- Never commit credentials (`.gitignore` blocks service-account JSON files).
- **Adding an image to another collection:** add `'image'` to its rules allow-list (the `common()` check validates
  it), `_imageField` to its `CollectionDef`, `final MediaImage? image` + `MediaImage.fromMap(m['image'])` to the
  model, and wrap its card's icon in `ItemImage(placeholder: <current icon>)`; add it to `imageCollections`.

## Checklist — add a new section / collection end-to-end

Example: a new public collection `announcements` shown on `/news`.

1. **Model** — `lib/domain/models.dart`: class implementing `Hideable` (`visible` default true, `order`), tolerant
   `fromMap(id, map)`, optional `sample`.
2. **Section key** — `lib/domain/features.dart`: add to `Sections` (+ `all`, `labels`), to `routeSections` for the new
   route, optionally a `HomeBlocks` entry (+ `defaultOrder`, `labels`, `requires`).
3. **Repository** — `ContentRepository` method, `SeedRepository` (`seed.<name>`), `FirestoreRepository` (`_col`);
   `SeedData` getter in `seed_data.dart`.
4. **Provider** — `lib/state/providers.dart`: `StreamProvider` wrapped with `_public(...)`.
5. **Page & routing** — `lib/ui/pages/<name>_page.dart`; `GoRoute` in `router.dart` inside the `ShellRoute` (via
   `_page`); nav entry in `app_shell.dart` `navItems` (and Services menu indices if needed); directory card in
   `home_page.dart` `_directory`; footer links if relevant; `l10n` strings.
6. **Assistant** — add a block in `buildAssistantInstruction` guarded by `f.enabled(Sections.<key>)` (prefix
   `[UNCONFIRMED]` for sample items) and await the provider in `AssistantPage._awaitContent`.
7. **Admin** — `CollectionDef` in `admin_schema.dart` (fields, `titleKeys`, `orderable`, `icon`, `publicPath`); icon
   in `adminIcon`; choice labels `opt_*` in l10n if needed.
8. **Rules** — `firestore.rules`: add the collection to the public-read list, `validContent` list and dispatch,
   delete list; write `valid<Name>(d)` with `keysAllowed([...].concat(meta()))` + type/size checks; add the section key
   to `sectionKeys()` (and block key to `homeOrder`/`homeHidden` lists) in `validFeatures`.
9. **Seed** — `tool/gen_seed.py`: data dict + include in `seed` + section key in `settings.features.sections`;
   run `python3 tool/gen_seed.py`; commit `seed.json` + `known_seed_ids.json`.
10. **Tests** — domain tests for logic; `features_test.dart` (route guard); `feature_gate_test.dart` (page hidden when
    off); `admin_test.dart` passes the rules/schema cross-check; `tool/rules_test` cases (valid/invalid writes).
11. **Docs** — update `04-data-model.md`, `05-firebase.md`, `06-features.md`, `07-admin-dashboard.md`, README tables,
    `docs/CONTENT_SOURCES.md` (sources/status), `10-decisions-and-history.md` timeline.
12. **Deploy data** — after merge, Seed workflow `only=<name>` (creates the new docs). No migration is needed for the
    new section key: a missing key means "on", and `--fill-missing` only adds absent **top-level** fields (it will not
    add a key inside the existing `sections` map anyway).

## Branding assets

All logos/icons come from the parish seal: `tool/gen_branding.sh [new-seal-1024.webp|png]` (ImageMagick 7) rewrites
`assets/branding/seal.png` (in-app `ChurchSeal`), `web/favicon.{ico,png}`, `web/favicon-16.png`,
`web/icons/Icon-{192,512}.png`, `Icon-maskable-{192,512}.png` (seal at 78% on `#470812`), `apple-touch-icon.png`,
`web/og-image.jpg` (1200×630) and `android/.../mipmap-*/ic_launcher{,_foreground}.png` (+ adaptive icon XML,
background `@color/ic_launcher_background`). Commit the regenerated files. `test/branding_test.dart` checks the web
title/manifest/share tags, the files and the Hosting redirect config.
