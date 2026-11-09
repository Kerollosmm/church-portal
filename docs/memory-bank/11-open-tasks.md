# 11 — Open tasks

Tick items off (or delete them) in the PR that completes them, and add new ones as you discover them.
Status as of 6 Nov 2026 (ADR-056 Phase 2 plan; ADR-055 / PR #49; ADR-054 / PR #48; ADR-053 / PR #47; PR #44 / ADR-051; PR #45 / ADR-050; PR #42 / ADR-049; PR #40 / ADR-047; PR #39 / ADR-046; PR #38 / ADR-045; PR #35 / ADR-044; PR #37 / ADR-043; PR #33 / ADR-042; PR #32 / ADR-041; PR #31 / ADR-039–040; PR #30 / ADR-038; PR #25 re-checked against `d60261d`; earlier: PR #7–#24).

## Top open items (owner's list, 4 Nov 2026 — details in the sections below)

1. ~~Footer note «تعرض البيانات المحفوظة مع التطبيق» shows on the live site while Firestore works~~ — fixed in PR #30 (ADR-038) → *Live data follow-ups*.
2. Sentry web source maps + Android symbols need a Sentry auth token → *Error tracking — Sentry*.
3. Sentry project privacy: *Prevent Storing of IP Addresses* + server-side data scrubbers → *Error tracking — Sentry*.
4. Android assistant needs release signing + Play Integrity registration → *Infrastructure & security*.
5. ~~Custom sections / pages are not in the sitemap~~ (PR #30: generated from Firestore at deploy, ADR-038); still not named in the assistant's allowed topics → *Custom sections*.
6. 320 px overflow reported on a real phone → *Infrastructure & security* (320 px item).
7. CI rebuild of the eBible verse asset (source-fidelity check) → *Verse of the day*.
8. Server-side assistant limit (the 3/day limit is client-side only) → *Assistant follow-ups*.
9. **Live check 4 Nov 2026 — owner items (not code):** (a) `settings/church.nameAr` reads «…الأنبا موسى **الابيض**»
   (saved via /admin 4 Nov 12:33): correct it to «الأسود» in /admin → church settings; (b) decide whether
   `/main.dart.js.map` (public, ~4.3 MB, exposes the Dart sources, built with `--source-maps` for PageSpeed) should
   stay public or be deleted from `build/web` before deploy (it could go to Sentry instead once a token exists);
   (c) `/contact` logs Google Maps `InvalidKeyMapError` — check the Maps embed key / its allowed referrers
   (`maximos-domadios-church.web.app`); (d) `/ask` returned «تعذّر الحصول على إجابة الآن» in automated browsers
   (App Check reCAPTCHA Enterprise 403 "App attestation failed", then a 1-day `appCheck/initial-throttle`): test once
   on a real phone; if it fails there, check the "church-portal-web" key's allowed domains. Fixed in code in PR #30:
   footer «العيادات» link during load, the half-empty screen after the splash, slow "not available" on missing
   custom / detail pages, English image alts and Arabic digits in English times.

10. **Holy Week & revivals roadmap (`docs/holy-week-and-revivals-roadmap.md`)** — PR #31 shipped the Coptic calendar /
    liturgical day / date strip, the top event of the day and the live banner (ADR-039/040); PR #32 the programme
    details (speaker / topic / choir / venue / audience / Drive PDF link, ADR-041 — owner: review the venue / audience
    lists in /admin → «إعدادات المواسم» and fill the programme group on Holy Week / revival services); PR #33 the
    season presets, season verse sets, assistant season limit / topics and hero v2 (ADR-042 — owner: add the Holy
    Week verses in «إعدادات المواسم» → «آيات المواسم», check «المساعد الذكي» → season limit (default 6), and a few
    days before Holy Week open «تجهيز الموسم», pick the season and apply; after it, press «استرجاع الإعدادات السابقة»).
    Owner: after merge, run *Actions → Daily commemoration* once (or wait for
    16:10 UTC) and optionally cap kept Hosting versions (Firebase console → Hosting → release storage) since the
    workflow publishes twice a day.

11. **Seasons v2 fixes A (PR #45, ADR-050) — owner decisions on live data (nothing was written):** (a) placeholder
    text «في انتظار تأكيد الكنيسة» / «(لم يُؤكَّد …)» is now hidden on display; clear it in /admin if live still stores
    it: `facilities/nursery`, `employment`, `library` (`descAr/En`), `priests/bigol`, `saleeb`, `barnaba` (`bioAr/En`,
    if those docs exist live); `activities/davids-tones`, `hymns-school` (`descAr/En`): drop «شريك» / "partner" if
    live says it, the affiliation caveat stays; (b) seed samples `hw-palm`,
    `hw-thursday`, `hw-friday`, `hw-saturday`, `pascha-eve`, `pascha-day` and the templates `hw-day-*`, `hw-eve-*`,
    `rev-max-*`, `rev-moses-*` still show in a season with no real service — enter the real programme or hide them;
    (c) after deploy, set `milestones/pope-visit.gallery[3].url` to
    `https://maximos-domadios-church.web.app/media/milestones/pope-visit-gallery5.webp` (prepared in
    `work/fixall/live-gallery3.json`, 1 write); (d) tick «يحل محل قداسات اليوم المعتادة» on feast liturgies of additive
    seasons that should cancel the day's regular masses.
12. **Seasons v2 follow-ups (ADR-051, PR #44)** — done in code: season keys `apostles` / `nayrouz` (+ Cross) / `kiahk` /
    `great_lent`, admin exceptional-quota list, prompt «Church calendar», Arabic digits in the limit message, /ask
    greeting / chips skip hidden sections, tonight's live end, `replaceDates`, fast presets without weddings, Holy Week
    day names, EN live label. **Owner:** re-key the 2027 season docs that used `fast` / `pascha` as stand-ins (Great
    Lent, Apostles, Kiahk, Nayrouz) in /admin → المواسم **together with their services' «الموسم» (`seasonKey`) in
    القداسات والصلوات** (matching is by exact key: a season re-keyed alone loses its services; the season's «نوع الموسم» field now says so); review «المساعد الذكي» → «المواسم الاستثنائية»; set
    «أيام يحل فيها الموسم محل الجدول العادي» on revival / fast seasons that have a feast night; fill «نص الشريط
    (إنجليزي)» when streaming. Open: a separate `cross` key only if the church wants the Cross apart from Nayrouz;
    the admin's free-text welcome is not filtered by sections.

13. **Seasons v2 round 2 fixes (ADR-053)** — done in code: full-override seasons replace the regular schedule on every
    day of an exact window (r2 P1 N1), cross-season sample hidden from the season lists / prompt weekly list (r2 P3),
    later parallel service named with its time on the card (r2 P2 O-a), switch subtitle mentions fasts (r2 P7 O3).
    **Owner:** a Holy Week / Pascha / Nativity season doc must have exact `startsAt` / `endsAt` (it now cancels every
    regular service inside, also on days with no entered programme) — keep the 50 Days additive. **Next:** re-run the
    7 season phases on the new main; still open from r2: «ليلة عيد القيامة» name (owner choice, P2 O-b); the
    /mass-schedule list cards' parallel summary still uses the overlap wording.

14. **Seasons v2 round 3 fixes (ADR-054)** — done in code: listed sample states its exception day («لا يُقام ٢٣ يونيو»,
    prompt "(not on …: replaced by …)", r3 P3 item 9); past seasons leave /mass-schedule and the prompt (r3 O-2);
    «بعد يومين» / «بعد ١١ يومًا» (O-1); preset dialog warns when a season replaces the weekly schedule for more than 3
    days (O-3; **owner:** keep the 50 Days additive — untick replaceRegular); the next card no longer repeats the
    now-box service (r3 P7 12:30); balanced season chip (P5 O-d). **Next:** re-run the 7 season phases on the new
    main until 0 FAIL / PARTIAL.

15. **Seasonal list empty state (ADR-055)** — done in code: /mass-schedule seasonal view with no current season shows
    «لا توجد مواسم حالية» + «الموسم القادم: … — يبدأ …» (round-4 empty screen). **Owner:** visual approval of the PR
    preview before merge.

## Phase 2 — notifications & mobile apps (ADR-056, plan in `docs/plans/phase2/`)

Progress is tracked in [`docs/plans/phase2/STATUS.md`](../plans/phase2/STATUS.md); the chain is merged only after
the owner approves the whole chain.

- [x] PR A — install banner + notification preferences (ADR-057)
- [x] PR B — Android APK + local notifications (ADR-058)
- [x] PR C — admin notification manager + FCM sender + deep links (ADR-059)
- [ ] PR D — web push + PWA + iPhone (ADR-060)
- [ ] PR E — responsive + size audit (ADR-061; includes the 320 px app-bar item below)
- [ ] Owner: keystore + secrets, FCM API + `push-sender` service account, VAPID key, Android developer verification
      before 2027 (`docs/plans/phase2/LAUNCH-AND-OPERATIONS.md`)
- [x] Owner decisions 6 Nov 2026 19:57 (README §8): **#6** APKs on GitHub Releases of a separate public repo
      `Kerollosmm/church-portal-apk`, manifest on Hosting; **#17** Katameros = Arabic Van Dyck full text + English
      references only (no NKJV), daily file ≤ ~20–25 KB.
- [ ] At PR B time: create the public repo `Kerollosmm/church-portal-apk` (owner, or the agent with the owner's
      approval), fine-grained `RELEASES_REPO_TOKEN` (that repo only, Contents: Read and write) as a main-repo Actions
      secret, variables `APK_HOST=releases-repo` + `APK_BASE_URL`; retention = newest 5 releases (PR B §12 / §15)
- [ ] Owner decisions on the plan (README §8): launch types / default times (#9), web «ذكّرني» design
      (#12), web pushes = event pushes + seasons + reminders (#13), seasons via FCM on the APK (#14), repo visibility
      (#15), exact alarms for APK reminders (#16), reminders in quiet hours (#18). (The urgent instant-dispatch token was removed from the plan on 6 Nov 19:31.)
- [ ] After PR C: Sentry cron monitor `push-sender` + `keepalive.yml` first run (LAUNCH §14)

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
- [ ] **`production` environment required reviewers** (recommended hygiene; no Phase 2 dependency since 6 Nov 19:31) (Settings → Environments) so live deploys, rules deploys
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
- [ ] **320 px overflow (reopened 4 Nov 2026, owner):** the automated sweep in `test/accessibility_test.dart` renders
      every public route at 320 px × 200 % text without overflow, but it uses the Flutter **test font**; the owner
      still lists 320 px overflow as open. Check on a real 320 px phone (or Chrome device mode at 320 px) with the
      bundled **IBM Plex Sans Arabic** / Lalezar / Aref Ruqaa fonts, find the overflowing widget (hero, verse, app bar,
      cards) and add a regression test that loads the real fonts. (Earlier fix: BUG-11 #1, highlight buttons move to
      the drawer below 360 px.)
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
- [x] Detail URLs in the sitemap — PR #30 (ADR-038): `deploy.yml` generates `sitemap.xml` from Firestore (read-only)
      with the app's own indexing rules; the static `web/sitemap.xml` is only the fallback.
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
- [ ] **CI eBible rebuild** (source-fidelity step: download the SHA-pinned eBible zip, run `tool/gen_daily_verses.py`,
      fail on a diff of `assets/verses/daily_verses.json`). Skipped in PR #16 to keep CI free of a network dependency; a test checks the asset's `sourceSha256`.
- [ ] Optional: an English verse alongside (a public-domain English translation such as KJV/WEB would need its own
      verified source); today the English UI shows the Arabic verse with an English reference.

## Occasion themes & hero videos (PR #17, ADR-025/026)

- [x] Theme presets, Cairo-date schedule, Coptic Easter, admin colour edits with contrast auto-correction, verse of the
      day in the hero. (The YouTube hero video library shipped here was removed in PR #25, ADR-036.)
- [ ] Church office: confirm the Holy Week / Resurrection looks and the default Resurrection length (7 days), and
      add the Nativity / fasts / Marian ranges each year (or ask for fixed-date presets such as 7 Jan / 19 Jan /
      the Marian feasts to be computed like Easter).
- [ ] Optional: `settings/church.verseAr/En` are no longer shown publicly — retire them from the admin form or reuse
      them (e.g. a parish motto).
- [ ] Optional: remove the legacy `heroVideos` key + `validHeroVideos` from `firestore.rules` once no live
      `settings/features` stores it (check the live doc first; never delete live data from the app) — ADR-036.
- [ ] Optional: a dark theme for the admin dashboard (it keeps Golden hour).
- [x] Theme follows the active church season; Holy Week / fasts palettes without violet or gold; legacy `purple` hidden
      (PR #37, ADR-043).
- [x] Seed templates mixed into an owner's season (ADR-043 B4 per day; sims B5): since PR #38 (ADR-045) a `sample`
      template is hidden in any season that has a real service, additive revivals included.
- [ ] Owner (ADR-045, recommended tidy-up): on live, hide (visible off) the seed templates `rev-max-1…7`,
      `rev-moses-1…7`, `hw-day-1…3` / `hw-eve-1…3` once the real programme is entered — they no longer mix in, but
      they would show in a season with no real service yet (no badge since ADR-046). Never delete live data from the app.
- [ ] Owner (ADR-045): for each revival night add speaker / topic / PDF on the service itself — the Home top event
      and the assistant now read them from there (a church event in «اليوم والبث المباشر» still takes precedence).
- [ ] Optional (ADR-043 cost): if the app-wide `seasons` listener matters, derive the active season from
      `settings/features.seasonPreset` only (no listener) when no season list is needed on the page.
- [x] ADR number: PR #35 (splash / top bar) renumbered to ADR-044 after PR #37 took ADR-043.
- [x] Seasons simulation Phase 1 (5 Nov 2026, `work/seasons-sim/phase1`): D1 «يُقام الآن» without the parallel
      services and C1 the grey-on-grey seasonal switch on Holy Week — fixed in PR #42 (ADR-049), with overnight and
      day-to-night handover tests. Still open from that report: S1 Holy Week day names in the top bar («ليلة الجمعة
      العظيمة», new feature), S2 dated seed samples `hw-palm` / `hw-saturday` outside the owner's days, S3 gold in the
      seal / photos on dark themes (design decision).
- [ ] Owner (ADR-049, optional): an additive season's own `mass` hides every regular mass that day (ADR-045
      feast rule); say if it should hide only the overlapping ones.
- [x] Live test 5 Nov 2026 (ADR-046, PR #39): top-event cold-load flicker, EN `<title>` / `lang`, reCAPTCHA on every page
      after /ask, «تعرّف على عن الكنيسة», public sample badges / banner, empty Coptic date in `today.json`, CORS pope-visit images.
- [ ] After PR #39 is merged and deployed: rewrite only `milestones/pope-visit` `image.url` + `gallery[0..2].url` on live to
      `/media/milestones/pope-visit-*.webp` (owner-authorised, admin SDK; before / after in `work/live-fixes/status.md`).
- [ ] Owner (data): `topEvent` and `commemoration` are off on live — switch them back on in «اليوم والبث المباشر» for the
      card to show at all; confirm or hide the 47 sample liturgies / 4 priests / 4 facilities (no public mark now, but
      the times are still unconfirmed and the assistant still marks them `[UNCONFIRMED]` when `mentionUnconfirmed` is on).
- [ ] Optional (rca #5): cap or slow the hero Ken Burns clock — NOT without the owner (approved motion, standing rule).
- [x] English verse of the day (live test 5 Nov 2026, rca #2): PR #40 / ADR-047 (WEB British Edition, admin English fields).
- [ ] Owner (optional, ADR-047): add English text to the fixed verse / season verses in /admin when used — without it the
      English site shows that verse in Arabic.

## Custom sections, pages & contact types (PR #18, ADR-027/028)

- [x] Admin-defined categories with items and their own pages + menu entries; custom pages (blocks incl. donation
      info) linked from notices; contact types with hall booking, anonymous complaints / suggestions, inbox boxes,
      booking status and notes.
- [ ] Church office: create the donations page for the new building (account / InstaPay / wallet details) and
      confirm the contact types and booking occasions.
- [ ] Optional: let built-in sections and custom categories share one menu order (built-ins come first today).
- [ ] Optional: detail pages for custom items (cards show the full description today).
- [x] **Custom sections / pages in the sitemap** — PR #30 (ADR-038): `/section/<slug>` and `/page/<slug>` of every
      public category / page (nav-hidden pages included) while their section switch is on, generated at deploy.
      Note: the sitemap refreshes on each deploy only — content an admin adds later is listed at the next deploy.
- [ ] **Assistant topics for custom content:** the content of custom sections / pages is grounded (PR #19), but the
      allowed-topics list is static (`AssistantSettings.defaultTopics`: one generic line "The custom sections and
      pages of this website"); a section's own name is not a topic, and the default topics / refusal text still
      mention clinics while the clinics section is off. Option: build the topic lines from the enabled sections +
      visible custom categories in `buildAssistantInstruction`, or let the admin edit them (Allowed topics field).
- [x] Never reuse a deleted contact-type id (PR #19: stable random ids).

## Content (owner: church office — see `09-content-status.md`)

- [ ] Real liturgy/vespers/praise timetable (47 placeholders), meetings (11), clinics (live documents deleted and
      section off since 4 Nov 2026 — add real clinics in the admin only if the church runs them),
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
      done in PR #10 — crawlers that do not run JS still see the static `/` canonical.) Since PR #30 the deployed
      sitemap follows `sections.clinics` by itself (generated from Firestore); the static fallback follows the seed.
- [ ] PageSpeed beyond ADR-037 (PR #29): TBT / Speed Index stay high because the CanvasKit Flutter app must
      download and start before the real page paints (the static hero splash covers first paint). Done in PR #30
      (ADR-038): the splash stays until the first settings / home data (9 s cap) and the hero video / ambient layer
      start at page idle. Still open if wanted: pre-rendered HTML for public pages. Remove the `Intl.v8BreakIterator` shim in `web/index.html` once Flutter's
      engine stops calling it.
- [ ] Performance budget (Lighthouse in CI), font subsetting (fonts are bundled since PR #15 — `assets/fonts/`, no
      runtime fetch — but not subset). (Deferred
      `/admin` and `/ask` chunks done in PR 3 of the review plan; verify lazy loading in the Network tab on the
      preview.)
- [ ] Footer: "last updated" (optional; needs a tracked timestamp — phones and socials done in PR #13).
- [ ] Persist the language choice on Android/iOS too (web uses `localStorage` key `church_portal_lang` since PR 3 of
      the review plan; native is still a no-op in `locale_storage_stub.dart`). `shared_preferences` is a dependency
      since PR #21 (assistant daily counter), so a native `LanguageStore` no longer needs a new package.
- [ ] Clinics/meetings freshness view in admin (FR-AD-06); "simulate now" next-mass preview for editors (FR-AD-03).
      (Meetings "today" badge FR-E-03 and admin "Open on site" via `CollectionDef.publicPath` done in PR 2 of the
      review plan.)
- [ ] Manual accessibility pass with TalkBack / VoiceOver on a real phone (automated checks live in
      `test/accessibility_test.dart`); the admin dashboard still uses fixed burgundy instead of the theme preset.
- [ ] PWA install prompt, floating *Live now* / *Doctors' times* buttons (v1.1).
- [ ] v2 ideas: FCM push alerts, daily synaxarium line, `.ics` export, live-stream embed.
- [ ] Consider an inbox "spam" status (business case) and owner-only settings (ADR-011) if the church asks.

## Docs

- [ ] Keep this memory bank **and** `/documentation/` (Arabic, one file per feature — PR #25, ADR-035) current with
      every PR (see `00-README.md`).
- [x] Arabic feature documentation (`documentation/`, PR #25).

## Assistant follow-ups (PR #21, ADR-031)
- [ ] Optional: on the Blaze plan, enable Grounding with Google Search restricted to `sourceDomains` (filter
      citations by `web.title`, show source links + the required Search-suggestions widget) instead of the search link.
- [ ] **Server-side assistant limit:** the 3-questions-per-device-per-day limit is client-side only (resets when site
      data is cleared; a modified client skips it). Set the Firebase AI Logic per-user rate limit / quota in the
      console, or later move the call behind a Cloud Function proxy (Blaze) that counts per App Check token.

## Error tracking — Sentry (PR #24, ADR-034)
- [ ] **Web source maps**: upload `build/web/*.js.map` (dart2js `--source-maps`) to Sentry for readable stack traces —
      needs a Sentry auth token (repo **secret** `SENTRY_AUTH_TOKEN`, org `kerollos-0e`, project `church-portal`) and a
      `sentry-cli sourcemaps upload --release church-portal@<version>+<sha7>` step in `deploy.yml` (main only); never
      deploy the `.map` files to Hosting.
- [ ] **Android symbols**: release APKs are not obfuscated yet; when `--obfuscate --split-debug-info` (and R8 /
      ProGuard mappings) are turned on, upload the Dart symbols + mapping with `sentry_dart_plugin` / `sentry-cli`
      (same auth token). There is no Android CI build yet: build with
      `flutter build apk --release --dart-define=SENTRY_ENVIRONMENT=production --dart-define=GIT_SHA=$(git rev-parse HEAD) --dart-define=APP_VERSION=1.0.0+1`.
- [ ] **DSN as a repo variable**: the agent's GitHub API has no Actions-variables endpoint, so release builds use the
      public DSN constant in `AppConfig.sentryDefaultDsn`. Optional: add the repository variable `SENTRY_DSN`
      (Settings → Secrets and variables → Actions → Variables); `ci.yml` / `deploy.yml` already pass it when set.
- [ ] **Sentry project settings** (sentry.io → church-portal → Settings → Security & Privacy): turn on *Prevent
      Storing of IP Addresses* and *Data Scrubber* + *Use Default Scrubbers* (server-side belt to the client
      scrubbing); if wanted, inbound filters for `preview` / `ci`.
- [x] Sentry alerts + monitoring (owner, 3–4 Nov 2026): alert e-mails to the developer, an uptime monitor on the live
      site, Seer / Autofix on; plan Education Sponsored Team until 2027-11-03 (see `05-firebase.md` → *Sentry*).
- [ ] Before **2027-11-03**: renew the Sentry education sponsorship or accept the free plan (errors-only usage fits).
- [ ] Optional (CodeRabbit nitpick): a `@TestOn('browser')` test of the JS glue in `sentry_js_gate_web.dart` (fake
      `window.Sentry` client, assert the registered `beforeSend` Promise) + a `flutter test --platform chrome` CI
      step. The scrubbing itself is pure Dart (`scrubEventJson`) and covered by `test/error_reporting_test.dart`.
- [ ] Verify a first event from production: an owner presses **Send test error** in `/admin` and checks the issue in
      Sentry (environment `production`, tags `section: admin`, `test: true`).

## Live data follow-ups (PR #23, ADR-033)
- [x] The footer note «تعرض البيانات المحفوظة مع التطبيق» showed on the live site while Firestore worked — **fixed in
      PR #30 (ADR-038)**. Proven root cause: the `settings/church` seeding check timed out / failed "client is
      offline" on a slow cold start, and a stream whose only snapshot cannot vouch for itself (missing optional doc
      such as `settings/contact`, or an empty collection) never re-checked, so it stayed on the seed. Now the
      `settings/church` listener proves seeding for every stream (`SeedGate.markSeeded` / `whenSeeded`).
- [ ] Follow-up (optional): the content streams still subscribe only after the one-shot seeding check answers (up to
      8 s on a slow start); subscribing at once and letting `whenSeeded` decide could make cold loads faster.
- [x] Clinics: the owner deleted the 11 seeded placeholders (3 Nov 2026) and switched the section **off** (4 Nov 2026,
      live `settings/features` updated 07:51 Cairo; one clinic added that morning stays hidden while off). The admin
      screen «العيادات» stays. Never run the Seed workflow for clinics: even create-only it re-creates the 11 deleted
      placeholders.

## Header / app bar & splash screen (4 Nov 2026)
- [x] Clinics shortcut removed from the public app bar (all widths, section on or off); clinics stay in the drawer /
      Services menu, Home directory and footer quick links when `sections.clinics` is on. Guarded by
      `test/feature_gate_test.dart` (PR #26). At ~07:30 Cairo on 4 Nov the live `sections.clinics` still read true; it
      was switched off at 07:51 (PR #25 live read).
- [x] **Liturgical web loading screen & top utility bar (PR #35, ADR-044)** — cream loading screen with the app's seal,
      Lalezar name and a composited gold progress track; `TopUtilityBar` above the app bar on the palette's title band
      with the Coptic date and a live badge; seal tab offset by the bar height.
- [ ] Owner (ADR-044): approve the visuals on the PR #35 preview before merging (Golden hour and Holy Week).
- [x] Owner (ADR-044, 5 Nov): while live, Home shows only the red `LiveStreamBanner`; every other page shows the
      tappable top-bar badge (admin switch «إخفاء شارة البث في الرئيسية عند ظهور الشريط», default on).
- [ ] Owner (ADR-044): the HTML loading screen is always cream; on a dark theme (Holy Week) it switches to charcoal when
      the app appears. Optional: remember the last theme's ground in `localStorage` and paint the screen with it.

## Mobile Performance, Native Splash & Navigation Chrome (ADR-062, 8 Nov 2026)
- [x] **Hero ambient loops on APK (`INV-PERF-01`)**: `heroAmbientLoopAllowed` halts 60 s canvas tickers and blurred ray repaints on Android APK, eliminating Home screen frame drops; hardware-decoded video preserved.
- [x] **Native Android splash cream (`INV-SPLASH-01`)**: `#FBF3E4` (`splash_cream`) applied across `launch_background.xml` (API 21+) and `styles.xml` (including `values-v31` Android 12+ Splash API) in light and dark mode, eliminating the cold start white flash.
- [x] **Single back arrow & unified shell (`INV-NAV-01`, `INV-NAV-02`)**: `AppShell.leading` provides single back arrow on mobile viewports; in-body `_BackLink` on `ItemDetailPage` shown only on desktop (`shellIsWide`); `NotificationHealthPage` unified to `PageBody` + `PageHeader` with parent routing back to `/notifications`.
