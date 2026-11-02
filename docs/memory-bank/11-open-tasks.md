# 11 — Open tasks

Tick items off (or delete them) in the PR that completes them, and add new ones as you discover them.
Status as of 2 Nov 2026 (after PR #7, PR #8, PR #9 `ad621cf`, PR #10 and PR #11).

## Infrastructure & security (owner: developer)

- [ ] **Re-save the service-account secret** `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL` with only the JSON key
      (no trailing characters/second copy). The credentials action tolerates it but prints
      `::warning::Ignored N extra character(s)…`. Delete any local copy of the key afterwards.
- [ ] **reCAPTCHA v3 site key**: create it (domains `maximos-domadios-church.web.app`, `maximos-domadios-church.firebaseapp.com`,
      `localhost`), register the web app under App Check, set repo **variable** `RECAPTCHA_SITE_KEY`, redeploy `main`.
      Until then App Check is off on the live site and the assistant is hidden.
- [ ] Enforce App Check for **Firebase AI Logic** (console) once the key works; set a Gemini **request quota** (cost cap).
      Do not enforce App Check on Firestore before the key is live.
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

## Customization plan (PRs #12–#13, ADR-020)

- [ ] **Run `node tool/seed_firestore.js --fill-missing`** (Seed workflow without `force`, needs approval) after PR #11
      deploys, so production `settings/features` gets `pageHeaders: {}` and the default `footer` map. Optional: missing
      = defaults, and the first save in /admin → Sections writes them too.
- [ ] **PR #12 — admin studio:** detail fields in `admin_schema.dart` (detailKeys + `image` on meetings/clinics/
      facilities, `BR-11` hint on meetings), `FieldType.imageList` gallery editor with `orphanedDocMediaIds`, and
      `extractDocMediaIds` in `collection_list.dart` delete; Page Headers + Footer cards in `FeaturesEditor`.
      **Save `gallery` and `extraFields` each in their own update** (with the stamp): both full lists in one write
      exceed the rules' 1,000-expression cap (`05-firebase.md`).
- [ ] **PR #13 — public pages:** detail routes, `ItemDetailPage`, card integration, custom page headers/intros,
      footer upgrade (closes FR-G-04), memory-bank sync.

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
- [ ] Footer: phones, socials, "last updated".
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
