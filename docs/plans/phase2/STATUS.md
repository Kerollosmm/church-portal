# حالة التنفيذ (Phase 2 status — tick as you go)

> Single source of truth for whoever continues the work (HANDOFF §9). Update in the branch you are on.

## الوضع الحالي (Current state)

- **Updated:** 6 Nov 2026 (Cairo), by Hark.
- **Plan PR:** [#50](https://github.com/Kerollosmm/church-portal/pull/50) — branch `docs/phase2-plans` → `main`, draft;
  review round 1 (Sentry 3 + CodeRabbit 19 findings) addressed; **owner change requests of 6 Nov evening applied**
  (urgent instant dispatch / dual trigger, APK sideload guide + in-app update + hosting decision, strict channel
  segregation + iOS onboarding); review round 2 requested (last allowed round) — waiting for the owner (gate G0).
- **Next action:** owner reviews the plan and answers README §8. **Do not start PR A** until the owner says so.
- **Blockers / owner decisions open:** README §8 #5–#15 (keystore, **APK host**, VAPID, service account, launch types,
  assistant in APK, Android developer verification, **urgent-dispatch token placement / who may send urgent**,
  **confirm web gets only announcements + season alerts**, **confirm seasons = FCM on the APK**, **repo
  visibility**).
- **Notes:** baseline `main.dart.js` 4,898,252 B / gzip 1,334,591 B (`main` @ `7e4705b`). No code written for
  Phase 2 yet; create `wtA` on `feat/p2a-install-prefs` per HANDOFF §1 when the owner allows.

## PR 0 — Plans (ADR-056)
- [x] Plan files written (README, HANDOFF, STATUS, PR A–E, LAUNCH-AND-OPERATIONS)
- [x] Memory bank (ADR-056, open tasks) + Arabic / English documentation index updated
- [x] Draft PR opened · #50
- [x] CI green (first two heads)
- [x] `@coderabbitai review` · `@sentry review` requested; round 1 findings handled
- [x] Owner change requests (6 Nov evening) applied: dual trigger (PR C §16, LAUNCH §14), sideload guide (PR A §3.3),
      in-app update + hosting (PR B §3.3 / §12, LAUNCH §4), channel segregation + iOS onboarding (README §3.1, PR D §3.1)
