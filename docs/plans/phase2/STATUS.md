# حالة التنفيذ (Phase 2 status — tick as you go)

> Single source of truth for whoever continues the work (HANDOFF §9). Update in the branch you are on.

## الوضع الحالي (Current state)

- **Updated:** 8 Nov 2026 (Cairo), by Hark — PR B fix round (apk build, review findings), see the PR B section.
- **Plan PR:** [#50](https://github.com/Kerollosmm/church-portal/pull/50) — branch `docs/phase2-plans` → `main`, draft;
  review rounds 1 and 2 (the maximum) addressed; owner change requests of 6 Nov evening applied; **owner
  clarification of 19:31 + additions of 19:35 applied** (instant dispatch removed — scheduled sender only with
  guaranteed delivery; admin event pushes; new user «ذكّرني» reminders; local verse + Katameros with a reading
  screen; keep-alive + sender-health alert; honest web-reminder delay copy; OEM battery guidance + diagnostics); **owner decisions of 19:57 recorded** (§8 #6
  releases repo, #17 Arabic text + English refs) — waiting for the owner (gate G0). No further bot review rounds on this PR.
- **Next action:** PR A is implemented in draft PR [#51](https://github.com/Kerollosmm/church-portal/pull/51)
  (`feat/p2a-install-prefs` → `docs/phase2-plans`; bot review rounds 1 and 2 — the maximum — answered). The owner
  reviews #51 and answers the open README §8 items. **Do not start PR B** until the owner says so. Gate G0 approval
  status is not recorded in this file (unconfirmed).
- **Decided 6 Nov 2026 19:57:** README §8 **#6** (APKs on GitHub Releases of a separate public repo
  `Kerollosmm/church-portal-apk`, manifest on Hosting, newest 5 releases kept — repo **not created yet**, created at
  PR B time by the owner or with approval) and **#17** (Katameros = Arabic Van Dyck full text + English references
  only, no NKJV; daily file ≈ 8 KB gzip, target ≤ ~20–25 KB uncompressed / minified JSON; WEB / ASV swap possible later).
- **Blockers / owner decisions open:** README §8 #5, #7–#9, #11 (keystore, VAPID, service account, launch
  types and default times, Android developer verification); to
  confirm: #10 (assistant in APK), **#12 web reminders design**, #13 (web gets event pushes + seasons + reminders;
  verse / Katameros / feasts on Home), #14 (seasons = FCM), #15 (repo visibility), **#16 exact alarms**, **#18
  reminders in quiet hours**; recommended: #19 (`production` required reviewers — hygiene, no longer a blocker).
