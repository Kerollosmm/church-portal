# PR C — مدير الإشعارات في لوحة التحكم + مُرسِل FCM + الروابط العميقة (Admin notification manager + FCM sender + deep links)

| | |
|---|---|
| Branch → base | `feat/p2c-notification-manager` → `feat/p2b-android-local-notifications` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-059** |
| Depends on | PR A (types, `push`, `pushTypes`), PR B (APK, local planner) |
| Owner console work | enable the FCM API, create the `push-sender` service account + secret `FIREBASE_SA_PUSH`; optional Sentry cron monitor (`SENTRY_CRONS_URL` secret) (§15) |
| Live effect after merge | admin screen visible; the sender runs but sends nothing while `push` is off |

> **Revised 8 Nov 2026 20:30 Africa/Cairo (Owner Architecture Lock — Supersedes any conflicting details below):**
> 1. **Cloudflare Worker Cron-Only Sender (`ADR-059`)**: Build `tool/firestore_rest.js`, `tool/push_sender.js`, `tool/push_daily.js`, and `tool/cf_push_worker.js` (+ `wrangler.toml` with `crons = ["*/15 * * * *"]`) using pure Web APIs (`fetch` + Web Crypto `crypto.subtle` RS256 JWT signing with `pemToDer`, stateless per run) and **zero native Node dependencies** so the exact same code runs on Cloudflare Workers and Node 22 CLI (`node --test tool/push_sender.test.mjs`). **No `POST /trigger` HTTP endpoint**. `.github/workflows/push-sender.yml` is **`workflow_dispatch` only** (no GitHub Actions cron). `.github/workflows/keepalive.yml` is scoped to `synaxarium.yml` only. Document Cloudflare Workers and the dedicated least-privilege `push-sender` service account (`roles/datastore.user` + `roles/firebasemessaging.admin`) in `ADR-059`.
> 2. **Defer `tool/push_reminders.js` to PR D (`feat/p2d-web-push`, `ADR-060`)**: Do **not** build `tool/push_reminders.js`, `tool/push_reminders.test.mjs`, or `test/occurrences_parity_test.dart` in PR C (APK reminders are local; web push subscribers do not exist until PR D).
> 3. **Firestore Spark Read Cost (~197 reads/day) & Subrequest Cap (≤ 25/run)**: Every 15-min run of `push_sender.js` performs 1 `:batchGet` reading `settings/features` and `settings/notifications` (2 reads/run = 192 reads/day). `push_daily.js` queries `seasons` (~5 docs) **only once per Cairo day** (after `seasons` time when `health.lastSeasonDate != todayCairoDate`). Cap each run at **16 FCM topic sends** (up to 4 event pushes × 4 topics) and **≤ 25 subrequests**.
> 4. **Schedule Lifecycle & `firestore.rules`**: Keep `status`, `reminderPlan`, `remindersSent`, and `health` strictly server/sender-only (`!changed.hasAny(['status', 'reminderPlan', 'remindersSent', 'health'])`, create-safe without referencing `resource.data` on create). Allow admins to **delete any row** from `settings/notifications.schedule` whose status is not `sending` (including `ok`, `partial`, `error`, `unconfirmed`, `expired`) so the 20-row limit never deadlocks. Drop partial-topic clearing from Admin UI; cloning a `partial`/`error`/`expired` row creates a new draft row (narrowing `targets` if only `web` or `app` failed). Add `notifyTypes` and `reminderSources` to `installPushKeys()` (not `legacyFeatureKeys()`).
> 5. **Canonical `EventKey` & Persistent `DayEvent.id` (`[a-z0-9]{8,10}`)**: Standardize `eventKey` regex on `^(|(lit|meeting|day|season)-[a-z0-9-]{1,40})$` (meetings use `meeting-<id>`, seasons use `season-<id>`, while `reminderSources` stays `'lit,mtg,day'`). Add a 17th field `id` (`[a-z0-9]{8,10}`) to `DayEvent.storedKeys` in `lib/domain/today.dart` and allow `(\x1f(|[a-z0-9]{8,10}))?` in `validDayEvent` in `firestore.rules`. New rows in `/admin` generate an 8-char `[a-z0-9]{8}` ID. Legacy rows without a stored `id` fall back to the 10-char lowercase hex SHA-1 prefix of `${dateIso}\u001f${start.trim()}\u001f${nfcNormalizeArabic(titleAr.trim())}` (with Unicode NFC normalization on `titleAr`). When an admin loads and saves an existing legacy `DayEvent` in `/admin`, persist its pre-edit 10-char hash as its stored `id` so its `day-<id>` reminder key never changes. No `day-e<index>` fallback.
> 6. **Android FCM (`lib/data/push_messaging.dart`)**: Annotate top-level background handler with `@pragma('vm:entry-point')`, persist the 100-item `seen_nids` ring buffer in `SharedPreferences` (`church_portal_seen_nids`), subscribe only to `app_announcements_<lang>` and `app_seasons_<lang>`, share `event:X` slot when a reminder for `X` is within ±60 min, route taps via `safeNotificationLink`, and set `window.flutterfire_ignore_scripts = ['messaging']` in `web/index.html`.

> **Revised 6 Nov 2026 19:31–19:35 (owner):** speed is not important — there is **no urgent / instant send**. The
> earlier dual trigger (`workflow_dispatch` from `/admin`, dispatch token in `admin_secrets/github_dispatch`, «إرسال
> عاجل الآن», `urgent` / `dispatch` fields) is **removed entirely**. Admin pushes go only through the scheduled sender;
> the focus is guaranteed delivery. New here: the **web reminder planner** (§16) and the **keep-alive + sender-health
> alert** (§17).

## ١. الهدف (Goal)

The admin, from the web `/admin` only, **decides which notification types exist and are offered, their texts,
times and reminder lead options**, and **creates / edits / deletes event pushes** — a normal push for an event or
occasion with title, body, an optional **deep link** (any page, or a specific event / service) and a **scheduled
time**. A free GitHub Action on a **cron every 15 min** sends them through **FCM topics** to the APK, browsers and the
installed iPhone PWA. It is **not urgent**: a push goes out at the first run at or after its time (normally within
15–30 min); what is guaranteed is that it **is** delivered — idempotent per-topic markers, retries, catch-up of
missed runs, and a visible sent / failed status. The same sender sends dynamic season alerts and the **web / iPhone
user reminders** («ذكّرني», §16). FCM carries **only remote (platform, type) pairs** (README §3.1); the Android app
keeps verse, Katameros, feasts and the user's own reminders **local** and never receives them by FCM. Tapping a
notification opens the chosen page on Android and (PR D) on the web / installed PWA.

