# PR C — مدير الإشعارات في لوحة التحكم + مُرسِل FCM + الروابط العميقة (Admin notification manager + FCM sender + deep links)

| | |
|---|---|
| Branch → base | `feat/p2c-notification-manager` → `feat/p2b-android-local-notifications` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-059** |
| Depends on | PR A (types, `push`, `pushTypes`), PR B (APK, local planner) |
| Owner console work | enable the FCM API, create the `push-sender` service account + secret `FIREBASE_SA_PUSH` (§15) |
| Live effect after merge | admin screen visible; the sender runs but sends nothing while `push` is off |

## ١. الهدف (Goal)

The admin, from the web `/admin` only, **decides which notification types exist and are offered, their texts,
times and lead times**, and **creates / edits / deletes scheduled one-off notifications** (or sends one now) with a
**deep link to any page**. A free scheduled GitHub Action sends them through **FCM topics**; the Android app
receives announcements via FCM and keeps scheduling the other types locally from the same configuration. Tapping a
notification opens the chosen page on Android and (PR D) on the web / installed PWA.

## ٢. قصص المستخدم (User stories)

- كمشرف أفتح «الإشعارات» وأرى الأنواع الخمسة: أفعّل/أعطّل عرض كل نوع للزوار، أعدّل نص العنوان والرسالة بالعربي
  والإنجليزي، ووقت الإرسال، ومدة التذكير قبل القداس.
- كمشرف أضيف إشعارًا: «قداس عيد النيروز غدًا الساعة ٧ صباحًا»، أحدد وقت الإرسال، وأختار الصفحة التي تفتح عند
  الضغط من قائمة («مواعيد القداسات»، صفحة مخصصة، موسم…)، وأرى معاينة كما تظهر على الهاتف، ثم أحفظ.
- أعدّل أو أحذف أي إشعار لم يُرسل بعد؛ أرى سجل ما أُرسل ومتى ونتيجته.
- «أرسل الآن» يرسل في أقرب دورة (خلال ~١٥–٣٠ دقيقة) — موضح في الشاشة.
- «جرّب على هذا الجهاز» يعرض الإشعار على جهاز المشرف نفسه فورًا (بدون خادم).
- كمستخدم Android يصلني إعلان الكنيسة حتى لو كان التطبيق مغلقًا، والضغط يفتح الصفحة المختارة.

## ٣. الخصائص الفرعية (Complete sub-features)

