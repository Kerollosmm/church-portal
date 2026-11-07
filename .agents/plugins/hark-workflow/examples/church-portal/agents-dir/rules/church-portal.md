---
trigger: always_on
description: "church-portal code and content rules (owner Kerollos). They override plugin defaults. Process rules: .agents/AGENTS.md."
---

# church-portal — code and content rules

1. **Business logic is pure Dart in `lib/domain/`** with unit tests. All time logic through `CairoTime`
   (Africa/Cairo; never `DateTime.now().weekday` directly); weekdays ISO 1–7; times `"HH:mm"`.
2. **A field change touches four places together**: model (`lib/domain/models.dart` / `features.dart`), admin schema
   (`lib/ui/admin/admin_schema.dart`), `firestore.rules`, seed (`tool/gen_seed.py`) — plus tests (rules suite in
   `tool/rules_test/rules.test.mjs` with allow AND deny cases, legacy writes of main's admin included).
3. **The seed is generated**: edit `tool/gen_seed.py`, run it, commit `assets/seed/seed.json` +
   `tool/known_seed_ids.json` / `retired_seed_ids.json` (gate step `seed` fails on drift). Removing a seeded id ⇒ add
   it to `retired`. Never seed `clinics` (it would bring back deleted sample clinics).
4. **Strings** in `lib/core/l10n.dart` (`[ar, en]`), content via `context.pick(ar, en)`; widgets from
   `package:material_ui/material_ui.dart`; colours only from palette roles (`context.pal.*`), no violet.
5. **Feature toggles**: anything public belongs to a section in `Sections` and disappears everywhere when off (home,
   nav, drawer, footer, directory, sitemap, assistant prompt).
6. **Images are optional** everywhere (`image` map, `media/{id}` inline bytes on Spark — ADR-017). A card without an
   image looks exactly as before; never make an image required or seed one.
7. **Sentry (ADR-034)** through `ErrorReporting.capture(e, st, section: …)`; never send form text, assistant questions,
   user ids, e-mails, IPs or query strings; the admin switch `settings/features.errorReporting` must keep working
   (`beforeSend` returns null when off); replay off.
8. **Never invent church content** (times, names, phones, doctors, photos). Unverified data stays `sample: true`;
   sources go in `docs/CONTENT_SOURCES.md`.
9. **Docs in the same PR (ADR-035)**: `docs/memory-bank/`, the Arabic `documentation/` file (simple Arabic, real admin
   labels from `admin_page.dart`, `admin_schema.dart`, `l10n.dart`), `documentation/en/`, the ADR + timeline row.
10. Keep `flutter analyze` clean and every test green; never skip or delete a test to get green.
