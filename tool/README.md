# tool

## Overview
The `tool` component package encompasses administrative, content generation, data pipeline, and deployment automation tools for the digital parish portal. It contains scripts and utilities implemented in Node.js, Python, Bash, and Dart that maintain reproducible seed data, synchronize liturgical Katameros readings and Synaxarium commemorations, build and validate SEO sitemaps, generate responsive branding assets, fingerprint web icon fonts to prevent stale browser caching, assemble Android APK release manifests, atomically publish updates to Firebase Hosting, and seed Cloud Firestore safely with strict non-clobber invariants. It also houses the emulator-based security rules test suite.

## Interface
- **Sitemap Pipeline:**
  - `[tool/build_sitemap.sh]`: Release script orchestrating public content export, sitemap generation, and XML validation (`build_sitemap.sh`), preserving the static fallback `web/sitemap.xml` on any failure.
  - `[tool/export_public_content.js:plain]`: Recursive normalization function converting Firestore values (Timestamps to ISO-8601 strings, GeoPoint to coordinate maps, DocumentReference to path strings).
  - `[tool/export_public_content.js:withTimeout]`: Promise timeout wrapper enforcing 30-second read limits on collection fetches.
  - `[tool/gen_sitemap.dart:main]`: Dart entry point reading exported JSON and bundled seed features to produce `sitemap.xml` via `sitemapContentFromExport` and `sitemapPaths`.
- **Liturgical & Scriptural Pipelines:**
  - `[tool/fetch_readings.js:BIBLE_BOOKS_EN]`: 66-book mapping table translating biblical book indices to English canonical book titles.
  - `[tool/fetch_readings.js:parseKatamerosDay]`: Normalizer converting raw Katameros JSON payloads into canonical `DayReadings` structures.
  - `[tool/fetch_readings.js:cairoToday]`: Computes UTC midnight timestamp corresponding to today's calendar date in Cairo (`Africa/Cairo`).
  - `[tool/fetch_readings.js:parseDaysArg]`, `[tool/fetch_readings.js:argValue]`: CLI argument parsers for day windows and target directories.
  - `[tool/fetch_synaxarium.js:copticDateOf]`: Computes Coptic calendar date (`D/M/YYYY`) from a Gregorian date using the Julian Day Number algorithm (aligned with `CopticDate.fromGregorian`).
  - `[tool/fetch_synaxarium.js:fetchDay]`: Queries Katameros API for day commemorations with Arabic and English bilingual parity.
  - `[tool/gen_daily_verses.py:load_zip]`: Downloads or loads ZIP archives and validates cryptographic SHA-256 digests.
  - `[tool/gen_daily_verses.py:parse_vpl]`: Parses Verse-Per-Line (VPL) scripture files into verse reference maps.
  - `[tool/gen_daily_verses.py:main]`: Compiles `assets/verses/daily_verses.json` with 366 verses for daily rotation.
- **Branding & Web Asset Utilities:**
  - `[tool/gen_branding.sh:shrink]`: ImageMagick Lanczos downscaling utility with size-specific unsharp masks.
  - `[tool/gen_branding.sh:onbg]`: Compositing function centering artwork on colored/transparent canvases for adaptive icons.
  - `[tool/fingerprint_icon_fonts.py:fingerprint]`: Hashes subsetted icon fonts (`MaterialIcons-Regular.otf`, `CupertinoIcons.ttf`) with SHA-256 and updates `assets/FontManifest.json`.
- **Release & Data Seeding:**
  - `[tool/make_apk_manifest.mjs:readPubspecVersion]`: Parses `version: x.y.z+n` strings from `pubspec.yaml`.
  - `[tool/make_apk_manifest.mjs:resolveDownloadUrl]`: Rewrites GitHub release asset links into immutable tag URLs or direct URLs.
  - `[tool/make_apk_manifest.mjs:detectApkAbi]`: Maps APK file names to target ABI architectures (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
  - `[tool/make_apk_manifest.mjs:buildManifest]`: Compiles release metadata, file sizes, and SHA-256 checksums into `version.json`.
  - `[tool/publish_hosting_file.js:buildFileMap]`: Constructs remote-to-local path maps for version deployment.
  - `[tool/publish_hosting_file.js:buildExcludeRegexes]`: Creates regex patterns to purge stale resources in version clones.
  - `[tool/publish_hosting_file.js:run]`: Clones current live Firebase Hosting version, stages new files, and finalizes release atomically.
  - `[tool/gen_seed.py]`: Generates `assets/seed/seed.json`, tracking retired seed IDs in `tool/retired_seed_ids.json` and historical IDs in `tool/known_seed_ids.json`.
  - `[tool/seed_firestore.js:missingFields]`: Recursively computes difference between seed data and existing Firestore documents.
  - `[tool/seed_firestore.js:convert]`: Transforms ISO date strings to Firestore `Timestamp` objects.
  - `[tool/seed_firestore.js:main]`: Uploads seed data with `--dry-run`, `--force`, `--fill-missing`, and `--only` safety gates.
- **Subdirectories & Boundaries:**
  - `./rules_test`: Firestore security rules testing harness running against Firebase Local Emulator (`tool/rules_test/rules.test.mjs`).

## Invariants
- `[tool/seed_firestore.js:main]`: Never overwrite production admin edits by default; skips existing documents unless explicitly executed with `--force` or `--fill-missing`. The flags `--force` and `--fill-missing` are mutually exclusive.
- `[tool/gen_seed.py]`: Every ID ever created in seed datasets must be tracked in `tool/known_seed_ids.json`. Any ID removed from `assets/seed/seed.json` must be explicitly recorded in `tool/retired_seed_ids.json`.
- `[tool/gen_seed.py:settings]`: Content awaiting church office confirmation must strictly specify `sample: true` per `docs/CONTENT_SOURCES.md`.
- `[tool/build_sitemap.sh:fallback]`: The sitemap build step must never break deployment; on network timeout, credential absence, or validation error, it emits a warning and keeps the static fallback `web/sitemap.xml`.
- `[tool/gen_daily_verses.py:load_zip]`: Scripture archives must match hardcoded SHA-256 checksums (`SRC_SHA256`, `EN_SHA256`) before extracting text.
- `[tool/publish_hosting_file.js:run]`: Live hosting releases must be atomic; any failure during file cloning or upload aborts the version release and leaves the existing deployment untouched.
- `[tool/fetch_readings.js:cairoToday]`, `[tool/fetch_synaxarium.js:cairoToday]`: All liturgical date windows and Katameros queries must be pegged to Africa/Cairo midnight.

## Side Effects
- Modifies local files: overwrites `assets/seed/seed.json`, `tool/known_seed_ids.json`, `tool/retired_seed_ids.json`, `assets/verses/daily_verses.json`, `assets/FontManifest.json`, `build/web/sitemap.xml`, and image assets in `assets/branding/`, `web/`, and `android/app/src/main/res/`.
- Network operations:
  - Queries `https://api.katameros.app/readings/gregorian/...` for readings and commemorations.
  - Downloads scripture ZIP files from `https://ebible.org/Scriptures/...`.
  - Invokes Google Firebase Hosting v1beta1 REST APIs to create, populate, and release site versions.
  - Reads and writes Cloud Firestore databases via the Firebase Admin SDK.
- Process spawning: invokes `curl`, `magick` (ImageMagick), `python3`, `node`, and `dart` subprocesses.

## Verification
- Run: `python3 tool/gen_seed.py && cd tool/rules_test && npm test`