## ٢. قصص المستخدم (User stories)

- كمشرف أفتح «الإشعارات» وأرى الأنواع الستة: أفعّل/أعطّل عرض كل نوع للزوار، أعدّل نص العنوان والرسالة بالعربي
  والإنجليزي، ووقت الآية والقطمارس والأعياد، وخيارات «ذكّرني» (في الموعد / قبل ١٥ دقيقة / قبل ساعة / قبل يوم).
- كمشرف أضيف إشعارًا لحدث: «نهضة السيدة العذراء — الليلة الساعة ٧ مساءً»، أحدد وقت الإرسال، وأختار الصفحة أو
  الحدث الذي يفتح عند الضغط من قائمة («مواعيد القداسات»، خدمة معيّنة من أسبوع الآلام، صفحة مخصصة…)، وأرى معاينة كما
  تظهر على الهاتف، ثم أحفظ.
- الشاشة تقول بوضوح: «يُرسل الإشعار خلال ١٥–٣٠ دقيقة تقريبًا من الموعد المحدد — المهم أنه يصل».
- أعدّل أو أحذف أي إشعار لم يُرسل بعد؛ أرى حالة كل إشعار («مجدول» ← «جارٍ الإرسال» ← «أُرسل» / «أُرسل جزئيًا» /
  «فشل — سيُعاد تلقائيًا» / «فات موعده») وسجل ما أُرسل.
- أرى «آخر تشغيل للمُرسِل: منذ ١٢ دقيقة»، وتحذيرًا أحمر إذا توقف أكثر من ٣ ساعات.
- «جرّب على هذا الجهاز» يعرض الإشعار على جهاز المشرف نفسه فورًا (بدون خادم).
- كمستخدم Android يصلني إشعار الكنيسة حتى لو كان التطبيق مغلقًا، والضغط يفتح الصفحة أو الحدث المختار.
- كمستخدم على iPhone (التطبيق المثبت) ضغطت «ذكّرني قبل ساعة» على صلاة الساعة السادسة يوم الجمعة العظيمة — يصلني
  التذكير (وقد يتأخر حتى ~٣٠ دقيقة كما قيل لي عند الاختيار).

## ٣. الخصائص الفرعية (Complete sub-features)

