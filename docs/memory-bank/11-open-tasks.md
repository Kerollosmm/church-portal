# 11 — Open tasks

Tick items off (or delete them) in the PR that completes them, and add new ones as you discover them.
Status as of 1 Nov 2026 (after PR #3).

## Infrastructure & security (owner: developer)

- [ ] **Re-save the service-account secret** `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` with only the JSON key
      (no trailing characters/second copy). The credentials action tolerates it but prints
      `::warning::Ignored N extra character(s)…`. Delete any local copy of the key afterwards.
- [ ] **reCAPTCHA v3 site key**: create it (domains `asafra-church-portal.web.app`, `asafra-church-portal.firebaseapp.com`,
      `localhost`), register the web app under App Check, set repo **variable** `RECAPTCHA_SITE_KEY`, redeploy `main`.
      Until then App Check is off on the live site and the assistant is hidden.
- [ ] Enforce App Check for **Firebase AI Logic** (console) once the key works; set a Gemini **request quota** (cost cap).
      Do not enforce App Check on Firestore before the key is live.
- [ ] **`production` environment required reviewers** (Settings → Environments) so live deploys and the Seed workflow
      (`force` can overwrite production data) need approval. Consider gating `deploy-rules` with the same environment.
- [ ] **iOS**: register the iOS app (bundle `com.asafrachurch.churchPortal`), `flutterfire configure`, replace the
      placeholders in `lib/firebase_options.dart`; App Attest for App Check.
- [ ] **Android release signing**: add an upload keystore + `signingConfigs.release` (currently signs release with the
      debug key in `android/app/build.gradle.kts`); register SHA-256 for Play Integrity; consider replacing the
      browser API key with the Android `current_key`; app label is "Church Portal" (consider the Arabic name);
      Play Store listing ($25 account).
- [ ] Decide **Spark vs Blaze**: business case recommends Blaze + $5/month budget alert (Spark's 360 MB/day Hosting
      and 50K reads/day can be exhausted on busy summer days).
- [ ] Bootstrap at least **two owners** in `admins` (avoid single-person dependency); Firebase project ownership by a
      church Google account with 2-step verification.
- [ ] Firestore backups/exports schedule (needs Blaze) before any `--force` seeding.

## Content (owner: church office — see `09-content-status.md`)

- [ ] Real liturgy/vespers/praise timetable (47 placeholders), meetings (11), clinics (11 — or remove the section),
      facilities (4), priest roster confirmations, altars, photos (hero + priests), founding year.
- [ ] Re-date seasons/alerts every year (2027 Nativity, revivals, Holy Week/Pascha seeded; 2028 not yet).
- [ ] Mirror confirmed content into `tool/gen_seed.py` + `docs/CONTENT_SOURCES.md`.

## Product gaps vs. requirements (see `02-business-case.md`)

- [ ] Privacy notice + **consent checkbox** on the contact form; retention clean-up (12 months; TTL needs Blaze);
      legal check on PDPL / cross-border transfer.
- [ ] **Analytics** (Firebase Analytics or similar) with the KPI events (`answer_visible`, `clinic_call`,
      `clinic_whatsapp`, `call_church`, `open_maps`, `whatsapp_channel`, `contact_submit_success`, `lang_switch`).
- [ ] SEO/static shell: JSON-LD `Church`, `sitemap.xml`, `robots.txt` (disallow `/admin`, `noindex`), Open Graph
      image; optional pre-rendered "today's masses" snapshot.
- [ ] Performance budget (Lighthouse in CI), font subset/bundling (fonts are fetched at runtime now), deferred imports
      for `/admin` and the assistant.
- [ ] Footer: phones, socials, "last updated".
- [ ] Persist language choice on the device (currently only `?lang=en`).
- [ ] Meetings "today" badge (FR-E-03); clinics/meetings freshness view in admin (FR-AD-06); "simulate now" next-mass
      preview for editors (FR-AD-03); "open on site" links using `CollectionDef.publicPath` (unused).
- [ ] PWA install prompt, floating *Live now* / *Doctors' times* buttons (v1.1).
- [ ] v2 ideas: FCM push alerts, daily synaxarium line, `.ics` export, live-stream embed.
- [ ] Consider an inbox "spam" status (business case) and owner-only settings (ADR-011) if the church asks.

## Docs

- [ ] Keep this memory bank current with every PR (see `00-README.md`).
