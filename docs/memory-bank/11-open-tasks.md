# 11 — Open tasks

Tick items off (or delete them) in the PR that completes them, and add new ones as you discover them.
Status as of 3 Nov 2026 (after PR #19; earlier: PR #7–#18).

## Infrastructure & security (owner: developer)

- [ ] **Re-save the service-account secret** `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` with only the JSON key
      (no trailing characters/second copy). The credentials action tolerates it but prints
      `::warning::Ignored N extra character(s)…`. Delete any local copy of the key afterwards.
- [x] **reCAPTCHA Enterprise site key** "church-portal-web" created, web app registered under App Check (reCAPTCHA
      Enterprise provider), repo variable `RECAPTCHA_SITE_KEY` set, AI Logic App Check **Enforced** (Nov 2026);
      the app uses `ReCaptchaEnterpriseProvider` since PR #19.
- [ ] Optional: set a Gemini **request quota** for Firebase AI Logic (console). On Spark the Developer API free tier
      is rate-limited and never billed. Do not enforce App Check on Firestore while Android release has no Play
      Integrity registration.
- [ ] **Android App Check (owner, manual — PR #19):** (1) create a release signing key (`keytool -genkey -v -keystore
      upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`) and wire `signingConfigs.release`
      in `android/app/build.gradle.kts` (keystore + passwords outside git); (2) copy its **SHA-256** (`keytool -list -v
      -keystore upload-keystore.jks -alias upload`; with Play App Signing use the *app signing key* SHA-256 from Play
      Console → App integrity); (3) Firebase console → Project settings → Android app `com.asafrachurch.church_portal`
      → Add fingerprint; (4) App Check → Apps → Android → **Play Integrity** → Register (link the Cloud project in
      Play Console → App integrity). **Debug APKs:** run once, copy the debug token from logcat ("Enter this debug
      secret into the allow list…") into App Check → Apps → ⋮ → Manage debug tokens (or build with
      `--dart-define=APPCHECK_DEBUG_TOKEN=<uuid>` registered there). Until then Android assistant requests are refused.
- [ ] **`production` environment required reviewers** (Settings → Environments) so live deploys, rules deploys
      (`deploy-rules` uses the environment since PR 1) and the Seed workflow (`force` can overwrite production data)
      need approval.
- [ ] **iOS**: register the iOS app (bundle `com.asafrachurch.churchPortal`), `flutterfire configure`, replace the
      placeholders in `lib/firebase_options.dart`; App Attest for App Check. (`Info.plist` already has
      `NSPhotoLibraryUsageDescription` for the admin image picker.)
- [ ] **Android release signing**: add an upload keystore + `signingConfigs.release` (currently signs release with the
      debug key in `android/app/build.gradle.kts`); register SHA-256 for Play Integrity; consider replacing the
      browser API key with the Android `current_key`; app label is now «كنيسة مكسيموس ودوماديوس» with seal launcher icons (PR #6);
      Play Store listing ($25 account).
- [ ] Decide **Spark vs Blaze**: business case recommends Blaze + $5/month budget alert (Spark's 360 MB/day Hosting
      and 50K reads/day can be exhausted on busy summer days).
- [ ] Bootstrap at least **two owners** in `admins` (avoid single-person dependency); Firebase project ownership by a
      church Google account with 2-step verification.
- [ ] Firestore backups/exports schedule (needs Blaze) before any `--force` seeding.
- [ ] **Optional: move uploaded images to Cloud Storage** once on Blaze — implement `StorageMediaRepository`, deploy
      `storage.rules`, build with `MEDIA_BACKEND=storage` (steps in ADR-017). Until then images are inline in
      Firestore `media/` (fine at parish scale; watch the 50K reads/day).
- [ ] **Orphaned `media` docs:** deletes are best effort; add a small owner-only "clean up unused images" action or a
      script (list `media` ids not referenced by any `image.mediaId`) if they accumulate.

- [ ] **Browser-target test for `applyDocumentHead`** (`lib/core/document_lang_web.dart`): the Dart VM tests only
      check the `DocumentHeadSpec` passed to `debugOnRouteMeta`, not the `<link rel="canonical">` /
      `<meta name="robots">` written to `document.head`. Needs a `@TestOn('browser')` test and a
      `flutter test --platform chrome` CI job (CodeRabbit nitpick on PR #10, deferred).

- [ ] **Custom domain (optional)**: if the church buys a domain, add it to Hosting site `maximos-domadios-church`
      (console → Hosting → Add custom domain), add it to Auth authorized domains, and update OG/robots/
      sitemap URLs and the redirect destination in `firebase.json` (ADR-018).
- [x] ~~Home page overflows by ~8 px at **320 px** width~~ — the app bar was the culprit (BUG-11 #1); below 360 px
      the highlight buttons now move to the drawer, and `test/accessibility_test.dart` renders every public route at
      320 px × 200 % text without overflow (Flutter test font). Still worth one look on a real 320 px phone with the
      Cairo font.
- [ ] Ask the church office to update the admin-editable English name (`settings/church.nameEn`, currently "Church of
      Saints Maximus & Domadius and the Strong Anba Moussa the Black") if they prefer "St. Maximus & Domadius and
      St. Moses the Black Church" — not changed by the seed to avoid overwriting admin edits.

## Customization plan (PRs #11–#13, ADR-020)

- [ ] **Run `node tool/seed_firestore.js --fill-missing`** (Seed workflow without `force`, needs approval) after PR #11
      deploys, so production `settings/features` gets `pageHeaders: {}` and the default `footer` map. Optional: missing
      = defaults, and the first save in /admin → Sections writes them too.
- [x] **PR #12 — admin studio** (grouped `DocEditor`, gallery editor, split saves, Page headers + Footer cards).
- [ ] Media orphans: when a later write of a split save fails, images orphaned by the earlier writes (e.g. a replaced
      cover) are kept until the save completes — a retry deletes them (`_saveBaseline`, PR #12 review fix). Only if
      the admin abandons the editor after a failed write do they stay — covered by the existing manual `media`
      clean-up task.
- [x] **PR #13 — public pages:** detail routes, `ItemDetailPage`, card integration, custom page headers/intros,
      footer upgrade (closes FR-G-04), memory-bank sync.
- [ ] Optional: a site-wide **"last updated"** line in the footer (FR-G-04 wording) — see *Footer* under product
      gaps below.
- [x] **PR #14 — detail pages on by default:** opt-out `detailsEnabled`, labelled key facts, add-to-calendar,
      directions, share, related items, admin hint (ADR-021).
- [ ] Optional: add detail URLs to `web/sitemap.xml` (every visible item has one since PR #14; the sitemap is static,
      so it needs a build-time generator or a manual list).
- [ ] Optional: native share sheet (Web Share API) on mobile instead of copy-link (needs a web-only plugin/JS interop).

## "Golden hour" identity (PR #15, merged 3 Nov 2026; ADR-022 revised / ADR-023)

- [x] Team approval of the "Golden hour" identity (approved 3 Nov 2026; burgundy preset is `#6E1C1C`).
- [x] Hero video loop on by default (`heroMotion`), phones included (portrait crop, ~110 KB); save-data and reduced
      motion still turn it off.
- [ ] Confirm the image style defaults (priests & clinics avatar; saints portrait card; the rest card).
- [ ] The Gemini art is decorative AI-painted imagery; confirm the church is happy to publish it (it never replaces
      real photos).
- [ ] Masonry vs equal-height rows in the grid (now: each card keeps its own height, rows top-aligned).

## Verse of the day (PR #16, ADR-024)

- [x] 366 Van Dyck verses bundled (eBible.org, public domain, SHA-pinned), Cairo-day rotation, admin on/off + fixed verse.
- [ ] Optional: let the church office review / reorder the 366 references (`tool/daily_verse_refs.txt`, then
      `python3 tool/gen_daily_verses.py`), e.g. to follow the Coptic calendar or feasts.
- [ ] Optional: CI source-fidelity step (download the SHA-pinned eBible zip, run `tool/gen_daily_verses.py`, fail on
      a diff). Skipped in PR #16 to keep CI free of a network dependency; a test checks the asset's `sourceSha256`.
- [ ] Optional: an English verse alongside (a public-domain English translation such as KJV/WEB would need its own
      verified source); today the English UI shows the Arabic verse with an English reference.

## Occasion themes & hero videos (PR #17, ADR-025/026)

- [x] Theme presets, Cairo-date schedule, Coptic Easter, admin colour edits with contrast auto-correction, YouTube
      hero video library with bundled-clip fallback, verse of the day in the hero.
- [ ] Church office: confirm the Holy Week / Resurrection looks and the default Resurrection length (7 days), and
      add the Nativity / fasts / Marian ranges each year (or ask for fixed-date presets such as 7 Jan / 19 Jan /
      the Marian feasts to be computed like Easter).
- [ ] Manually check YouTube playback on a real phone browser and the Android app (autoplay policies; headless tests
      cannot play it).
- [ ] Optional: `settings/church.verseAr/En` are no longer shown publicly — retire them from the admin form or reuse
      them (e.g. a parish motto).
- [ ] Optional: a dark theme for the admin dashboard (it keeps Golden hour).

## Custom sections, pages & contact types (PR #18, ADR-027/028)

- [x] Admin-defined categories with items and their own pages + menu entries; custom pages (blocks incl. donation
      info) linked from notices; contact types with hall booking, anonymous complaints / suggestions, inbox boxes,
      booking status and notes.
- [ ] Church office: create the donations page for the new building (account / InstaPay / wallet details) and
      confirm the contact types and booking occasions.
- [ ] Optional: let built-in sections and custom categories share one menu order (built-ins come first today).
- [ ] Optional: detail pages for custom items (cards show the full description today).
- [ ] Optional: add custom sections / pages to `web/sitemap.xml` (static file). (Assistant grounding done in PR #19.)
- [x] Never reuse a deleted contact-type id (PR #19: stable random ids).

## Content (owner: church office — see `09-content-status.md`)

- [ ] Real liturgy/vespers/praise timetable (47 placeholders), meetings (11), clinics (11 — or remove the section),
      facilities (4), priest roster confirmations, altars, photos (hero; priests/saints/activities can now be added
      in /admin — optional, only with the church's permission), founding year.
- [ ] Re-date seasons/alerts every year (2027 Nativity, revivals, Holy Week/Pascha seeded; 2028 not yet).
- [ ] Mirror confirmed content into `tool/gen_seed.py` + `docs/CONTENT_SOURCES.md`.

## Product gaps vs. requirements (see `02-business-case.md`)

- [ ] Retention clean-up of contact messages (12 months; TTL needs Blaze); legal check on PDPL / cross-border
      transfer and on the privacy-notice wording. (Notice + consent checkbox done in PR 3 of the review plan.)
- [ ] **Analytics** (Firebase Analytics or similar) with the KPI events (`answer_visible`, `clinic_call`,
      `clinic_whatsapp`, `call_church`, `open_maps`, `whatsapp_channel`, `contact_submit_success`, `lang_switch`).
- [ ] SEO/static shell: optional pre-rendered "today's masses" snapshot. (`Church` JSON-LD done in PR 3; keep it in
      sync with `settings/church`.) (`web/robots.txt` disallowing `/admin`, `web/sitemap.xml` and the Open Graph image
      `web/og-image.jpg` shipped in PR #6; per-route canonical + `noindex` on `/admin`, 404 and switched-off sections
      done in PR #10 — crawlers that do not run JS still see the static `/` canonical.) When clinics go live,
      uncomment `/clinics` in `web/sitemap.xml`.
- [ ] Performance budget (Lighthouse in CI), font subset/bundling (fonts are fetched at runtime now). (Deferred
      `/admin` and `/ask` chunks done in PR 3 of the review plan; verify lazy loading in the Network tab on the
      preview.)
- [ ] Footer: "last updated" (optional; needs a tracked timestamp — phones and socials done in PR #13).
- [ ] Persist the language choice on Android/iOS too (web uses `localStorage` since PR 3 of the review plan; native is
      a no-op to avoid a new dependency).
- [ ] Clinics/meetings freshness view in admin (FR-AD-06); "simulate now" next-mass preview for editors (FR-AD-03).
      (Meetings "today" badge FR-E-03 and admin "Open on site" via `CollectionDef.publicPath` done in PR 2 of the
      review plan.)
- [ ] Manual accessibility pass with TalkBack / VoiceOver on a real phone (automated checks live in
      `test/accessibility_test.dart`); the admin dashboard still uses fixed burgundy instead of the theme preset.
- [ ] PWA install prompt, floating *Live now* / *Doctors' times* buttons (v1.1).
- [ ] v2 ideas: FCM push alerts, daily synaxarium line, `.ics` export, live-stream embed.
- [ ] Consider an inbox "spam" status (business case) and owner-only settings (ADR-011) if the church asks.

## Docs

- [ ] Keep this memory bank current with every PR (see `00-README.md`).

## Assistant follow-ups (PR #21, ADR-031)
- [ ] Optional: on the Blaze plan, enable Grounding with Google Search restricted to `sourceDomains` (filter
      citations by `web.title`, show source links + the required Search-suggestions widget) instead of the search link.
- [ ] Optional: set the Firebase AI Logic per-user rate limit in the console (server-side; the daily device limit is
      client-side only and resets when site data is cleared).