- **Notes:** baseline `main.dart.js` 4,898,252 B / gzip 1,334,591 B (`main` @ `7e4705b`). Phase 2 code so far:
  PR A only, on `feat/p2a-install-prefs` (#51); no PR B–E branches yet.

## PR 0 — Plans (ADR-056)
- [x] Plan files written (README, HANDOFF, STATUS, PR A–E, LAUNCH-AND-OPERATIONS)
- [x] Memory bank (ADR-056, open tasks) + Arabic / English documentation index updated
- [x] Draft PR opened · #50
- [x] CI green (first two heads)
- [x] `@coderabbitai review` · `@sentry review` requested; round 1 findings handled
- [x] Owner change requests (6 Nov evening) applied: dual trigger (superseded 19:31 — removed), sideload guide (PR A §3.3),
      in-app update + hosting (PR B §3.3 / §12, LAUNCH §4), channel segregation + iOS onboarding (README §3.1, PR D §3.1)
- [x] Review round 2 (`@coderabbitai review` · `@sentry review`, last round) findings handled — Sentry 3 (counter
      without reads, `includeUncontrolled`, admin/sender field split) + CodeRabbit 20 (production approval before the
      token, Admin-SDK topic management with per-token results, `prevToken` union, plain SW foreground delivery,
      `requestIdleCallback` fallback, per-topic partial-send recovery, `topic_override` safeguards, urgent = «now»
      only (urgent path later removed, 19:31), `saveDocsFresh`, API-level signature check, `cancelAllPendingNotifications`, replenishment freshness,
      `hosting-live` publish job, arm32 size, «the app that opened the file», storage / privacy wording, abuse
      recovery) + 2 round-1 follow-ups (same-tab stale flag, rejected-request rule reads)
- [x] Owner clarification 19:31 + additions 19:35 applied (docs only): instant dispatch / token / `admin_secrets`
      removed; scheduled sender with catch-up, retries, status (README §3.2, PR C §3 / §7); admin event pushes
      (README §3.3); user reminders «ذكّرني» (README §3.4, PR A §3.2, PR B §3.4, PR C §16, PR D §3.2); local verse +
      Katameros + reading screen (README §3.5, PR B §3.5); keep-alive + health alert (PR C §17, LAUNCH §14); OEM
      guidance + diagnostics (PR B §3.6); decisions renumbered (README §8 #12, #16–#19)
- [x] Owner decisions 19:57 recorded (docs only): §8 #6 releases repo (README §5, PR B §12 / §15, LAUNCH §1 / §4) and
      §8 #17 Arabic text + English refs (README §3.5, PR B §3.5, LAUNCH §11), ADR-056 + open tasks
- [ ] **G0 owner approval of the plan** (+ answers to README §8 #5, #7–#9, #11, #12, #16, #18)

## PR A — Install banner + prefs (ADR-057) · `feat/p2a-install-prefs` → `docs/phase2-plans`
- [x] Domain: `app_install.dart`, `push.dart` + tests
- [x] `FeatureSettings` parsing of install / push keys + tests
- [x] Rules + emulator tests
- [x] Web env + `index.html` early `beforeinstallprompt` capture
- [x] Channel-owner model per platform (6 types): `channelOf` / `isLocalOwned(type, platform)`, `topicFor` throws for local-owned pairs, `reminderTopic` + tests
- [x] Reminders foundation: `reminders.dart` (`EventKey`, `reconcileReminders`), `ReminderStore`, `RemindMeButton` + lead sheet + «تذكيراتي» (no delivery yet) + `reminderLeads` / `reminderDefaultLead` keys + tests
- [x] `InstallBanner` (Android APK / PWA prompt / steps, iOS steps sheet **without any permission call**, ✕, later, installed detection)
- [x] Android sideload guide modal (5 steps, screenshot placeholders, ar/en, safety box) + `web/install-guide/README.md`
- [x] `/notifications` page (explainer, states incl. `iosNeedsInstall` / `iosTooOld` / `inAppBrowser`, blocked how-to, platform-filtered toggles, unsubscribe-all) behind `push`
- [x] Admin «التطبيق والإشعارات»
- [x] SW + `push_client.js` scaffolds
- [x] Docs: memory bank, Arabic `documentation/`, English, ADR-057
- [x] analyze 0 · flutter test 1110/1110 · rules 133/133 · build green · `main.dart.js` 4,964,109 B / gzip -9 1,353,225 B vs base `1881ce6` 4,898,239 / 1,334,622 → **Δ +65,870 B raw / +18,603 B gzip** (≤ +20 KB budget; notifications page, reminder sheet + «تذكيراتي», install guides are deferred chunks)
- [ ] Screenshots (390 px AR: Android banner, sideload guide steps 1 + 4, iPhone banner + sheet, prefs page incl. iOS install-first)
- [ ] Draft PR #51 · CI green · preview https://maximos-domadios-church--pr-51-gqdq4466.web.app · reviews done (CodeRabbit + Sentry rounds 1 and 2 — the maximum — answered)
- [ ] PSI mobile median ___

## PR B — Android APK + local notifications (ADR-058) · `feat/p2b-android-local-notifications` → A
- [x] `planNotifications` (Android-local types only: verse, Katameros, feasts, reminders; ~9-day window, refresh < 4 days) + tests
- [x] Readings: `tool/fetch_readings.js` + `synaxarium.yml` / `deploy.yml` publishing `/data/readings/*.json` (multi-file `publish_hosting_file.js`), `readings.dart`, cache, `/readings/<date>` screen (offline) + tests; Arabic Van Dyck full text + English references only per §8 #17 (decided 6 Nov 2026; `bibleEn: refs-only`, ≈ 8 KB gzip, target ≤ ~20–25 KB uncompressed / minified JSON per file)
- [x] `ReminderScheduler` (exact `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` ≤ 32 with inexact fallback, boot + package-replaced, follow edits / cancel on removal, notification action) + tests
- [x] OEM battery guidance screen (Xiaomi / Oppo-Realme / Vivo / Huawei-Honor / Samsung, try-list intents) + diagnostic check («افحص الإشعارات», «اختبار بعد دقيقتين») + tests
- [x] Gradle: desugaring, minify/shrink, env signing (debug fallback); `flutter_local_notifications ^22.3.3` (23.x needs compileSdk 37 / AGP 9.1.1), minSdk 26 (`sentry_flutter` 10), compressed native libs
- [x] Admin compiled out (`kIsWeb || !dart.vm.product` compile-time guard), Android language store, back button, assistant via web
- [ ] `LocalNotifier`, channels (6), permission, prefs sections (verse / readings times, quiet hours + reminders rule, test, inbox)
- [ ] Re-plan triggers + boot receiver + inputs snapshot + `workmanager` daily replenishment
- [ ] Update banner (`installApkBuild`) + **in-app update**: manifest, resumable download with progress, SHA-256 + size, signature pre-check, `REQUEST_INSTALL_PACKAGES` explainer, FileProvider installer intent (Kotlin channel), clean-up
- [ ] `android.yml` (artifacts on PRs, release on `apk-v*` tags, APK size budget step, `APP_BUILD` define, `version.json` via `tool/make_apk_manifest.mjs`, publish per `APK_HOST`) + `deploy.yml` keeps `/app/android/*`
- [ ] Docs + ADR-058 · APK sizes arm64 14,978,067 B / arm32 14,565,355 B (CI `apk` on `8184692`, debug-signed, budget 20 / 18 MiB) · web `main.dart.js` 4,972,733 B / gzip -9 1,355,532 B vs PR A 4,964,109 / 1,353,225 → **Δ +8,624 B raw / +2,307 B gzip**
- [ ] Draft PR #52 · CI green (incl. `apk` from `8184692`) · reviews: bot findings of round 1 triaged in the 8 Nov fix round (open threads listed in the PR body); no new bot round requested
- [x] Fix round 8 Nov 2026: Android prefs / reminders were not persisted (stub `InstallEnv`) → `install_env_io.dart`; worker snapshot lost push keys / `dayEvents` / `seasonVerses`; expired / double inexact reminders; updater fail-open + wrong cache dir + manifest build 1; `deploy.yml` dropped `version.json`; partial readings window deleted hosted days (all fixed, see PR body)
- [ ] Owner: keystore + secrets (or accept debug test builds); releases repo `Kerollosmm/church-portal-apk` created (owner, or agent with approval at PR B time) + `RELEASES_REPO_TOKEN` (fine-grained, that repo only, Contents: Read and write) + variables `APK_HOST=releases-repo`, `APK_BASE_URL` (§8 #6, decided)
- [ ] Release workflow: mirror to the releases repo + retention step (newest 5 kept) — PR B §12

## PR C — Admin notification manager + FCM sender + deep links (ADR-059) · `feat/p2c-notification-manager` → B
- [x] `NotifyConfig`, templates, `dueNow`, dedup, `EventKey` + tests
- [x] Rules (`notifyTypes` ≤ 6, `reminderSources`; admin-only `settings/notifications` with `schedule` incl. `eventKey`, sender-only `status` / `sentLog` / `reminderPlan` / `remindersSent` / `health`) + emulator tests
- [x] Admin «الإشعارات» (types with channel labels, «ذكّرني» card, event pushes CRUD with route / event picker, status chips, sender health card, preview, test-on-device, log)
- [x] `tool/cf_push_worker.js`, `tool/push_sender.js` (cron only; per-topic claim, retries ≤ 3, catch-up, 24 h expiry, health stamp, Sentry check-in), `tool/push_daily.js` (season alerts) + node tests (delivery guarantee)
- [x] `push-sender.yml` (manual fallback) + `keepalive.yml` (monthly workflow keepalive)
- [x] Android FCM (`app_announcements_*`, `app_seasons_*` only) + data-only payload `type` / `nid` / `eventKey` + client guard + seen-set + `event:X` slot + deep links; `flutterfire_ignore_scripts` on web
- [x] Docs + ADR-059 (`documentation/features/install-and-notifications.md`, `documentation/operations.md`, `documentation/en/`)
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___
- [ ] Owner: FCM API, `push-sender` SA, `FIREBASE_SA_PUSH`, `PUSH_DRY_RUN=true`, Sentry cron monitor + `SENTRY_CRONS_URL` (optional), first `keepalive.yml` run (LAUNCH §14); recommended `production` required reviewers

## PR D — Web push + PWA + iPhone (ADR-060) · `feat/p2d-web-push` → C
- [x] Spike: token on Android Chrome + iPhone PWA; IID batchAdd works
- [x] Rules `push_queue` (4 fixed web topics + `rem` / `drop` reminder-topic strings ≤ 30) + `meta/push_rate` (`day` as UTC `YYYYMMDD` int, deterministic retry sequence) + emulator tests (160 pass)
- [x] `push_client.js` + `firebase-messaging-sw.js` complete; Dart interop (`PushEnvWeb`, `WebPushRepository` deferred)
- [x] Worker Cron 2 drains the queue (Google IID REST `batchAdd`/`batchRemove`, single writer of `meta/push_topics`)
- [x] Web «ذكّرني»: debounced queue writes, delay copy ar / en (40-minute minimum window), «أضف إلى التقويم» with RFC 5545 `.ics` + `VALARM` and Google Calendar URL, expired clean-up
- [x] Page: quiet hours (`silent: true`), test notification, IndexedDB inbox with clear history, iOS onboarding states (install-first, too old, standalone, focus mode note), in-app browser copy link, web offers announcements + seasons + reminders
- [x] SW guard (visible notification guarantee, fallback on forbidden types) + `nid` dedupe (`tag: nid, renotify: false`)
- [x] Docs + ADR-060
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___
- [ ] Owner: VAPID key in `/admin`

## PR E — Responsive + size audit (ADR-061) · `fix/p2e-responsive-size` → D
- [x] 320 px app-bar space recovery (< 360 px title + seal tab >= 6 dp gap) & real-font geometry regression test
- [x] Landscape < 420 px restraint (hide InstallBanner & TopUtilityBar)
- [x] Phase 2 surfaces responsive sweep (readings, notifications, battery, sheets, install guide)
- [x] Deferred chunk load error handling (`ErrorReporting.capture`)
- [x] Bundle-size CI gate (main.dart.js gzip -9 <= 1,396,031 B & zero leaks in 8 deferred modules)
- [x] Docs + ADR-061 · screenshots 320 / 390 / 740x360 / 1024 / 1440
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___

## الدمج والإطلاق (Merge & launch)
- [ ] G2 chain ready (all above ticked) — reported to the owner
- [ ] G3 owner says "merge"
- [ ] Merged bottom-up (HANDOFF §5.6): 0 ___ · A ___ · B ___ · C ___ · D ___ · E ___
- [ ] LAUNCH-AND-OPERATIONS §13 launch-day checklist done