| Sub-feature | Detail |
|---|---|
| Types editor | 6 rows (fixed set). Per type: offered (writes `pushTypes`), time `HH:mm` (verse, Katameros, feasts, seasons), days before (seasons 0–7), title/body templates ar/en with placeholders, default link. Plus the «ذكّرني» card: lead options (`reminderLeads`, ≤ 4 of 0/5/10/15/30/60/120/180/1440 min) and default (`reminderDefaultLead`), and per source whether the button is shown (liturgies, meetings, today's events). Each card shows its **channel** (README §3.1): «محلي على تطبيق Android» for verse / Katameros / feasts, «محلي على Android، وعبر الإنترنت على الويب و iPhone» for reminders, «عبر FCM» for event pushes / seasons |
| Placeholders | `{verse}` `{ref}` (verse), `{reading}` `{ref}` (Katameros), `{season}` `{days}` (seasons), `{feast}` (feasts), `{event}` `{time}` `{place}` `{lead}` (reminders), `{date}` everywhere; unknown placeholders flagged by the validator |
| Event pushes (schedule) | stored in the **admin-only** doc `settings/notifications` (never streamed by visitors, unreadable by the public — unsent texts stay private); list ≤ 20; row = title ar/en (≤ 80), body ar/en (≤ 240), send-at (Cairo date + time picker, 12-hour UI / 24-hour stored like ADR-049; blank = «في أقرب دورة»), deep link (route / event picker), optional `eventKey` (set when an event / service is picked — README §3.1 rule 5), targets (web, app; default both). Always type `announcements` (no type field): a «feast» push would otherwise reach users who turned feasts off and duplicate the APK's local feast notification — word it as an event push |
| Route / event picker | existing `FieldDef.linkPicker` («اختر صفحة…»): built-in routes (`/`, `/mass-schedule`, `/mass-schedule?tab=seasons`, `/about`, `/church-education`, `/church-activities`, `/clinics`, `/public-services`, `/contact`, `/ask`, `/notifications`, `/readings`), custom pages `/page/<slug>`, categories `/section/<slug>`, item detail pages, plus a new group «حدث أو خدمة» listing liturgies (incl. season services), meetings and today's events → link to the item and `eventKey` (`lit-<id>`, `mtg-<id>`, `day-<hash10>`). Free text accepted if it passes the URL/path validator |
| Create / edit / delete | generic `objectList` editor (encoded rows), saved with `AdminRepository.saveDocsFresh` (fresh-read transaction, ADR-042) so the edited row is merged into the **latest** `schedule`; edit allowed until the first topic is claimed; the sender writes per-topic markers into the separate map field `status.<rowId>` (**never overwritten by an admin save** — Sentry round 2, §5); a sent row is read-only, delete allowed |
| Delivery (not urgent, guaranteed) | due = `sendAt <= now` (blank = due at once). **Catch-up:** every run sends everything due since the last successful run — a skipped / delayed / failed run loses nothing; a row more than **24 h** past `sendAt` and never claimed becomes `expired` («فات موعده ولم يُرسل» — the admin can copy it to a new time). **Retries:** transient FCM errors (`internal-error`, `unavailable`, `quota-exceeded`, HTTP 5xx / 429) are retried on the next runs, ≤ 3 attempts per topic, then `error:<code>` final; permanent errors not retried. **At most once per topic:** the claim transaction (§7) |
| Status (admin UI) | per row, from `status.<rowId>` (sender) → chip: «مجدول ١٠:٠٠ ص» (no status, future), «في الطابور» (due, not yet claimed — «يُرسل في الدورة القادمة»), «جارٍ الإرسال» (`sending`), «أُرسل ١٠:١٥ ص» (`ok`), «أُرسل جزئيًا» (`partial`, per-topic list), «فشل — سيُعاد تلقائيًا (محاولة ٢ من ٣)» (transient), «فشل: …» (final), «لم يُتأكد — راجِع ثم أعد الإرسال» (`unconfirmed`), «فات موعده» (`expired`). Buttons «أعد الإرسال» / «أعد إرسال الفاشل فقط». The open admin screen streams `settings/notifications`, so chips update live without polling |
| Sender health card | «آخر تشغيل للمُرسِل: منذ …» from `health.lastRunAt` (stamped hourly, §17); amber after 1 h, **red after 3 h** with «المُرسِل متوقف — راجع GitHub Actions» + link to the runbook (LAUNCH §14); also shows `health.lastError` (code only) and «آخر تخطيط للتذكيرات» |
| Preview | live card under the row: notification mock (seal icon, app name, title, body, «الآن») in Arabic and English, character counters, truncation warning (Android shows ~2 lines collapsed) |
| Test on this device | admin browser: `Notification.permission` → `registration.showNotification(...)` via the PR A service-worker scaffold (no server). If permission not granted, explains how |
| Sent log | `sentLog` (in `settings/notifications`) table: when, what (title), topic(s), result (`ok` / `partial` / `error:<code>`), run trigger (`cron` / `manual`). «مسح السجل» (owner only) |
| Kill switch | `push` off → the sender sends nothing (queue still drained) and the client UI hides |
| Quiet hours (server side) | the sender never sends **season alerts** between 22:00–06:00 Cairo (moved to 06:00); event pushes go when scheduled (admin's choice); web reminders go at their time (user's choice); Android / the SW apply the user's quiet hours on display (README §3.4 / §8 #18) |
| Android FCM | `firebase_messaging` subscribes **only to remote topics**: `app_announcements_<lang>` and `app_seasons_<lang>`; never a reminder topic (APK reminders are local, PR B §3.4). Unsubscribes on off / unsubscribe-all / language change. `topicFor(type, lang, platform)` throws for local-owned pairs (unit-tested). Data-only messages (`android.priority = high`) → background handler → **client guard** → local notification on the type's channel, honouring quiet hours (silent), stored in the inbox |
| Message payload | every FCM message is **data-only**: `type` (`announcements` \| `seasons` \| `reminders` — the last only on web topics), `nid` (row `id`; `season:<seasonId>:<yyyy-mm-dd>`; `rem:<eventKey>:<date>:<lead>`), `title`, `body`, `link`, `lang`, optional `eventKey`. No `notification` block |
| Client guard + dedupe | Android handler and web SW: (1) **drop** a message whose `type` is local-owned on that platform or unknown — Sentry breadcrumb `push.dropped_local_type` (no content); (2) **drop** a repeated `nid` (seen-set, last 100); (3) stable display id = hash(`nid`) / `tag: nid`; (4) a message with `eventKey` X uses the slot `event:X` when a reminder for X is within ±60 min (README §3.1 rule 5) — replaces, never stacks |
| Deep links | payload `data.link`; Android: `onMessageOpenedApp`, `getInitialMessage`, local `onDidReceiveNotificationResponse` → `router.go(safeNotificationLink(link))`; external https only for the live-stream link. Fallback: unknown / deleted page → 404 «الرجوع للرئيسية»; switched-off section → FeatureGate notice; removed event → the schedule page with «لم يعد هذا الحدث موجودًا» |
| Dedup (server) | event pushes: per-topic markers in `status.<rowId>` set by the claim transaction; a later run sees them and skips. Season alerts: key `season:<seasonId>:<date>` in `sentLog`, only today's items computed. Web reminders: `remindersSent.<slotKey>` (§16) |
| Local planner follows admin | PR B planner reads `notifyTypes`, `reminderLeads` and `pushTypes` from the already-streamed doc — re-plans on change |

## ٤. الشاشات (Screens — `/admin` → «الإشعارات», `Icons.notifications_active_outlined`)

1. Header card: switch «تشغيل الإشعارات» (`push`), **sender health** («آخر تشغيل: …», amber / red states), line
   «الإرسال مجدول كل ١٥ دقيقة — ليس فوريًا، والمهم أن يصل», link to the guide.
2. «أنواع الإشعارات» — 6 collapsible cards + the «ذكّرني» card (lead options, default, sources).
3. «إشعارات الأحداث» — list with «إضافة إشعار»; each row: preview, send-at, link / event, targets, status chip.
4. «سجل الإرسال» — table (latest first).
Implementation: a dedicated `NotificationsAdminScreen` composed of the generic `ChurchInfoScreen` pieces with
`notifyTypesDoc` (`DocDef('settings/features', …)`, fields `notifyTypes`, `reminderLeads`, `reminderDefaultLead`)
and `notifyScheduleDoc` (`DocDef('settings/notifications', …)`, field `schedule`) + read-only `sentLog` / `health`
widgets; each writes only its changed keys. `AdminRepository` gains read/write of `settings/notifications` (admin
session only).

## ٥. نموذج البيانات + القواعد (Data model + rules)

Two places (encoded rows, `␟` = U+001F, like `dayEvents`):

**Public — top-level keys of `settings/features`** (needed by the APK's local planner; templates are not secret):
```
notifyTypes:          'type␟time␟daysBefore␟titleAr␟titleEn␟bodyAr␟bodyEn␟link'   (≤ 6, unique type)
reminderLeads:        [0, 15, 60, 1440]        (PR A key; ≤ 4 unique ints from the allowed set)
reminderDefaultLead:  60                       (PR A key; must be in reminderLeads)
reminderSources:      'lit,mtg,day'            (which cards show «ذكّرني»; subset of lit|mtg|day)
```

**Admin-only — doc `settings/notifications`** (Sentry review on the plan PR: unsent pushes must not be publicly
readable, and the sender's writes must not wake every visitor's `settings/features` listener):
```
schedule:       'id␟sendAt␟titleAr␟titleEn␟bodyAr␟bodyEn␟link␟targets␟eventKey'   (≤ 20; always type announcements; ADMIN only)
                id = [A-Za-z0-9]{8} (random, never reused); sendAt = '' | 'YYYY-MM-DDTHH:mm' (Cairo wall time);
                targets = 'web,app' | 'web' | 'app'; eventKey = '' | (lit|mtg|day)-[a-z0-9-]{1,40}
status:         map rowId → { at, topics: { <topic>: 'sending' | 'ok' | 'retry:<n>:<code>' | 'error:<code>' | 'unconfirmed' }, result }
                (SENDER only; result = 'sending' | 'ok' | 'partial' | 'retrying' | 'error:<code>' | 'unconfirmed' | 'expired')
sentLog:        'key␟sentAtIso␟result␟title␟trigger'                    (≤ 60, newest first; SENDER)
reminderPlan:   'slotKey␟fireAtIso␟eventKey␟occurrence␟lead␟titleAr␟titleEn␟link'  (≤ 400; next 36 h; SENDER, §16)
remindersSent:  map slotKey → 'ok' | 'retry:<n>' | 'error:<code>' | 'late-skip'   (today + yesterday; SENDER, §16)
health:         { lastRunAt, lastPlanAt, lastError, queueToday, capReached }    (SENDER, stamped hourly, §17)
updatedAt, updatedBy                                                        (admin stamp, as other settings docs)
```
Dart: `NotifyConfig.fromFeatures(m)` + `NotifySchedule.fromDoc(m)` (`lib/domain/push.dart`), `ScheduledNotification`
(with `isExpiredAt(now)`), `SentEntry`, `SenderHealth`, `dueNow(...)`, `renderTemplate(...)`, `EventKey` (shared
with PR A / B / D: `eventKeyFor(liturgy|meeting|dayEvent)`, `day-` = first 10 hex of SHA-1 of `date␟start␟titleAr`).
The admin screen streams `settings/notifications` only while it is open (admins only).

Rules:
```
match /settings/{docId} {
  allow read: if docId != 'notifications' || isAdmin();          // was: if true
  allow create, update: if isAdmin() && (… existing docs …
      || (docId == 'notifications' && validNotifications(request.resource.data)));
  allow delete: if false;
}
// in validFeatures:
&& (!('notifyTypes' in changed) || validNotifyTypes(d))
&& (!('reminderSources' in changed) || d.reminderSources.matches('^(lit|mtg|day)(,(lit|mtg|day)){0,2}$'))
function validNotifications(d) {
  let changed = changedKeys(d);
  return keysAllowed(['schedule', 'status', 'sentLog', 'reminderPlan', 'remindersSent', 'health',
                      'updatedAt', 'updatedBy'])
    && (!('schedule' in changed) || validNotifySchedule(d))
    // admins may only REMOVE status entries («أعد الإرسال»); only the sender (Admin SDK) adds / changes them
    && (!('status' in changed) || (resource != null
          && d.get('status', {}).diff(resource.data.get('status', {})).addedKeys().size() == 0
          && d.get('status', {}).diff(resource.data.get('status', {})).changedKeys().size() == 0))
    // sender-only fields: admins may only clear the log (owner button); never touch plan / sent markers / health
    && (!('sentLog' in changed) || d.get('sentLog', []).size() == 0)
    && !changed.hasAny(['reminderPlan', 'remindersSent', 'health'])
    && (!changed.hasAny(['updatedAt', 'updatedBy']) || stampOk(d));
}
```
`validNotifyTypes`: list ≤ 6, joined with `\u001e`, one regex:
`(announcements|verse_daily|katameros_daily|seasons|feasts|reminders)\x1f(|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9])\x1f[0-7]?\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{0,240}\x1f[^\x1f\x1e]{0,240}\x1f(|/[^\x1f\x1e ]{0,300}|[Hh][Tt][Tt][Pp][Ss]://[^\x1f\x1e ]{1,300})`
repeated `{0,5}` after `\x1e`. `validNotifySchedule`: list ≤ 20, same technique:
`[A-Za-z0-9]{8}\x1f(|20[2-9][0-9]-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9])\x1f[^\x1f\x1e]{1,80}\x1f[^\x1f\x1e]{0,80}\x1f[^\x1f\x1e]{1,240}\x1f[^\x1f\x1e]{0,240}\x1f(link)\x1f(web,app|web|app)\x1f(|(lit|mtg|day)-[a-z0-9-]{1,40})`.
Impossible calendar dates (31 Feb) cannot be expressed in a regex: the admin date picker cannot produce them,
`admin_validators.dart` rejects them, and the sender marks an unparsable `sendAt` `error:bad-date` instead of sending.
**No lost updates between admin and sender** (Sentry round 2): admin and sender never write the same field. The
admin UI saves with field-level `update({schedule, updatedAt, updatedBy})` (never `set` of the whole doc), so a save
cannot touch `status`, `sentLog`, `reminderPlan`, `remindersSent` or `health`; «أعد الإرسال» writes only
`update({'status.<rowId>': FieldValue.delete()})` (or only the non-`ok` topic keys). The sender writes only its own
fields (claim + result in a transaction that reads `schedule` + `status`), never `schedule`. Edits of a row after its
first claim are ignored for sending (the UI turns the row read-only as soon as the streamed `status` shows it). Two
admins editing `schedule` at once: `saveDocsFresh` merges into the fresh `schedule` and aborts with «تغيّرت
القائمة، أعد الفتح» if the same row changed since it was loaded. The sender removes `status` keys whose row no
longer exists when it writes anyway (garbage). Emulator tests: valid rows pass; `javascript:` link, 21 rows, bad
date, oversize text, bad `eventKey`, stranger write → denied; an admin adding a non-empty `sentLog` → denied,
clearing it → allowed; an admin adding or changing a `status` entry → denied, removing one → allowed; an admin
writing `reminderPlan` / `remindersSent` / `health` → denied; a `schedule` save leaves sender fields untouched; **a
visitor (unauthenticated or non-admin) cannot read `settings/notifications`** while `settings/features` stays public;
unrelated `settings/features` saves still within budget.

## ٦. التكلفة (Cost)

| Item | Reads | Writes | Notes |
|---|---|---|---|
| Visitors | +0 | +0 | `notifyTypes` / reminder keys ride the existing `settings/features` stream; schedule, log, plan and markers live in the admin-only doc |
| Admin edits | — | 1 per save | |
| Sender run (every 15 min) | 2 (`settings/features`; `settings/notifications`) | 0, or 1–2 when something was sent (claim + result) | ≤ 192 reads/day |
| Reminder planner (first run of each hour, §16) | ≈ 65 (`liturgies` ~47, `meetings` ~11, `seasons` ~5, already-read docs reused) | 1 (`reminderPlan` + `health` in one update) | ≈ 1,560 reads + 24 writes/day; skipped when `push` is off or `reminders` is not offered |
| Web reminder sends | 0 extra | ≤ 1 per run that sent (`remindersSent` batch) | ≈ 100–200 FCM topic sends/day in a busy season (free) |
| FCM | — | — | free, no quota cost |
| GitHub Actions | — | — | free while the repo is public (~40 s/run); private → 15-min cron ≈ 2,900 min/month > 2,000 free → hourly cron (README §8 #15) |

Total sender side ≈ 1,750 reads + ≤ ~60 writes per day — under 4 % of Spark's daily reads; visitors never see these
writes (admin-only doc).

## ٧. الملفات (Files)

Create:
- `tool/push_sender.js` — Node 22, `firebase-admin` (Firestore read/write + `getMessaging().send`). Steps: (0)
  **always** drain `push_queue` first (PR D; subscription changes and unsubscribes are processed even while `push` is
  off, so tokens are deleted as promised — CodeRabbit); (1) load `settings/features` and `settings/notifications`;
  stop sending (not draining) if `push` false; (2) if this is the first run of the Cairo hour (or `lastPlanAt` > 70
  min old), run the **reminder planner** (§16) and stamp `health`; (3) compute due items: event pushes with no
  final status and `now − 24 h <= sendAt <= now` (older unclaimed rows → `expired`); **today's season alerts** via
  `tool/push_daily.js`, skipped if their key is in `sentLog`; **due web reminder slots** from `reminderPlan` (§16);
  **never** a verse / Katameros / feast message, and never an `app_*` reminder — `topicFor` refuses them; (4)
  **claim** each item **per topic** in a transaction before calling FCM (an event push goes to up to 4 topics:
  `app|web` × `ar|en`): mark `sending`, `send`, then `ok` / `retry:<n>:<code>` / `error:<code>`. **Partial-send
  recovery** (CodeRabbit round 2): next runs send only topics that are **unattempted** or in `retry` (transient:
  `messaging/internal-error`, `unavailable`, `quota-exceeded`, HTTP 5xx / 429 — at most 3 attempts per topic, then
  `error:<code>` final); topics already `ok` are never resent; permanent errors (`invalid-argument`, unknown topic…)
  are not retried; a topic still `sending` after 10 minutes (the run crashed between FCM and the write) becomes
  `unconfirmed` and is **never re-sent automatically** — a duplicate is worse than a rare unconfirmed send for a
  parish; the admin decides with «أعد الإرسال». Row `result` = `ok`, `partial`, `retrying`, `error:<code>`,
  `unconfirmed` or `expired`. (5) Sentry cron check-in `in_progress` at start, `ok` / `error` at the end (§17).
  Print a job summary (`$GITHUB_STEP_SUMMARY`) without tokens or personal data.
- `tool/push_daily.js` — **season alerts only**: season starts (and N days before, `notifyTypes.seasons.daysBefore`)
  from the `seasons` collection (read once per day, or reused from the planner's read), sent to `app_seasons_<lang>`
  and `web_seasons_<lang>`.
- `tool/push_reminders.js` — the web reminder planner + slot sender (§16): pure functions `occurrencesBetween(…)`
  (a JS port of `computeNextMass` / `occurrencesForDay` / `dayEvents` parsing / season `replacesRegular` rules,
  checked against a **Dart↔JS parity fixture** generated from `lib/domain/schedule.dart` in CI), `planSlots(…)`,
  `dueSlots(plan, now, sent)`, `topicsForSlot(…)`.
- `tool/push_sender.test.mjs`, `tool/push_reminders.test.mjs` (node:test, no network: fake messaging + fake
  Firestore objects), `test/fixtures/occurrences_parity.json` + `test/occurrences_parity_test.dart` (writes the
  fixture from Dart; the node test reads it).
- `.github/workflows/push-sender.yml` (§12), `.github/workflows/keepalive.yml` (§17).
- `lib/ui/admin/notifications_admin.dart`, `lib/data/push_messaging.dart` (Android FCM: init, topic sync,
  background handler — conditional import, web stub), `lib/domain/notify_config.dart` (or inside `push.dart`).
- `test/notify_config_test.dart`, `test/notifications_admin_test.dart`, `test/deep_link_test.dart`,
  `test/push_guard_test.dart` (local-owned type dropped per platform, seen `nid` dropped, unknown type dropped,
  `event:X` slot shared with a reminder).
- `documentation/features/notifications.md` (Arabic admin manual), ADR-059.

Modify:
- `pubspec.yaml`: `firebase_messaging: ^17.0.1` (compatible with `firebase_core ^5.1.0`).
- **`web/index.html`**: `window.flutterfire_ignore_scripts = ['messaging'];` before Flutter boots — the
  `firebase_messaging_web` plugin would otherwise make `firebase_core_web` inject the messaging JS SDK on **every
  page load** (PageSpeed). PR D loads it lazily on tap instead. Verify in DevTools → Network.
- `android/app/src/main/AndroidManifest.xml`: default channel meta-data
  `com.google.firebase.messaging.default_notification_channel_id = announcements`, default icon `ic_stat_seal`.
- `android/app/google-services.json` (public config) + Gradle plugin `com.google.gms.google-services` **only if**
  background messages fail without it (test on a real device first; record in ADR-059).
- `lib/main.dart` (`FirebaseMessaging.onBackgroundMessage` top-level handler on Android only), `lib/router.dart`
  (initial link from `getInitialMessage`), PR B planner (reads `notifyTypes`, reminder keys).
- `lib/ui/admin/admin_page.dart` (destination), `lib/ui/admin/admin_schema.dart` (`notifyDoc`, «ذكّرني» card,
  health card), `lib/ui/admin/admin_validators.dart` (template placeholders, sendAt in the past warning, `eventKey`).
- `firestore.rules`, `tool/rules_test/rules.test.mjs`, `tool/package.json` (`firebase-admin ^13.0.0` is already a
  dependency; add a `test` script).
- Docs: memory bank 04/05/07/08/10/11, `documentation/operations.md` (sender + keep-alive runbook),
  `documentation/en/*`.

## ٨. الحزم (Packages)

| Package | Version | Where |
|---|---|---|
| `firebase_messaging` | `^17.0.1` | Flutter (Android FCM; web plugin registered but its SDK ignored on load) |
| `firebase-admin` (npm) | `^13.0.0` (already in `tool/package.json`) | `tool/` (sender) |

## ٩. خطوات التنفيذ (Step-by-step)

1. Domain: `NotifyConfig`, encode/decode rows, templates, `dueNow`, dedup keys, `EventKey` + tests.
2. Rules + emulator tests.
3. Admin screen (types, «ذكّرني» card, event pushes with route / event picker, preview, status chips, health card,
   test-on-device, log) + widget tests.
4. Sender (`tool/push_sender.js`, `tool/push_daily.js`) + node tests (claim, retries, catch-up, expiry, guard).
5. Reminder planner (`tool/push_reminders.js`) + Dart↔JS occurrence parity fixture + node tests (§16).
6. Workflow `push-sender.yml` (cron + manual `workflow_dispatch` with `dry_run` default true, `topic_override`) — prints
   what it *would* send; `keepalive.yml` (§17); Sentry cron monitor check-ins (§17).
7. Android FCM (`lib/data/push_messaging.dart`): topic sync, data-message handler → local notification, inbox entry,
   deep link; `flutterfire_ignore_scripts` on web.
8. Deep-link handling for local + FCM taps; fallback tests.
9. Docs + ADR-059. Owner sets up the service account (§15), runs the workflow manually with `dry_run=true`, then
   `false` with `PUSH_TEST_ENABLED=true` and input `topic_override=test_<random>` (fixed test message, no row claimed;
   §12); set `PUSH_TEST_ENABLED` back to `false` afterwards.

## ١٠. الاختبارات (Tests)

- Dart: rows round-trip, invalid rows dropped, template rendering ar/en with missing values, `dueNow` (past,
  future, blank = now, already sent, > 24 h → expired), Cairo times across the summer-time switch,
  `safeNotificationLink` with every picker output, `eventKeyFor` stable for liturgies / meetings / day events.
- Admin widgets: add / edit / delete an event push writes only `settings/notifications.schedule` (field-level update;
  a concurrent sender `status` write survives the save — fake Firestore test); sent rows read-only; status chips
  for every `result`; health card amber after 1 h / red after 3 h; preview text; validators.
- Node (delivery guarantee): a row due at 10:00 with the 10:07 run **skipped** → sent by the 10:22 run (catch-up);
  a row due yesterday 09:00, first run today 08:00 (23 h) → sent; 25 h → `expired`, never sent; FCM 503 on one topic
  → `retry:1`, next run sends only that topic, 3 failures → `error:<code>` final, row `partial`; permanent error →
  not retried; crash after `send` before the write → `unconfirmed`, not retried; «أعد إرسال الفاشل فقط» clears only
  non-ok topics; a sent row is never re-sent even after its log entry is evicted or the log is cleared.
- Node (topic override): override run sends only the fixed test text to `test_*`, writes nothing to `status` /
  `sentLog`, refuses a non-`test_` topic and refuses to run unless `PUSH_TEST_ENABLED=true`.
- Node (segregation): a message of type `verse_daily` / `katameros_daily` / `feasts` can never be built; `reminders`
  only to `web_rem_*` topics, never `app_*`; every message data-only with `type` + `nid`.
- Node: queue drained while `push` is off; sender skips when `push` false; sends due rows to
  `web_announcements_ar`/`_en` and `app_announcements_ar`/`_en` per targets and language (Arabic text to `_ar`,
  English to `_en`, fallback to Arabic when English blank); trims log to 60; season alert once per day after its
  time; no season alerts 22:00–06:00; dry run sends nothing; health stamped hourly; Sentry check-in URL absent → no
  error.
- Reminder planner: §16 tests.
- Deep links: router receives `/page/x`; deleted page → 404 widget; removed event → schedule page notice;
  external non-live URL → `/`.
- Rules emulator: as in §5.

## ١١. اختبار يدوي (Manual QA)

| # | Scenario | Expected |
|---|---|---|
| 1 | `PUSH_TEST_ENABLED=true`, manual run with `topic_override=test_<random>` (dry run off) | Android test phone (subscribed via a debug toggle to the test topic) gets the fixed test message; no schedule row changes |
| 2 | Admin creates an event push for now+5 min with a link to a Holy Week service (dry run off, test phone on the real topic in a debug build) | arrives within ~30 min; tap opens the service |
| 3 | Same with the app killed | arrives; tap cold-starts on the page |
| 4 | Disable `push-sender.yml` for 40 min around a row's time, re-enable | the next run sends it once (catch-up); chip «أُرسل» |
| 5 | Quiet hours on the phone | arrives silently, listed in the inbox |
| 6 | Edit the push before it is sent | new text sent |
| 7 | Delete before sent | nothing sent |
| 8 | Change the verse / Katameros time in «أنواع الإشعارات» | Android re-plans (next one at the new time) |
| 9 | Untick «قراءات اليوم» as offered | disappears from users' pages; Android cancels its alarms |
| 10 | Link to a page then delete that page | tap → «الصفحة غير موجودة» + Home |
| 11 | `push` off | sender logs "push off", nothing sent |
| 12 | English user | English text (or Arabic fallback) |
| 13 | Admin UI at 320 px / tablet / desktop | usable; no overflow |
| 14 | 4-topic push with one topic forced to fail (fake / test project) | «أُرسل جزئيًا»; next run retries only that topic |
| 15 | Admin push for event X while the phone has a reminder for X due 20 min later | one notification slot `event:X` (replaced, not stacked); both in the inbox |
| 16 | No sender run for 3 h (workflow disabled on a test fork) | `/admin` red health card; Sentry missed check-in e-mail |

## ١٢. CI — `.github/workflows/push-sender.yml`

```yaml
name: Push sender (FCM)
on:
  schedule:
    - cron: '7,22,37,52 * * * *'   # every 15 min, off the top of the hour (GitHub delays busy minutes)
  workflow_dispatch:               # owner's manual runs from the GitHub UI only (dry run / test topic)
    inputs:
      dry_run: { type: boolean, default: true }
      topic_override: { type: string, default: '' }      # test topic only, see below
concurrency: { group: push-sender, cancel-in-progress: false }   # one run at a time; never cancel a run mid-send
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
          # scheduled runs follow the repo variable; only a hand-started run uses its input
          DRY_RUN: ${{ github.event_name == 'schedule' && vars.PUSH_DRY_RUN || inputs.dry_run }}
          TOPIC_OVERRIDE: ${{ inputs.topic_override }}
          TRIGGER: ${{ github.event_name == 'schedule' && 'cron' || 'manual' }}
          SENTRY_CRONS_URL: ${{ secrets.SENTRY_CRONS_URL }}   # optional (§17)
        run: node tool/push_sender.js
      - if: always()
        run: rm -f "$RUNNER_TEMP/sa.json"
```
- Repo **variable** `PUSH_DRY_RUN` = `true` until launch day (then `false`).
- GitHub disables scheduled workflows of a public repo after **60 days without repository activity** → `keepalive.yml`
  (§17); never dummy commits.
- `ci.yml`: add `node --test tool/push_sender.test.mjs tool/push_reminders.test.mjs` to the rules job (Node is
  already set up there) and the occurrence parity check.
- **Concurrency:** GitHub keeps at most one *running* and one *pending* run per group; a newer pending run replaces an
  older pending one. Safe here because every run processes **everything** due (catch-up) and the claim transaction
  prevents double sends.
- Optional speed-up: commit `tool/package-lock.json` and use `npm ci` + `actions/setup-node` `cache: npm` (saves
  ~10–20 s per run; not required — speed is not a goal).
- `TRIGGER` (`cron` / `manual`) is printed in the job summary and the log.
- **`topic_override` safeguards** (CodeRabbit round 2): an override run (a) requires the repo **variable**
  `PUSH_TEST_ENABLED=true` — set by the owner only while testing; (b) accepts only `^test_[a-z0-9]{6,20}$`; (c) never
  reads or claims production rows: it sends one fixed built-in test message («رسالة تجريبية من الكنيسة», link `/`)
  and writes nothing to `status` / `sentLog`. Scheduled runs ignore `topic_override`. Only people with write access
  to the repo can start a manual run (no token exists any more).

## ١٣. التوثيق (Docs / ADR)

ADR-059: admin-managed types, reminder leads and event pushes; GitHub Actions sender on a **cron only** (no
Functions, **no instant / urgent path** — owner 19:31: speed is not important, delivery is) with per-topic
claim markers, retries, catch-up and expiry; web reminder planner over per-event topics (§16); keep-alive workflow
and sender-health alert (§17); strict channel segregation per platform (data-only messages with `type` + `nid`,
client guard, `event:X` slot); topics per platform / type / language; one-offs kept in the admin-only
`settings/notifications`; deep links in-app only; messaging JS ignored at load. Arabic manual
`documentation/features/notifications.md` (admin how-to with the exact labels) + `operations.md` runbook.

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| Cron delay (5–30 min, occasionally longer under GitHub load) | accepted by the owner (19:31); UI says «خلال ١٥–٣٠ دقيقة تقريبًا»; catch-up sends late rather than never; web reminders say «قد يتأخر حتى ~٣٠ دقيقة» + calendar link for exact time |
| Scheduled workflow disabled after 60 days idle / GitHub outage | `keepalive.yml` monthly re-enable (§17); health card red after 3 h; Sentry missed check-in e-mail; LAUNCH §14 runbook |
| Service-account key leak | separate least-privilege SA, secret only in GitHub, rotate yearly (runbook) |
| Org policy blocks key creation | personal project (no organisation) — allowed; if blocked use Workload Identity Federation |
| Duplicate on Android (FCM + local) | strict ownership per platform (README §3.1): no `app_*` topic for local types; `topicFor` throws; client guard; `nid` seen-set + stable ids; `event:X` slot for push + reminder |
| Planner's JS port of the schedule rules drifts from Dart | Dart↔JS parity fixture in CI (§16); a drift fails CI |
| Reminder for an event the admin moved / deleted after the plan | the planner re-plans every hour; a slot is re-validated against the latest plan right before sending; deleted event → no send |
| Template text too long | counters + preview + rules caps |
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
   `FIREBASE_SA_PUSH` = the whole JSON file content → **Add secret**. Delete the downloaded file from your computer.
5. Same page → **Variables** tab → **New repository variable** → `PUSH_DRY_RUN` = `true`.
6. (Optional, recommended) **Sentry cron monitor** (the free plan includes one — https://docs.sentry.io/pricing/):
   Sentry → **Crons** → **Add monitor** → name `push-sender`, schedule crontab `7,22,37,52 * * * *` (UTC), check-in
   margin 60 min, max runtime 10 min, alert «after 3 consecutive missed / failed check-ins» → e-mail the owner →
   copy the **HTTP check-in URL** (`https://o<org>.ingest.sentry.io/api/<project>/cron/push-sender/<key>/`) → GitHub
   secret `SENTRY_CRONS_URL`.
7. GitHub → **Actions** → «Push sender (FCM)» → **Run workflow** (dry run ✓) → open the run → the summary lists what
   would be sent.
8. (Recommended hygiene, not required — README §8 #19) GitHub → Settings → Environments → `production` → Required
   reviewers → add yourself (LAUNCH §14).
9. On launch day set `PUSH_DRY_RUN` = `false` and `/admin` → «الإشعارات» → «تشغيل الإشعارات» on.

## ١٦. تذكيرات الويب و iPhone «ذكّرني» (Web reminder planner + slot sender)

**Why this design (Spark, no Functions):** browsers cannot schedule a notification themselves; storing every
browser's reminders in Firestore would cost N reads per sender run. Instead each reminder is an **FCM topic
subscription** and the sender sends to topics on a schedule — **no reminder data is stored in Firestore**, nobody's
choices are readable, and sending to a topic without subscribers is free and harmless.

- **Topic per (event occurrence, lead, language):**
  - once: `web_rem_<eventKey>-<yyyymmdd>_<lead>_<lang>` (e.g. `web_rem_lit-hw-friday-20270430_60_ar`);
  - every time (recurring service): `web_rem_<eventKey>_<lead>_<lang>`.
  `eventKey` = `lit-<docId>` | `mtg-<docId>` | `day-<sha1-10>`; `lead` ∈ `reminderLeads` (minutes). FCM topic names
  allow `[a-zA-Z0-9-_.~%]` — all keys are lower-case `[a-z0-9-]`.
- **Planner (first run of each Cairo hour):** reads `liturgies`, `meetings`, `seasons` (+ `dayEvents` from the
  already-read `settings/features`), computes occurrences in the next **36 h** with the same rules as the app (active
  seasons, `replacesRegular`, `replacesDay`, `replaceDates`, hidden items excluded — JS port checked by a Dart↔JS
  parity fixture), filters by `reminderSources`, and for each occurrence × each lead in `reminderLeads` writes a slot
  `slotKey = <eventKey>:<yyyymmdd>:<lead>`, `fireAt = start − lead`, titles and link → `reminderPlan` (≤ 400 slots;
  a busy Holy Week day ≈ 12 services × 4 leads = 48 slots/day). One update per hour (+ `health.lastPlanAt`).
- **Slot sender (every run):** due slots = `fireAt − 5 min <= now` and not in `remindersSent`; for each: send to the
  **once** topic and the **every-time** topic, `ar` and `en` (4 sends), data-only `type: reminders`, `nid:
  rem:<slotKey>`, `eventKey`, title «تذكير: {event}» / body «{time} — {place}» (template from `notifyTypes`), link to
  the item. The device dedupes the two topic copies by `nid` (same `tag`). Result into `remindersSent.<slotKey>`
  (one batched update per run). Transient errors → retried next run (≤ 3).
- **Catch-up and lateness:** a slot whose run was missed is still sent while useful — until the event's **start**
  for leads ≥ 15 min, or until **start + 15 min** for «في الموعد»; after that it is marked `late-skip` (a reminder
  after the service ended helps nobody). Expected lateness = cron cadence + GitHub delay: normally 0–20 min, worst
  case ~30 min+; **the UI states it** (PR D §3.2).
- **Edits / removal:** the hourly re-plan follows admin changes; right before sending, the slot is re-checked against
  the current plan (and the row's item still exists and is visible); a moved event gets new slots (same topic names,
  so subscribers follow automatically when `eventKey` is unchanged); a removed event → nothing sent. Day events whose
  title / date / time changes get a new `day-` key — the web client notices the missing key on the next visit and
  shows «تغيّر الحدث — أعد ضبط التذكير» in «تذكيراتي».
- **Clean-up:** `remindersSent` retains all entries with `occurrenceDate >= yesterday` (yesterday, today, and tomorrow — pruned by the planner only when `occurrenceDate < yesterday`, so a `lead = 1440` reminder sent today for tomorrow's liturgy is never pruned while tomorrow's occurrence is still in the 36 h window). Browsers unsubscribe expired
  once-topics on their next visit (PR D) — stale subscriptions are harmless (the topic is never sent again) and far
  below FCM's 2,000-topics-per-instance limit.
- **Cost:** see §6 — planner ≈ 1,560 reads/day, ≤ ~30 writes/day; FCM sends free.
- **Tests (`tool/push_reminders.test.mjs`):** occurrences for a Holy Week day (season replaces regular schedule),
  an additive revival evening, a `replacesDay` feast liturgy, a `dayEvents` item, hidden items excluded; Cairo DST
  nights; slots per lead; due window (`fireAt − 5 min`); missed run → sent before start, `late-skip` after; both
  topics sent with one `nid`; slot sent once across runs; deleted event → not sent; `remindersSent` pruned only for `occurrenceDate < yesterday` (a `1440` min lead sent today for tomorrow's liturgy survives hourly re-plans); parity
  fixture matches Dart for 60 sample days.

## ١٧. استمرار التشغيل وتنبيه التوقف (Keep-alive + sender-health alert — owner 19:35)

**Problem:** GitHub disables scheduled workflows in a public repository after **60 days without repository
activity** (https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/disabling-and-enabling-a-workflow).
A quiet repo would silently stop the sender, `synaxarium.yml` and the readings publisher.

**Keep-alive without commits — `.github/workflows/keepalive.yml`:**
```yaml
name: Keep scheduled workflows enabled
on:
  schedule:
    - cron: '17 4 1 * *'          # monthly, 1st day 04:17 UTC
  workflow_dispatch: {}
permissions: { actions: write, contents: read }
jobs:
  enable:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - env: { GH_TOKEN: '${{ github.token }}' }
        run: |
          for wf in push-sender.yml synaxarium.yml; do
            gh api -X PUT "repos/${GITHUB_REPOSITORY}/actions/workflows/$wf/disable" || true
            gh api -X PUT "repos/${GITHUB_REPOSITORY}/actions/workflows/$wf/enable" && echo "toggled $wf"
          done
          gh api -X PUT "repos/${GITHUB_REPOSITORY}/actions/workflows/keepalive.yml/enable" && echo "enabled keepalive.yml"
```
- Uses the documented **Disable / Enable a workflow** endpoints (`PUT /repos/{owner}/{repo}/actions/workflows/{workflow_id}/disable` + `/enable`,
  needs `actions: write` — https://docs.github.com/en/rest/actions/workflows#enable-a-workflow) with the run's own
  `GITHUB_TOKEN`: no personal token, no dummy commit, nothing pushed to `main`. Toggling `disable` → `enable` on
  `push-sender.yml` and `synaxarium.yml` forces a real state transition (whereas a bare `PUT .../enable` on an
  already-enabled workflow can be a no-op that does not reset the 60-day schedule timer), and also re-enables a
  workflow GitHub already disabled.
- **Not trusted blindly:** because GitHub Actions runs using `GITHUB_TOKEN` may not count as user-initiated repository
  activity if the repo goes completely untouched for 60 days, the first 60-day window after launch is watched
  (LAUNCH §14); if GitHub ever disables `keepalive.yml` itself at day 60, the fallbacks below (`push-sender` Sentry
  cron monitor + `/admin` red health card) catch the stop within hours, and the owner re-enables with one click.

**Sender-health alert (layers):**
1. **`/admin` health card** (§3): `health.lastRunAt` stamped by the sender at least hourly; amber > 1 h, **red > 3 h**
   («المُرسِل متوقف منذ … — راجع GitHub Actions») — seen by any admin opening «الإشعارات».
2. **Sentry cron monitor** `push-sender` (free plan includes one): check-in `in_progress` / `ok` / `error` from
   `push_sender.js` via `SENTRY_CRONS_URL` (plain `fetch`, no SDK; failure to reach Sentry never fails the run);
   alert after 3 consecutive missed or failed check-ins (≈ 45 min) **or** when no check-in for 3 h → e-mail to the
   owner. Covers "workflow disabled", "secret broken", "Firestore errors".
3. **Web app Sentry breadcrumb**: when an admin's `/admin` sees `lastRunAt` > 3 h, it reports one Sentry message
   `push.sender_stale` (tag `section: push`, once per admin session) so the issue shows up even without the cron
   monitor.
4. **GitHub e-mails**: failed-run notifications (LAUNCH §11) and GitHub's own warning before it disables a workflow.