| Sub-feature | Detail |
|---|---|
| Types editor | 5 rows (fixed set). Per type: offered (writes `pushTypes`), time `HH:mm` (verse, feasts, seasons), days before (seasons 0–7), lead minutes (occasions 15–240), title/body templates ar/en with placeholders, default link. Placeholder help under each field |
| Placeholders | `{verse}` `{ref}` (verse), `{season}` `{days}` (seasons), `{feast}` (feasts), `{service}` `{time}` `{place}` (occasions), `{date}` everywhere; unknown placeholders flagged by the validator |
| One-off schedule | list ≤ 20; row = title ar/en (≤ 80), body ar/en (≤ 240), send-at (Cairo date + time picker, 12-hour UI / 24-hour stored like ADR-049; blank = «في أقرب دورة»), deep link (route picker), targets (web, app; default both), type (default `announcements`) |
| Route picker | existing `FieldDef.linkPicker` («اختر صفحة…»): built-in routes (`/`, `/mass-schedule`, `/mass-schedule?tab=seasons`, `/about`, `/church-education`, `/church-activities`, `/clinics`, `/public-services`, `/contact`, `/ask`, `/notifications`), custom pages `/page/<slug>`, categories `/section/<slug>`, item detail pages (`/about/saints/<id>`, `/church-activities/<id>`…), plus the live-stream https link. Free text accepted if it passes the URL/path validator |
| Create / edit / delete | generic `objectList` editor (encoded rows) — edit allowed until sent; a sent row shows «أُرسل ١٠:١٥ ص» and is read-only, delete allowed (keeps the log) |
| Preview | live card under the row: notification mock (seal icon, app name, title, body, «الآن») in Arabic and English, character counters, truncation warning (Android shows ~2 lines collapsed) |
| Test on this device | admin browser: `Notification.permission` → `registration.showNotification(...)` via the PR A service-worker scaffold (no server). If permission not granted, explains how |
| Send now | sets `sendAt` = now; screen states the cron delay honestly («يُرسل خلال ١٥–٣٠ دقيقة») |
| Sent log | `pushSent` table: when, what (title), topic(s), result (`ok` / `error:<code>`), from the sender. «مسح السجل» (owner only) |
| Kill switch | `push` off → the sender sends nothing (and the client UI hides) |
| Quiet hours (server side) | the sender never sends daily web types between 22:00–06:00 Cairo; one-offs are sent when scheduled (admin's choice), Android shows them silently inside the user's quiet hours (data message → local display, §3.2) |
| Android FCM | `firebase_messaging` subscribes to `app_announcements_<lang>` when the user has `announcements` on (and unsubscribes on off / unsubscribe-all / language change). Data-only messages (`android.priority = high`) → background handler shows a local notification on the `announcements` channel, honouring quiet hours (silent) and storing it in the inbox |
| Deep links | payload `data.link`; Android: `onMessageOpenedApp`, `getInitialMessage`, local `onDidReceiveNotificationResponse` → `router.go(safeNotificationLink(link))`; external https only for the live-stream link (opens browser). Fallback: unknown / deleted page → 404 with «الرجوع للرئيسية»; switched-off section → FeatureGate notice |
| Dedup | every send has a key (`one:<id>`, `verse:2026-11-07`, `season:<seasonId>:<date>`, `feast:<date>`, `event:<date>:<i>`); sender skips keys in `pushSent` |
| Local planner follows admin | PR B planner reads `notifyTypes` (templates, times, leads) and `pushTypes` from the already-streamed doc — re-plans on change |

## ٤. الشاشات (Screens — `/admin` → «الإشعارات», `Icons.notifications_active_outlined`)

1. Header card: switch «تشغيل الإشعارات» (`push`), status line («المُرسِل يعمل كل ١٥ دقيقة — آخر تشغيل: …» from
   the last `pushSent` entry), link to the guide.
2. «أنواع الإشعارات» — 5 collapsible cards (generic `DocEditor` fields of `notifyTypes`, one encoded row per type).
3. «إشعارات مجدولة» — list with «إضافة إشعار»; each row: preview, send-at, link, targets, state.
4. «سجل الإرسال» — table (latest first).
Implementation: a dedicated `NotificationsAdminScreen` composed of the generic `ChurchInfoScreen` pieces with
`notifyDoc` (`DocDef('settings/features', 'الإشعارات', 'Notifications', [...])`) + a read-only log widget; writes
only changed keys (like `todaySettingsDoc`).

## ٥. نموذج البيانات + القواعد (Data model + rules)

Top-level keys of `settings/features` (encoded rows, `␟` = U+001F, like `dayEvents`):

```
notifyTypes:   'type␟time␟daysBefore␟leadMin␟titleAr␟titleEn␟bodyAr␟bodyEn␟link'      (≤ 5, unique type)
notifySchedule:'id␟type␟sendAt␟titleAr␟titleEn␟bodyAr␟bodyEn␟link␟targets'             (≤ 20)
               id = [A-Za-z0-9]{8}; sendAt = '' | 'YYYY-MM-DDTHH:mm' (Cairo wall time); targets = 'web,app' | 'web' | 'app'
pushSent:      'key␟sentAtIso␟result␟title'                                              (≤ 60, newest first; trimmed by the sender)
```
Dart: `NotifyConfig.fromFeatures(m)` (`lib/domain/push.dart`), `ScheduledNotification`, `SentEntry`, `dueNow(...)`,
`renderTemplate(...)`.

Rules (`validFeatures`), one gate each:
```
&& (!('notifyTypes' in changed) || validNotifyTypes(d))
&& (!('notifySchedule' in changed) || validNotifySchedule(d))
&& (!('pushSent' in changed) || (optList(d,'pushSent',60)
       && (d.get('pushSent',[]).size() == 0 || d.pushSent.join('\u001e').size() <= 20000)))
```
`validNotifyTypes`: list ≤ 5, joined with `\u001e`, one regex:
`(announcements|verse_daily|seasons|feasts|occasions)\x1f(|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9])\x1f[0-7]?\x1f[0-9]{0,3}\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{0,240}\x1f[^\x1f\x1e]{0,240}\x1f(|/[^\x1f\x1e ]{0,300}|[Hh][Tt][Tt][Pp][Ss]://[^\x1f\x1e ]{1,300})`
repeated `{0,4}` after `\x1e`. `validNotifySchedule`: list ≤ 20, same technique:
`[A-Za-z0-9]{8}\x1f(announcements|…)\x1f(|20[2-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9])\x1f[^\x1f\x1e]{1,80}\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{1,240}\x1f[^\x1f\x1e]{0,240}\x1f(link)\x1f(web,app|web|app)`.
The sender writes `pushSent` with the Admin SDK (bypasses rules); admins may only clear it (owner UI).
Emulator tests: valid rows pass; `javascript:` link, 21 rows, bad date, duplicate-free check, oversize text,
stranger write → denied; unrelated saves still within budget.

## ٦. التكلفة (Cost)

| Item | Reads | Writes | Notes |
|---|---|---|---|
| Visitors | +0 | +0 | same doc |
| Admin edits | — | 1 per save | |
| Sender run (every 15 min) | 1 (`settings/features`) | 0, or 1 when something was sent (`pushSent`) | ≤ 96 reads + ~5–10 writes/day |
| FCM | — | — | free, no quota cost |
| GitHub Actions | — | — | free for public repos (~40 s/run) |

## ٧. الملفات (Files)

Create:
- `tool/push_sender.js` — Node 22, `firebase-admin` (Firestore read/write + `getMessaging().send`). Steps: load
  `settings/features`; exit if `push` false; compute due items (one-offs `sendAt <= now` not in `pushSent`; daily
  web types via `tool/push_daily.js`); send; append to `pushSent` (transaction, trim to 60); print a job summary
  (`$GITHUB_STEP_SUMMARY`) without tokens or personal data.
- `tool/push_daily.js` — web daily items: verse (port of `lib/domain/daily_verse.dart` rotation over
  `assets/verses/daily_verses.json` + admin fixed / season verses), feasts (from the live `/data/today.json`),
  season starts (reads `seasons` collection **only on days a season could start**: 1 query/day, ≤ 20 reads),
  occasions (church `dayEvents` with times; weekly masses are **not** pushed to web — too noisy). Parity test with
  Dart.
- `tool/push_sender.test.mjs` (node:test, no network: fake messaging + fake Firestore objects).
- `test/fixtures/daily_verse_parity.json` generated by a Dart test for 400 dates → consumed by the node test.
- `.github/workflows/push-sender.yml` (§12).
- `lib/ui/admin/notifications_admin.dart`, `lib/data/push_messaging.dart` (Android FCM: init, topic sync,
  background handler — conditional import, web stub), `lib/domain/notify_config.dart` (or inside `push.dart`).
- `test/notify_config_test.dart`, `test/notifications_admin_test.dart`, `test/deep_link_test.dart`.
- `documentation/features/notifications.md` (Arabic admin manual), ADR-059.

Modify:
- `pubspec.yaml`: `firebase_messaging: ^17.0.1` (compatible with `firebase_core ^5.1.0`).
- **`web/index.html`**: `window.flutterfire_ignore_scripts = ['messaging'];` before Flutter boots — the
  `firebase_messaging_web` plugin would otherwise make `firebase_core_web` inject the messaging JS SDK on **every
  page load** (PageSpeed). PR D loads it lazily on tap instead. Verify in DevTools → Network.
- `android/app/src/main/AndroidManifest.xml`: default channel meta-data
  `com.google.firebase.messaging.default_notification_channel_id = announcements`, default icon `ic_stat_seal`.
- `android/app/google-services.json` (public config, via `flutterfire configure` or the Firebase console download)
  + Gradle plugin `com.google.gms.google-services` **only if** background messages fail without it (FlutterFire
  initialises from Dart options; test on a real device first and record the result in ADR-059).
- `lib/main.dart` (`FirebaseMessaging.onBackgroundMessage` top-level handler on Android only),
  `lib/router.dart` (initial link from `getInitialMessage`), PR B planner (reads `notifyTypes`).
- `lib/ui/admin/admin_page.dart` (destination), `lib/ui/admin/admin_schema.dart` (`notifyDoc`),
  `lib/ui/admin/admin_validators.dart` (template placeholders, sendAt in the future warning).
- `firestore.rules`, `tool/rules_test/rules.test.mjs`, `tool/package.json` (`firebase-admin ^13.0.0` is already a dependency; add a `test` script).
- Docs: memory bank 04/05/07/08/10/11, `documentation/operations.md` (sender runbook), `documentation/en/*`.

## ٨. الحزم (Packages)

| Package | Version | Where |
|---|---|---|
| `firebase_messaging` | `^17.0.1` | Flutter (Android FCM; web plugin registered but its SDK ignored on load) |
| `firebase-admin` (npm) | `^13.0.0` (already in `tool/package.json`) | `tool/` (sender) |

## ٩. خطوات التنفيذ (Step-by-step)

1. Domain: `NotifyConfig`, encode/decode rows, templates, `dueNow`, dedup keys + tests.
2. Rules + emulator tests.
3. Admin screen (types, schedule with route picker, preview, test-on-device, log) + widget tests.
4. Sender (`tool/push_sender.js`, `tool/push_daily.js`) + node tests + Dart↔JS verse parity fixture.
5. Workflow `push-sender.yml` with `workflow_dispatch` input `dry_run` (default true until launch) — prints what
   it *would* send.
6. Android FCM (`lib/data/push_messaging.dart`): topic sync, data-message handler → local notification, inbox
   entry, deep link; `flutterfire_ignore_scripts` on web.
7. Deep-link handling for local + FCM taps; fallback tests.
8. Docs + ADR-059. Owner sets up the service account (§15), runs the workflow manually with `dry_run=true`, then
   `false` with a test one-off to a **test topic** (`test_<random>` via input `topic_override`).

## ١٠. الاختبارات (Tests)

- Dart: rows round-trip, invalid rows dropped, template rendering ar/en with missing values, `dueNow` (past,
  future, blank = now, already sent), Cairo times across the summer-time switch, `safeNotificationLink` with every
  picker output.
- Admin widgets: add / edit / delete a one-off writes only `notifySchedule`; sent rows read-only; preview text;
  validators (title required, link invalid, sendAt in the past warns).
- Node: sender skips when `push` false; sends due one-off to `web_announcements_ar`/`_en` and
  `app_announcements_ar`/`_en` per targets and language (Arabic text to `_ar`, English to `_en`, fallback to
  Arabic when English blank); never twice (dedup); trims log to 60; daily web verse once per day after its time;
  no daily web sends 22:00–06:00; FCM error recorded as `error:<code>`; dry run sends nothing.
- Deep links: router receives `/page/x`; deleted page → 404 widget; external non-live URL → `/`.
- Rules emulator: as in §5.

## ١١. اختبار يدوي (Manual QA)

| # | Scenario | Expected |
|---|---|---|
| 1 | Admin creates a one-off for now+5 min to a test topic (dry run off) | Android test phone (subscribed via a debug toggle to the test topic) gets it within ~30 min; tap opens the link |
| 2 | Same with the app killed | arrives; tap cold-starts on the page |
| 3 | Quiet hours on the phone | arrives silently, listed in the inbox |
| 4 | Edit the one-off before it is sent | new text sent |
| 5 | Delete before sent | nothing sent |
| 6 | Change verse time in «أنواع الإشعارات» | Android re-plans (next verse at the new time) |
| 7 | Untick «آية اليوم» as offered | disappears from users' pages; Android cancels its alarms |
| 8 | Link to a page then delete that page | tap → «الصفحة غير موجودة» + Home |
| 9 | `push` off | sender logs "push off", nothing sent |
| 10 | English user | English text (or Arabic fallback) |
| 11 | Admin UI at 320 px / tablet / desktop | usable; no overflow |

## ١٢. CI — `.github/workflows/push-sender.yml`

```yaml
name: Push sender (FCM)
on:
  schedule:
    - cron: '7,22,37,52 * * * *'   # every 15 min, off the top of the hour (GitHub delays busy minutes)
  workflow_dispatch:
    inputs:
      dry_run: { type: boolean, default: true }
      topic_override: { type: string, default: '' }
concurrency: { group: push-sender, cancel-in-progress: false }
permissions: { contents: read }
jobs:
  send:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with: { node-version: 22 }
      - run: npm install --no-audit --no-fund   # tool/ has no lockfile (as synaxarium.yml)
        working-directory: tool
      - name: Credentials
        env: { SA: '${{ secrets.FIREBASE_SA_PUSH }}' }
        run: printf '%s' "$SA" > "$RUNNER_TEMP/sa.json"
      - name: Send due notifications
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ runner.temp }}/sa.json
          DRY_RUN: ${{ github.event_name == 'schedule' && vars.PUSH_DRY_RUN || inputs.dry_run }}
          TOPIC_OVERRIDE: ${{ inputs.topic_override }}
        run: node tool/push_sender.js
      - if: always()
        run: rm -f "$RUNNER_TEMP/sa.json"
```
- Repo **variable** `PUSH_DRY_RUN` = `true` until launch day (then `false`).
- GitHub disables scheduled workflows after **60 days without repository activity** — the runbook (LAUNCH §10)
  covers re-enabling; any commit keeps it alive.
- `ci.yml`: add `node --test tool/push_sender.test.mjs` to the rules job (Node is already set up there).

## ١٣. التوثيق (Docs / ADR)

ADR-059: admin-managed types/one-offs inside `settings/features`; GitHub Actions cron sender (no Functions) with
honest 15–30 min latency; topics per platform/type/language; data-only messages on Android for quiet hours +
inbox; dedup log `pushSent`; deep links in-app only; messaging JS ignored at load. Arabic manual
`documentation/features/notifications.md` (admin how-to with the exact labels) + `operations.md` runbook.

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| Cron delay (5–30 min, occasionally skipped under load) | UI says so; time-critical items are local on Android; send-at a bit early |
| Service-account key leak | separate least-privilege SA, secret only in GitHub, rotate yearly (runbook) |
| Org policy blocks key creation | personal project (no organisation) — allowed; if blocked use Workload Identity Federation (documented alternative) |
| Duplicate on Android (FCM + local) | Android receives only `announcements` via FCM; other types local only |
| Template text too long | counters + preview + rules caps |
| Scheduled workflow disabled after 60 days idle | runbook monthly check; Sentry/GitHub email on failure |
| FCM topic fan-out latency | normal (seconds–minutes) |

## ١٥. ما يفعله المالك (Owner steps — click by click)

1. **Enable the API**: https://console.cloud.google.com/apis/library/fcm.googleapis.com?project=asafra-church-portal →
   **Enable** ("Firebase Cloud Messaging API"). (Firebase console → ⚙ Project settings → **Cloud Messaging** tab
   should then show "Firebase Cloud Messaging API (V1) — Enabled".)
2. **Service account**: https://console.cloud.google.com/iam-admin/serviceaccounts?project=asafra-church-portal →
   **+ Create service account** → name `push-sender` → **Create and continue** → roles: **Firebase Cloud Messaging
   API Admin** and **Cloud Datastore User** → **Done**.
3. Open `push-sender@…` → **Keys** → **Add key** → **Create new key** → **JSON** → download.
4. GitHub → repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** →
   `FIREBASE_SA_PUSH` = the whole JSON file content → **Add secret**. Delete the downloaded file from your computer
   (keep no copy; a new key can always be created).
5. Same page → **Variables** tab → **New repository variable** → `PUSH_DRY_RUN` = `true`.
6. GitHub → **Actions** → «Push sender (FCM)» → **Run workflow** (dry run ✓) → open the run → the summary lists what
   would be sent.
7. On launch day set `PUSH_DRY_RUN` = `false` and `/admin` → «الإشعارات» → «تشغيل الإشعارات» on.