- [ ] Review round 2 (`@coderabbitai review` · `@sentry review`, last round) findings handled
- [ ] **G0 owner approval of the plan** (+ answers to README §8 #6, #12–#15)

## PR A — Install banner + prefs (ADR-057) · `feat/p2a-install-prefs` → `docs/phase2-plans`
- [ ] Domain: `app_install.dart`, `push.dart` + tests
- [ ] `FeatureSettings` parsing of install / push keys + tests
- [ ] Rules + emulator tests
- [ ] Web env + `index.html` early `beforeinstallprompt` capture
- [ ] Channel-owner model: `isLocalOwned`, `topicFor` throws for local-owned types + tests
- [ ] `InstallBanner` (Android APK / PWA prompt / steps, iOS steps sheet **without any permission call**, ✕, later, installed detection)
- [ ] Android sideload guide modal (5 steps, screenshot placeholders, ar/en, safety box) + `web/install-guide/README.md`
- [ ] `/notifications` page (explainer, states incl. `iosNeedsInstall` / `iosTooOld` / `inAppBrowser`, blocked how-to, platform-filtered toggles, unsubscribe-all) behind `push`
- [ ] Admin «التطبيق والإشعارات»
- [ ] SW + `push_client.js` scaffolds
- [ ] Docs: memory bank, Arabic `documentation/`, English, ADR-057
- [ ] analyze / test / rules / build green · size Δ ___
- [ ] Screenshots (390 px AR: Android banner, sideload guide steps 1 + 4, iPhone banner + sheet, prefs page incl. iOS install-first)
- [ ] Draft PR # ___ · CI green · preview ___ · reviews done
- [ ] PSI mobile median ___

## PR B — Android APK + local notifications (ADR-058) · `feat/p2b-android-local-notifications` → A
- [ ] `planNotifications` (local-owned types only: verse, feasts, occasions) + tests
- [ ] Gradle: desugaring, minify/shrink, env signing (debug fallback)
- [ ] Admin compiled out (`kIsWeb`), Android language store, back button, assistant via web
- [ ] `LocalNotifier`, channels, permission, prefs sections (times, quiet hours, test, inbox, battery note)
- [ ] Re-plan triggers + boot receiver + inputs snapshot + `workmanager` daily replenishment
- [ ] Update banner (`installApkBuild`) + **in-app update**: manifest, resumable download with progress, SHA-256 + size, signature pre-check, `REQUEST_INSTALL_PACKAGES` explainer, FileProvider installer intent (Kotlin channel), clean-up
- [ ] `android.yml` (artifacts on PRs, release on `apk-v*` tags, APK size budget step, `APP_BUILD` define, `version.json` via `tool/make_apk_manifest.mjs`, publish per `APK_HOST`) + `deploy.yml` keeps `/app/android/*`
- [ ] Docs + ADR-058 · APK sizes arm64 ___ / arm32 ___
- [ ] Draft PR # ___ · CI green · reviews done
- [ ] Owner: keystore + secrets (or accept debug test builds); APK host (`APK_HOST`, `APK_BASE_URL`, optional `RELEASES_REPO_TOKEN`)

## PR C — Admin notification manager + FCM sender + deep links (ADR-059) · `feat/p2c-notification-manager` → B
- [ ] `NotifyConfig`, templates, `dueNow`, dedup + tests
- [ ] Rules (`notifyTypes`; admin-only `settings/notifications` with `schedule` incl. `urgent` / `dispatch` + `sentLog`; owner-only `admin_secrets/github_dispatch`) + emulator tests
- [ ] Admin «الإشعارات» (types with channel labels, schedule CRUD, «إرسال عاجل الآن», dispatch status chips, owner token card, route picker, preview, test-on-device, log)
- [ ] `lib/data/github_dispatch.dart` + spike (CORS, Actions: write only) + Sentry token scrubbing
- [ ] `tool/push_sender.js` (claim gate shared by cron + urgent), `tool/push_daily.js` (season alerts only) + node tests (dual trigger, idempotency, fallback)
- [ ] `push-sender.yml` (dry run default; `trigger` / `row_id` inputs; concurrency group)
- [ ] Android FCM (`app_announcements_*`, `app_seasons_*` only) + data-only payload `type` / `nid` + client guard + seen-set + deep links; `flutterfire_ignore_scripts` on web
- [ ] Docs + ADR-059
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___
- [ ] Owner: FCM API, `push-sender` SA, `FIREBASE_SA_PUSH`, `PUSH_DRY_RUN=true`, urgent-dispatch token (LAUNCH §14)

## PR D — Web push + PWA + iPhone (ADR-060) · `feat/p2d-web-push` → C
- [ ] Spike: token on Android Chrome + iPhone PWA; IID batchAdd works? (result: ___)
- [ ] Rules `push_queue` (4 remote web topics only) + `meta/push_rate` + emulator tests
- [ ] `push_client.js` + `firebase-messaging-sw.js` complete; Dart interop
- [ ] Sender drains the queue
- [ ] Page: quiet hours, test, inbox, iOS onboarding states (install-first, too old, standalone), web offers announcements + seasons only, deep-link messages
- [ ] SW guard (local-owned `type`) + `nid` dedupe (`tag`)
- [ ] Docs + ADR-060
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___
- [ ] Owner: VAPID key in `/admin`

## PR E — Responsive + size audit (ADR-061) · `fix/p2e-responsive-size` → D
- [ ] 320 px app-bar overlap fixed with a real-font regression test
- [ ] Width × text × locale × theme sweep green
- [ ] Font subsetting (if kept) + shaping check
- [ ] Bundle-size CI step; optional Lighthouse job
- [ ] Docs + ADR-061 · screenshots 320 / 390 / 768 / 1024 / 1440
- [ ] Draft PR # ___ · CI green · reviews done · PSI ___

## الدمج والإطلاق (Merge & launch)
- [ ] G2 chain ready (all above ticked) — reported to the owner
- [ ] G3 owner says "merge"
- [ ] Merged bottom-up (HANDOFF §5.6): 0 ___ · A ___ · B ___ · C ___ · D ___ · E ___
- [ ] LAUNCH-AND-OPERATIONS §13 launch-day checklist done
