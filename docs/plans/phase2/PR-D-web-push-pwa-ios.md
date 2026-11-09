# PR D — إشعارات الويب + التطبيق المثبت على iPhone (Web push, PWA, iPhone)

| | |
|---|---|
| Branch → base | `feat/p2d-web-push` → `feat/p2c-notification-manager` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-060** |
| Depends on | PR A (prefs page, `pushVapidKey`, SW scaffold), PR C (sender, topics, deep links) |
| Owner console work | generate the **VAPID** key pair and paste the public key in `/admin` (§15) |
| Live effect after merge | nothing until `push` is on **and** `pushVapidKey` is set |

> **Revised 9 Nov 2026 13:02 Africa/Cairo (Owner Architecture Lock & PR C Alignment — Supersedes conflicting details below):**
> 1. **Cloudflare Worker 3-Cron Architecture, `PUSH_KV` Token Cache & Cold-Start 10 ms CPU Gate (`ADR-059` → `ADR-060`)**:
>    - Fix the inaccurate comment in `tool/push_sender.js` line 53: Cloudflare Workers Free Tier allows **50 external `fetch` subrequests** and **10 ms CPU time** per invocation (**Error 1102** when exceeded), and up to **5 cron triggers across the entire Cloudflare account** (verify no other Workers on the account exceed 5 total crons before deploy).
>    - Split `wrangler.toml` into 3 dedicated crons so each workload gets an isolated 50-subrequest and 10 ms CPU budget:
>      1. `*/15 * * * *` (**Delivery Cron**): `push_sender.js` (priority: announcements first, daily seasons second, due web reminders from `meta/push_plan.reminderPlan` third). For web reminders, sort due `(slot, lead)` items by **`serviceStartMs ASC`** first (earliest upcoming service prioritized on busy Sundays), combine once-off + recurring topics for each language into a **single FCM v1 message** using `condition: "'web_rem_x_20261115_60_ar' in topics || 'web_rem_x_60_ar' in topics"` (or `topic` when only 1 topic is active — halving subrequests and preventing double pushes), stamp `remindersSent` (`${tKey}:${yyyymmdd}:${lead}:${lang}`) **only for sends that actually succeeded**, and roll remaining items over to the next 15-min tick. Inject top-level `webpush: { headers: { Urgency: 'high', TTL: ttlSeconds } }` in `sendFcmMessage` with **per-type TTL**:
>         - `reminders`: seconds until service start (`String(Math.max(300, Math.floor((serviceStartMs - nowMs) / 1000)))`, 5-min floor for `0`-lead «في الموعد» reminders so reminders never arrive hours after a service).
>         - `seasons`: seconds until `23:59:59 Africa/Cairo` end of day (`String(Math.max(300, secondsUntilCairoEndOfDay(nowMs)))`).
>         - `announcements`: `'86400'` (24 h).
>      2. `7,22,37,52 * * * *` (**Queue Drain Cron**): Queries at most **`limit = 60`** `push_queue` docs (`createdAt ASC`; if empty, exits immediately with **0** `:batchGet` calls on `meta/*`). Evicts poison/stale docs older than **7 days** or failing transiently **>= 30 times** (`meta/push_topics.retryCounts`, incrementing `cronQueue.queueFailedCount`). Drains remaining docs via Google IID REST (`POST https://iid.googleapis.com/iid/v1:batchAdd` and `v1:batchRemove` with `Authorization: Bearer <token>`, `access_token_auth: true`, and `"to": "/topics/" + topicName`), inspecting per-token `results[i].error`, capped at `MAX_IID_CALLS_PER_RUN = 20` topics/run, batch-deleting completed/evicted queue docs via `POST .../documents:commit` (`commitWrites` in `tool/firestore_rest.js`, 1 subrequest), copying `rateDay` / `rateCount` / `capReached` (`rateCount >= 1000`) into `meta/push_topics.cronQueue`, and pre-rolling `meta/push_rate` after `00:00 UTC`.
>      3. `3 2,8,14,20 * * *` (**Occurrence Planner Cron — UTC, 4×/day**: `04:03, 10:03, 16:03, 22:03` Cairo winter `UTC+2`; `05:03, 11:03, 17:03, 23:03` Cairo summer DST `UTC+3`): Runs `tool/push_reminders.js` (deferred from PR C, ~63 docs × 4 = ~252 reads/day). Document in `/admin` and `documentation/` that mid-day admin schedule edits take ~2–6 hours to reflect in web reminder plans.
>    - **Two-Tier OAuth2 Token Cache & Authoritative CPU Verification**: Because 15-min crons frequently cold-start across 3 separate schedules, keep Worker module scope as L1 cache and store the minted Google OAuth2 access token in **Cloudflare Workers KV** (`PUSH_KV` binding in `wrangler.toml`, `expirationTtl: 3300` = 55 min, ~26 KV writes/day vs 1,000 free; graceful fallback when `PUSH_KV` is absent in Node tests). Keep the Node timing test as a coarse guard, and measure real Worker CPU via **`npx wrangler dev --test-scheduled`** across all 3 crons + **Cloudflare Workers Logs (`CPU Time < 10 ms`)** immediately after `wrangler deploy`.
> 2. **True Single-Writer Metadata Docs (`meta/push_topics` + `meta/push_plan`) & Non-Expiring Recurring Hints**:
>    - Do **not** store `activeRemTopics` or `reminderPlan` inside `settings/notifications` (avoids write conflicts with `/admin` `saveDocsFresh` and Cron 1). Split metadata by single writer:
>      - **`meta/push_topics`** (sole writer: Cron 2 Queue Drain): `topics` presence map + `cronQueue` health (`lastDrainAt`, `queueProcessedCount`, `queueFailedCount`, `lastIidError`). Note: topic names contain `-`, so any `updateMask.fieldPaths` patch on `topics` must escape keys in backticks (`` topics.`web_rem_lit-x_60_ar` ``), or Cron 2 writes `meta/push_topics` directly as sole writer.
>      - **`meta/push_plan`** (sole writer: Cron 3 Planner): `reminderPlan`, `activeEventKeys`, and `lastPlanAt`.
>      - Cron 1 reads `[settings/features, settings/notifications, meta/push_plan, meta/push_topics]` in **one `:batchGet` subrequest** (+96 reads/day = ~0.2% of Spark; ~736 total reads/day across all 3 crons = ~1.5% of Spark). Both `meta/*` docs allow `read: if isAdmin(); write: if false;`.
>    - **No 30-Day Lease on Recurring Topics + Send-Time Hint Check**: Because web tokens only refresh on `/notifications`, `ReminderSheet`, or push deep-link opens, recurring topics (`web_rem_<key>_<lead>_<lang>`) have **no expiry** (`topics[t] = true`) and are removed only when the underlying service (`eventKey` absent from `activeEventKeys`) is deleted or its source is disabled (`drop` unsubscribes that browser's token in IID without deleting shared recurring topic flags while other subscribers may exist; once-off `<yyyymmdd>` keys auto-prune after `<yyyymmdd>`). Check the topic hint **at send time in Cron 1** (never at plan time in Cron 3) so visitors subscribing after the planner ran still receive their reminder; uninitialized `meta/push_topics` fails open (sends).
> 3. **`push_queue` + `iid/v1:batchAdd` Only & Strict iOS Visible-Push Compliance**:
>    - Implement only the `push_queue` topic pipeline (no `push_subscribers` fallback — YAGNI). Refresh tokens only on `/notifications`, `ReminderSheet`, or push deep-link opens (zero Firebase Messaging JS on casual visits).
>    - **Never skip `showNotification` in `web/firebase-messaging-sw.js`** (any skipped push = silent push = iOS revokes subscription):
>      - **Duplicate `nid`s (`seen_nids`)**: Do **not** skip; always call `showNotification` with `tag: nid` and `renotify: false` so it replaces the prior banner in place (deduplicating only the 30-item IndexedDB `inbox` append).
>      - **Quiet hours**: Pass `silent: true` on Chrome/Edge/Android/Desktop without suppressing `showNotification`; on iOS standalone PWAs (where WebKit ignores `silent` and forbids banner suppression), hide the «ساعات الهدوء» switch on `/notifications` and display a clear note explaining that iPhone notification silence is controlled via iOS Focus / Do Not Disturb.
>      - **Malformed / local-owned types**: Parse `payload.data || payload` inside `try/catch` and fall back to a visible «تحديث من الكنيسة» notice linking to `/`.
>    - Call `window.Notification.requestPermission()` **synchronously** inside the tap handler before awaiting lazy `/push_client.js`. In `web/push_client.js`, resolve the exact loaded Firebase JS SDK version via `window.firebase_core?.SDK_VERSION || window.flutterfire_web_sdk_version || '13.1.0'` (`13.1.0` verified in `firebase_core_web-4.1.0`), reuse `window.firebase_core` if already loaded by Flutter, and call **`appMod.getApps()[0] ?? appMod.initializeApp(firebaseConfig)`** so it never throws `app/duplicate-app`. **Test Flutter `onTap` (`pointerup`) user activation on a real iPhone PWA build on `dev`**.
>    - Place `firebase-messaging-sw.js` and `push_client.js` in the `no-cache, no-store, must-revalidate` rule **after** `**/*.@(js|mjs|wasm)` (`firebase.json` line 85) and **verify `Cache-Control: no-cache` with `curl -I` after deploying to `dev`**. Add `"id": "/"` and `"scope": "/"` in `web/manifest.json` (safe: matches existing `"start_url": "/"`).
> 4. **Canonical `EventKey`, 60-Day Parity Fixture & Calendar Fallbacks**:
>    - `lib/domain/push.dart` (`sourceOf` / `isReminderSourceEnabled`) maps `season-<id>` → `'lit'` and `meeting-<id>` → `'mtg'`; `tool/push_reminders.js` must match, verified by the 60-day Dart↔JS parity fixture (`test/occurrences_parity_test.dart`) explicitly covering `season→lit`, `meeting→mtg`, `day→day`, and a **Cairo DST transition night**.
>    - Define one shared **`topicKey(rawEventKey)`** helper in Dart (`lib/domain/push.dart`, called inside `reminderTopic`) and JS (`tool/push_reminders.js` / `tool/push_sender.js`), tested in the 60-day parity fixture: lowercases input, replaces any char outside `[a-z0-9-]` with `-`, validates `(lit|meeting|day|season)-`, and caps the ID suffix after `<prefix>-` at **`{1,40}`** chars. Lock `remList()` in `firestore.rules` to `^$|^web_rem_(lit|meeting|day|season)-[a-z0-9-]{1,40}(_[0-9]{8})?_(0|5|10|15|30|60|120|180|1440)_(ar|en)(,web_rem_(lit|meeting|day|season)-[a-z0-9-]{1,40}(_[0-9]{8})?_(0|5|10|15|30|60|120|180|1440)_(ar|en)){0,29}$` with `d.rem.size() <= 2600` and `d.drop.size() <= 2600`, and filter out any non-matching topic on the client before writing `push_queue` so a bad entry never poisons the whole batch.
>    - Flip `kPushDeliveryShipped = true` in `lib/domain/push.dart`. When computing web reminder topics (`computeWebTopicSync`), resolve `effectiveOcc = r.every ? null : (r.occurrence ?? isoDate(CairoTime.fromInstant(r.startsAt)))` because weekly liturgy/meeting `RemindMeButton` call sites pass `occurrence: null, recurring: true` even when the visitor selects «هذه المرة فقط» (`every: false`). Keep `lib/data/web_push_repository.dart` behind `deferred as web_push` in `AppShell` (loaded only when `localStorage['church_portal_push_web']` has an active token or `pendingSync == true`) so `main.dart.js` stays well under the +20 KB gzip budget.
>    - Update `/admin` `'lit'` reminder source label to **«القداسات والصلوات وخدمات المواسم»**. Implement pure-Dart RFC 5545 `.ics` `VALARM` (`lib/domain/calendar_ics.dart`) alongside the Google Calendar URL fallback (since `.ics` download inside standalone iOS PWA may not open Apple Calendar directly on all iOS versions and not all calendar apps honor imported `VALARM` — test on real iPhone PWA), and clamp web leads whose `fireAt < now + 40 min`.
> 5. **Live `dev` Channel Testing & `firestore.rules` Approval Gate (`deploy-dev.yml`)**:
>    - **Deploy the Cloudflare Worker manually (`npx wrangler deploy` with `PUSH_KV` + `FIREBASE_SERVICE_ACCOUNT`) FIRST and verify all 3 crons in Workers Logs BEFORE merging PR D to `dev`** (otherwise `push_queue` accumulates up to 1,000 docs/day with nothing draining it). Merging/pushing PR D to `dev` deploys `firestore.rules` + indexes to the **LIVE `asafra-church-portal` project** (`.agents/AGENTS.md` §2.3) and **strictly requires explicit owner approval beforehand**. Use `cache: 'no-store'` on `HEAD /data/today.json`, test in emulator that neither visitors nor admins can read `meta/push_rate` or `meta/contact_rate`, document the site-wide 1,000/day & 3 s spacing quota-exhaustion risk in `ADR-060`, and color-code `/admin` health rows (`null` → «لم يعمل بعد» `muted`; `lastPlanAt > 7h` → warning `goldText`; `lastDrainAt > 45m` or `lastIidError` → warning `goldText`; `capReached == true` → warning banner).
>    - Rules for `meta/push_rate`, `push_queue/{id}`, `meta/push_topics`, and `meta/push_plan` must be 100% additive (zero changes to legacy paths, scalar + 3s spacing + `count <= 1000` checks evaluated **before** `exists`/`existsAfter`/`getAfter`, and no `get(.../settings/features)` call inside `push_queue` rules).

## ١. الهدف (Goal)

Visitors on **Android Chrome / Samsung Internet / desktop browsers** and **iPhone/iPad users who installed the site
to the Home Screen (iOS/iPadOS 16.4+)** can opt in and receive the church's **remote** notifications on the web —
admin **event pushes** (scheduled, not urgent: within ~15–30 min of their time, PR C), season alerts and **their own
«ذكّرني» reminders** (per-event topics sent by the scheduled sender, PR C §16 — may be up to ~30 min late, said
plainly in the UI, §3.2) — with the same complete UX as the APK: explainer, blocked state, quiet hours, test
notification, inbox, deep links, unsubscribe-all — with **zero cost on page load**. Per the owner's channel rule
(README §3.1) the verse, Katameros and feasts are **never** sent by FCM: the web shows them on Home and in the
`/readings/<date>` screen (one `/data/readings/<date>.json` fetched on demand, ≤ ~20–25 KB: Arabic Van Dyck full
text + English references only, e.g. "Gospel: John 15:1-12" — no NKJV text; README §8 #17, decided 6 Nov 2026).

## ٢. قصص المستخدم (User stories)

- على iPhone: أضيف الموقع للشاشة الرئيسية (خطوات PR A)، أفتحه من الأيقونة، أفعّل الإشعارات وأختار الأنواع.
- على Chrome في Android أو الكمبيوتر: أفعّل من صفحة «الإشعارات» بدون تثبيت.
- أضغط الإشعار فيفتح الصفحة المحددة داخل التطبيق المثبت (أو في تبويب الموقع المفتوح).
- أرى سجل الإشعارات في الصفحة؛ «جرّب إشعارًا» يعمل فورًا؛ ساعات الهدوء تجعل الإشعار صامتًا.
- على iPhone أضغط «ذكّرني قبل ساعة» على خدمة البصخة؛ تقول لي الشاشة بوضوح إن التذكير يصل عبر الإنترنت وقد يتأخر حتى
  ٣٠ دقيقة تقريبًا، وتعرض «أضف إلى التقويم» إن أردت التنبيه في الموعد بالضبط.
- «إيقاف كل الإشعارات» يوقف كل شيء فعلًا (حتى من الخادم).

## ٣. الخصائص الفرعية (Complete sub-features)

| Sub-feature | Detail |
|---|---|
| Support detection | `'Notification' in window && 'serviceWorker' in navigator && 'PushManager' in window`; iOS: only when standalone (else → install steps from PR A, see «iOS onboarding» below); Firefox private windows / Safari < 16 → «غير مدعوم في هذا المتصفح» |
| Web types offered | `pushTypes ∩ {announcements, seasons, reminders}`. APK-only types are listed below the switches as a muted line «آية اليوم وقراءات القطمارس والأعياد: في الصفحة الرئيسية وشاشة «قراءات اليوم»، وكإشعارات محلية في تطبيق Android» (no switch) |
| Explainer → tap → permission | PR A flow; `Notification.requestPermission()` inside the click handler (iOS requires a user gesture) |
| Token | on grant: inject `/push_client.js` (once), which `import()`s `https://www.gstatic.com/firebasejs/<SDK_VERSION>/firebase-messaging.js` (same version FlutterFire loaded: `window.firebase_core.SDK_VERSION`, fallback `13.1.0` from `firebase_core_web 4.1.0`), registers `/firebase-messaging-sw.js` with scope `/firebase-cloud-messaging-push-scope`, `getToken(messaging, {vapidKey, serviceWorkerRegistration})` |
| Subscribe to topics | browsers cannot subscribe themselves → write ONE doc `push_queue/{auto}` = `{token, want:['web_announcements_ar',…], rem:'web_rem_…,web_rem_…', drop:'web_rem_…', createdAt: serverTimestamp()}` carrying the **full desired topic set** (not a diff): `want` = at most 2 fixed topics (`web_announcements_<lang>`, `web_seasons_<lang>`); `rem` = the browser's current reminder topics as one comma-joined string (≤ 30 topics, §3.2); `drop` = reminder topics this browser held before and no longer wants (cancelled / expired / language change; ≤ 30) — the sender cannot know a browser's previous reminder topics, so the client names them; the sender (PR C) groups queue docs by token, applies the **newest** doc's `want` (`createdAt`) with the supported **Firebase Admin SDK** calls `getMessaging().subscribeToTopic(tokens, topic)` / `unsubscribeFromTopic(tokens, topic)` (≤ 1,000 tokens per call, one call per topic) — subscribe to `want`, unsubscribe from the other fixed web topics and from every `drop` topic — subscribes every `rem` topic — and unsubscribes the **union of every `prevToken`** (from all fixed topics and all its `rem` topics) found in any doc of that token (a refresh followed by a preference change before the drain keeps the old-token clean-up; CodeRabbit round 2). Each call returns per-token results (`successCount`, `errors[{index, error}]`): a token's queue docs are deleted **only after all its topic changes succeeded**; transient errors (`messaging/internal-error`, `server-unavailable`, HTTP 5xx / 429) keep the docs for the next run (which again applies the newest `want`, so retries stay order-safe); permanent errors (`messaging/invalid-registration-token`, `registration-token-not-registered`, `invalid-argument`) delete the docs and count the token as gone (summary count only, never the token). Idempotent and order-safe (an ar → en → ar flip before the drain ends on ar; CodeRabbit round 1) |
| Change types / language | one queue doc with the new full `want` set (and the reminder topics re-named in the new language: new ones in `rem`, old ones in `drop`) |
| Unsubscribe all | queue `want: []`, `rem: ''`, `drop:` every held reminder topic + `deleteToken()` + clear prefs |
| Token refresh | FCM does not move topic subscriptions to a new token. Allowed refresh point (resolves "nothing on load" vs refresh — CodeRabbit): only for a device that **already enabled** notifications (local flag) and has permission `granted`, **at most once every 7 days**, after `ContentReady` + an idle slot ≥ 10 s after load — `requestIdleCallback(cb, {timeout: 5000})` where it exists, else `setTimeout(cb, 10000)` (Safari / iOS have no `requestIdleCallback`; CodeRabbit round 2): load the SDK, `getToken`; if it differs from the stored token → queue `{token: new, prevToken: old, want}` (the sender removes `prevToken` from all topics). First-time visitors and opted-out devices never load anything |
| Pending / throttled writes | the desired state is saved locally first (`pendingWant`); a rejected queue write (3 s spacing or daily cap) is retried with jitter (≤ 5 tries this visit) and again on the next visits until it succeeds; the page shows «جارٍ التفعيل…» / «تعذّر الآن، سنحاول تلقائيًا» until then (CodeRabbit) |
| Foreground delivery | every message is shown **by our own SW `push` handler, whether or not a page is open or focused** — no dependency on the FCM foreground `onMessage` handler (which would only exist after the SDK loaded, leaving a gap on normal visits, CodeRabbit round 2). The SW parses the FCM web-push payload itself (`event.data.json()` → `data`), always calls `showNotification` (iOS requires a visible notification per push) and, if a focused window exists (`clients.matchAll({type:'window', includeUncontrolled:true})`), also `postMessage({type:'received', nid})` so an open `/notifications` page refreshes its inbox. The page never loads the messaging SDK just to receive. Verified in the spike (step 1) on Chrome Android, desktop and an iPhone PWA; fallback if the payload shape differs: Firebase `onBackgroundMessage` in the SW + `onMessage` registered only on `/notifications` |
| Quiet hours | the SW reads quiet hours from IndexedDB (written by the page) and shows notifications **silently** (`silent: true`, no vibrate) inside the window — it never drops a push (iOS/Chrome penalise invisible pushes). `reminders` ring normally unless «التذكيرات تحترم ساعات الهدوء» is on (README §8 #18) |
| Guard + dedupe (SW) | same rule as Android (PR C §3), web flavour: a message whose `type` is `verse_daily`, `katameros_daily`, `feasts` or unknown is not shown as a church notification. Because iOS / Chrome penalise pushes that show nothing, the SW still shows a minimal, silent «تحديث من الكنيسة» notification with the link `/` and logs `push.dropped_local_type` — this can only happen through a sender bug, which the sender tests prevent. A repeated `nid` (seen-set of the last 100 in IndexedDB) re-uses `tag: nid` with `renotify: false`, so it replaces silently instead of stacking |
| Test notification | page → `registration.showNotification(title, {body, icon:'/icons/Icon-192.png', badge:'/icons/badge-72.png', data:{link}})` |
| Inbox | the SW appends each shown notification to IndexedDB `church_portal_push/inbox` (last 30); the page lists them with time + link; «مسح السجل» |
| Deep link | SW `notificationclick`: `link = safe(data.link)`; `clients.matchAll({type: 'window', includeUncontrolled: true})` (**required**: the SW's private scope controls no page, so without it the list is always empty — Sentry round 2), focus an existing client of the origin and `postMessage({type:'open', link})` (the app listens and calls `router.go`) or `clients.openWindow(link)`; installed PWA opens in its standalone window (manifest `scope: /`) |
| Fallback | invalid link → `/`; deleted page → app 404 «الرجوع للرئيسية» |
| Blocked state | PR A texts + detection of `permission === 'denied'` on every visit (shows the how-to) |
| iOS specifics | permission only from the Home Screen app; badge count not used; notifications show the site icon (apple-touch-icon). Full onboarding below |
| Admin test | PR C «جرّب على هذا الجهاز» uses the same SW |

### 3.1 iOS onboarding (install first, permission only when standalone)
| State (detected on `/notifications` and in the install banner) | Detection | What the user sees |
|---|---|---|
| iPhone / iPad in **Safari tab**, not installed | iOS (PR A `detectInstallOs`) and **not** standalone (`matchMedia('(display-mode: standalone)').matches == false` and `navigator.standalone !== true`) | the PR A install banner and, on `/notifications`, an **install-first card**: Share → «إضافة إلى الشاشة الرئيسية» → «إضافة» → open from the new icon; the type list is shown **read-only** (greyed preview) with «تتوفر الإشعارات بعد فتح التطبيق من الشاشة الرئيسية (iOS 16.4 أو أحدث)». **No enable button, no `Notification` / `PushManager` call at all** (in a Safari tab they are absent or unusable anyway) |
| In-app browser on iOS (Facebook, Instagram, WhatsApp) | PR A `inAppBrowser` | «افتح الموقع في Safari أولًا» + copy-link button, then the steps above |
| Installed (standalone) but **iOS < 16.4** | standalone and iOS version from the UA `OS (\d+)_(\d+)` < 16.4, or `PushManager` missing | «حدّث iOS إلى 16.4 أو أحدث لتصلك الإشعارات» (Settings → General → Software Update); app otherwise works |
| Installed (standalone), iOS ≥ 16.4, permission `default` | standalone + `'PushManager' in window` | normal explainer → «تفعيل الإشعارات» → `Notification.requestPermission()` **inside the tap handler** (user gesture) |
| Installed, `granted` / `denied` | `Notification.permission` | normal granted / blocked states (blocked how-to: Settings → Notifications → the church app) |
| Added to Home Screen from a non-Safari browser on iOS < 17 | standalone false in that browser | treated like a Safari tab: «افتح الموقع في Safari ثم أضفه» |

Rules that keep this safe: the install banner on iOS **never** requests notification permission (PR A §3.1); the
permission UI is rendered only when `isStandalone && iosVersion >= 16.4 && 'PushManager' in window`; the manifest
keeps `display: standalone` (required for iOS web push). Users who never install still get everything on the site
itself (Home verse, feasts, announcements banner) — only push needs the install.

### 3.2 «ذكّرني» على الويب و iPhone (Web reminders — per-event topics, honest delay, owner 19:31 / 19:35)
| Sub-feature | Detail |
|---|---|
| Implements | PR A's `ReminderScheduler` for the web: on save / cancel the reminder store changes locally first (`pendingRem`), then **one debounced queue write** (10 s after the last change, or on leaving the page) carries the full `rem` set + `drop` |
| Topic names | `web_rem_<eventKey>-<yyyymmdd>_<lead>_<lang>` (this time only) / `web_rem_<eventKey>_<lead>_<lang>` (every time) — PR C §16; built by PR A `reminderTopic(...)` |
| Requires | notifications enabled on this browser (granted + token). If not: the sheet offers «فعّل الإشعارات أولًا» (→ the normal flow; on iOS Safari tab → install-first card) **and** «أضف إلى التقويم» which needs nothing |
| **Delay copy (shown before saving, in the sheet and in «تذكيراتي»)** | AR: «يصل هذا التذكير عبر الإنترنت من الكنيسة، وقد يتأخر حتى ٣٠ دقيقة تقريبًا عن الموعد المختار. للتنبيه في الموعد بالضبط: «أضف إلى التقويم».» — EN: "This reminder is sent over the internet by the church and may arrive up to about 30 minutes later than the time you chose. For an alert at the exact time, use «Add to calendar»." For «في الموعد» an extra line: «قد يصل بعد بدء الخدمة بدقائق» / "may arrive a few minutes after the service starts". On an hourly cron (private repo, README §8 #15) the copy says «حتى ساعة تقريبًا» / "up to about an hour" (driven by a constant, not hard-coded twice) |
| Calendar alternative | «أضف إلى التقويم» reuses the existing `.ics` / Google Calendar link of ADR-021 with a `VALARM` at the chosen lead (`TRIGGER:-PT60M`) — exact time on iPhone even without installing the PWA, no Firestore cost |
| «تذكيراتي» on the web | same list as PR A; states add «في انتظار التفعيل» (queued write pending) and «تقريبي (عبر الإنترنت)»; expired once-reminders are moved to `drop` on the next visit (clean-up) |
| Limits | ≤ 30 reminder topics per browser (FCM allows 2,000 per instance); the reminder only arrives if the scheduled sender is running (health alert, PR C §17); a reminder for an event whose `day-` key changed shows «تغيّر الحدث — أعد ضبط التذكير» |
| Dedupe | the sender sends both the once- and every-time topic copies with one `nid` → same `tag` → one notification; with an admin push for the same event the `event:X` slot (README §3.1 rule 5) |
| Privacy | the reminder topics name the event and lead time (not the person); they sit in `push_queue` only until drained (minutes), then only Google's topic registry holds them (LAUNCH §6) |
| Client clock skew & retry | Queue batches write `push_queue` with `meta/push_rate` enforcing `request.resource.data.day == request.time.year() * 10000 + request.time.month() * 100 + request.time.day()` (integer `YYYYMMDD`, avoiding Timestamp millisecond truncation pitfalls). On rejection, `web_push_repository.dart` / `push_client.js` follows a deterministic retry sequence that separates 3 s spacing collisions, UTC midnight rollover (`count: 1`), and client clock skew via the HTTP `Date` header (§5) |

## ٤. الشاشات (Screens)

Same `/notifications` page as PR A, now fully live on the web: status card, types, «ساعات الهدوء», «جرّب
إشعارًا», «سجل الإشعارات», «إيقاف كل الإشعارات», privacy line. iPhone (not installed): install steps card at the
top instead of the enable button.

## ٥. نموذج البيانات + القواعد (Data model + rules)

New collection `push_queue/{docId}` — **create-only for visitors**, nobody reads or updates it except the sender
(Admin SDK). Batched with a global throttle like `contact_messages` + `meta/contact_rate`:

```
// Same pattern as contact_messages + meta/contact_rate (firestore.rules ~L1027), plus a DAILY CAP (Sentry review on
// the plan PR: a 2-second spacing alone would allow ~43k batches/day and exhaust Spark's 20k writes/day).
match /meta/push_rate {
  allow read, delete: if false;
  // cheap field checks FIRST: `&&` short-circuits, so a malformed request is rejected before any exists() read
  allow create, update: if request.resource.data.keys().hasOnly(['lastAt', 'lastId', 'day', 'count'])
    && request.resource.data.lastAt == request.time
    && request.resource.data.lastId is string && request.resource.data.lastId.matches('^[A-Za-z0-9]{10,64}$')
    // spacing: one queue write per 3 s overall
    && (resource == null || request.time > resource.data.lastAt + duration.value(3, 's'))
    // daily cap: `day` = UTC date integer YYYYMMDD (e.g. 20270430) — avoids Timestamp type/millisecond pitfalls;
    // count restarts at 1 each day; at most 1,000 per day. Final syntax confirmed by the emulator tests.
    && request.resource.data.day is int
    && request.resource.data.day == request.time.year() * 10000 + request.time.month() * 100 + request.time.day()
    && request.resource.data.count is int && request.resource.data.count >= 1 && request.resource.data.count <= 1000
    && (resource == null || resource.data.day != request.resource.data.day
          ? request.resource.data.count == 1
          : request.resource.data.count == resource.data.count + 1)
    // document reads last (billed even when the request is rejected)
    && !exists(/databases/$(database)/documents/push_queue/$(request.resource.data.lastId))
    && existsAfter(/databases/$(database)/documents/push_queue/$(request.resource.data.lastId));
}
match /push_queue/{id} {
  allow read, update, delete: if false;          // only the sender (Admin SDK) reads / deletes
  allow create: if validPushQueue(request.resource.data)
    && getAfter(/databases/$(database)/documents/meta/push_rate).data.lastAt == request.time
    && getAfter(/databases/$(database)/documents/meta/push_rate).data.get('lastId', '') == id;
}
function validPushQueue(d) {
  return d.keys().hasOnly(['token', 'prevToken', 'want', 'rem', 'drop', 'createdAt'])
    && d.token is string && d.token.matches('^[A-Za-z0-9:_-]{100,400}$')
    && (!('prevToken' in d) || (d.prevToken is string && d.prevToken.matches('^[A-Za-z0-9:_-]{100,400}$')))
    && d.want is list && d.want.size() <= 2
    && d.want.hasOnly(webTopics())                 // the 4 fixed web topics: web_(announcements|seasons)_(ar|en)
    // reminder topics: rules cannot loop over a list, so they travel as ONE comma-joined string checked by one regex
    && (!('rem' in d) || (d.rem is string && d.rem.size() <= 2600 && d.rem.matches(remList())))
    && (!('drop' in d) || (d.drop is string && d.drop.size() <= 2600 && d.drop.matches(remList())))
    && d.createdAt == request.time;
}
function remList() {   // '' or 1–30 topics web_rem_<key>_<lead>_<lang>
  return '^$|^web_rem_(lit|meeting|day|season)-[a-z0-9-]{1,40}(_[0-9]{8})?_(0|5|10|15|30|60|120|180|1440)_(ar|en)(,web_rem_(lit|meeting|day|season)-[a-z0-9-]{1,40}(_[0-9]{8})?_(0|5|10|15|30|60|120|180|1440)_(ar|en)){0,29}$';
}
```
**How the client satisfies the counter without reading it** (Sentry round 2: the doc is unreadable): the batch
writes `meta/push_rate` with `set({lastAt: serverTimestamp(), lastId, day: <UTC YYYYMMDD int>, count:
FieldValue.increment(1)}, {merge: true})` — the rules see the post-increment value, so on the same UTC day `count ==
old + 1` holds without the client knowing `old`; on a missing doc the increment yields 1. `allow read` stays false:
no counter or `lastId` is ever exposed.

**Deterministic retry protocol (disambiguating 3 s spacing, UTC day rollover, and client clock skew):**
Because all rule rejections return `permission-denied`, the client must not blindly confuse a 3 s spacing collision
with a new-UTC-day rollover (`resource.data.day != request.resource.data.day`, where `FieldValue.increment(1)` yields
`old + 1 != 1`) or an inaccurate device clock (`day != server YYYYMMDD`). `web_push_repository.dart` / `push_client.js`
executes this exact sequence:
1. **Attempt 1 (normal path):** write with local UTC `day` (`YYYYMMDD`) and `count: FieldValue.increment(1)`.
2. **Sync server date on first rejection:** if Attempt 1 fails with `permission-denied`, fetch `HEAD /data/today.json`
   (same-origin, lightweight) and read its HTTP `Date` response header to obtain the authoritative UTC `serverDay`
   (`YYYYMMDD`, falling back to local UTC date if the header is absent).
3. **Attempt 2 (new-UTC-day rollover):** tried **once** with `day: serverDay` and literal `count: 1` (if today's first
   write has not happened yet, this resets the counter to `1` for `serverDay` and succeeds; if `meta/push_rate.day` is
   already `serverDay`, the rule requires `old + 1` so `count: 1` is harmlessly rejected). Additionally, `push_sender.js`
   (running every 15 min via Admin SDK) pre-rolls `meta/push_rate` to `{day: todayUtcInt, count: 0}` on its first run
   after `00:00 UTC` whenever `day < todayUtcInt`, so visitors after `00:07 UTC` rarely even need Attempt 2.
4. **Attempts 3–5 (3 s spacing backoff):** wait `3.2 s + random(0..1.5 s)` jitter and retry with `day: serverDay` and
   `count: FieldValue.increment(1)`.

**Rejected requests still cost rule reads** (CodeRabbit round 1 follow-up; Firebase: reads made by `get()` /
`exists()` / `getAfter()` are charged even when the request is denied —
https://firebase.google.com/docs/firestore/security/rules-conditions#access_calls_and_pricing). Bounds: the field
checks run first, so a **malformed** request costs **0** reads; a well-formed but rejected batch (spacing / cap)
costs at most ~3 reads (`exists`, `existsAfter`, `getAfter`). The rules cannot bound a flood of well-formed
rejected requests: ~17k of them in a day would consume Spark's 50k reads, after which visitors fall back to the
bundled seed / cached data until the quota resets (the site keeps working, with stale data). This is the **same
exposure the live `contact_messages` + `meta/contact_rate` form already has**. Controls before exposing the queue:
the queue is reachable only after the owner turns `push` on with a VAPID key (LAUNCH §13); Firestore usage is
watched daily in the first weeks (LAUNCH §11); the kill switch is a rules change `allow create: if false` on
`push_queue` (LAUNCH §10, minutes to deploy); the hardening path, if abuse is ever seen, is App Check enforcement on
Firestore for the web (rejected for now by ADR-037 for PageSpeed). The emulator tests assert that malformed requests
evaluate no document read.

Tests: a valid `want` doc (incl. the initial subscription and `want: []`) passes in a batch with the throttle; alone → denied; second within 3 s → denied; count 1,001 →
denied; `count: increment(1)` accepted on the same day without a prior read; new UTC day (`YYYYMMDD` integer): increment denied, literal
`count: 1` accepted (count 2 on a new day → denied); `day` not today's integer → denied; client retry sequence test (spacing rejection vs new-day rollover vs skewed client clock corrected via HTTP `Date`); malformed request → no document
read evaluated; bad token,
unknown topic, **a local-owned topic such as `web_verse_daily_ar` / `web_katameros_daily_ar` → denied**, 3 fixed
topics, `rem` with 31 topics / an upper-case key / lead 7 / `app_rem_…` → denied, 30 valid reminder topics →
allowed, read/update/delete → denied.

**Fallback if Admin-SDK topic management stops working for web tokens** (verify in step 1): collection
`push_subscribers/{sha256(token)}` `{token, topics, updatedAt}` — create / update by the client with the same
validation and throttle, delete on unsubscribe, **never readable by visitors**, read only by the sender; the
sender sends to each token with `message.token`. Storage contract: one doc per opted-in browser, kept **while the
user stays subscribed** (unlike the queue, which is deleted after minutes); invalid tokens deleted on the first
permanent send error. Cost contract: every announcement / season alert reads all N docs (≈ N reads per send; e.g.
1,000 subscribers × ~3 sends/day = 3k reads/day) and one `send` per token (FCM free). Privacy: LAUNCH §6 must then
say that the token, chosen types and language are **stored in Firestore while subscribed** (not "deleted after a
few minutes") — the alternative text is in LAUNCH §6. ADR-060 records which path was used.

## ٦. التكلفة (Cost)

Page load: **0** (no SW registration, no SDK, no Firestore) until the user taps «تفعيل». Per opt-in / change batch
(type change, language change, or any number of «ذكّرني» changes within the 10 s debounce): 2 writes (queue +
throttle) + ~3 rule reads, hard-capped at 1,000 queue writes per day by the rules; sender: 1 read + 1 delete per
queued doc + Admin-SDK topic calls (free); reminder sends cost no Firestore per user (PR C §16). FCM free.
**Holy Week peak:** if many visitors set reminders on the same day the daily cap can be reached; their changes stay
pending locally and are retried (next visit / next day) — the UI says «تعذّر الحفظ الآن، سنحاول تلقائيًا» and
offers «أضف إلى التقويم» meanwhile. The cap can be raised to 2,000 (≈ 4k writes / 6k rule reads per day, still
< 30 % of Spark) if the first season shows it is needed.

## ٧. الملفات (Files)

Create / complete:
- `web/push_client.js` — `window.churchPush = { enable({vapidKey, firebaseConfig}), getToken(), deleteToken(), test(n), inbox(), clearInbox(), setQuiet(q) }`; ES module dynamic imports from gstatic; no globals besides `churchPush`.
- `web/firebase-messaging-sw.js` — **plain** service worker (no Firebase import needed to receive: `getToken` in the page subscribes this registration's `PushManager`); its own `self.addEventListener('push', …)` → parse `event.data.json().data` → guard + `nid` dedupe → read quiet hours (IndexedDB) → `self.registration.showNotification(title, {body, icon, badge, dir: lang==='ar'?'rtl':'ltr', lang, tag: key, silent, data:{link}})` → inbox append; `notificationclick` deep link; **no `fetch` handler** (no effect on page loads; Flutter's own SW is a self-unregistering cleanup worker at scope `/` — different scope, verify it does not unregister ours).
- `web/icons/badge-72.png` (monochrome seal for Android Chrome's status bar; generated by `tool/gen_branding.sh`).
- `lib/core/push_env_web.dart` (complete) — JS interop to `churchPush`; message listener for `{type:'open'}` → router.
- `lib/data/web_push_repository.dart` — writes the queue + throttle batch.
- `test/web_push_test.dart` (fake env), rules tests.
- `documentation/features/notifications.md` (web + iPhone sections), ADR-060.

Modify:
- `lib/ui/pages/notifications_page.dart` (web sections), `lib/ui/widgets/app_shell.dart` (listen to SW messages),
  `firestore.rules`, `tool/rules_test/rules.test.mjs`, `tool/push_sender.js` (drain queue: batchAdd/batchRemove
  grouped by topic via `subscribeToTopic` / `unsubscribeFromTopic`, max 1,000 tokens per call; per-token results;
  delete a token's docs only after success; transient → keep; permanent → delete; errors logged without the
  token), `web/manifest.json` (`"id": "/"`, `"scope": "/"`; keep `display: standalone` — required for iOS push),
  `firebase.json` (headers for `/firebase-messaging-sw.js`: `Cache-Control: no-cache`, `Service-Worker-Allowed` not
  needed for a narrower scope).
- Privacy texts (`lib/core/l10n.dart` `pushPrivacy`), `documentation/features/pwa-and-caching.md`.

## ٨. الحزم (Packages)

No Dart package (uses PR C's `firebase_messaging` only on Android; on web its SDK is ignored at load and our own
`push_client.js` imports the gstatic modules lazily). JS: Firebase JS SDK from gstatic, same version as FlutterFire.

## ٩. خطوات التنفيذ (Step-by-step)

1. **Spike (½ day)**: with a test VAPID key on the PR preview channel, get a token on Android Chrome and an
   installed iPhone PWA; call Admin SDK `subscribeToTopic` for that web token from a local script with the
   `push-sender` key; send to the topic; check the plain SW receives it with the page open, in the background and
   closed. Record results (topic subscription OK for web tokens? iOS OK? payload shape?) in ADR-060 and pick the
   queue or the fallback.
2. Rules + emulator tests for `push_queue` + throttle.
3. `push_client.js` + SW (complete) + Dart interop; enable / disable / token refresh; queue writes.
4. Sender: drain queue — newest doc per token wins, add `want` / remove the rest / remove `prevToken`; drained even
   while `push` is off (+ tests with a fake messaging client, including out-of-order docs, refresh-then-change with
   `prevToken` only in the older doc, partial per-token failures, transient vs permanent errors).
5. Page: quiet hours, test, inbox, iOS states; deep-link messages.
5b. Web «ذكّرني» (§3.2): `ReminderScheduler` web implementation, debounced `rem` / `drop` queue writes, delay copy,
    calendar `VALARM`, expired clean-up; sender drains `rem` / `drop` (subscribe / unsubscribe per topic).
6. PageSpeed check: Lighthouse mobile on the preview (no new requests on load; score ≥ previous − 2).
7. Docs + ADR-060.

## ١٠. الاختبارات (Tests)

- Dart (fake env): token-refresh scheduling uses `requestIdleCallback` when present and `setTimeout(10 s)` when absent;
  states (unsupported, ios not installed, ios standalone < 16.4, in-app browser, default, granted,
  denied); on iOS not standalone **zero** calls to `requestPermission` / `PushManager` whatever the user taps;
  only `announcements` / `seasons` / `reminders` offered on the web; reminder save → one debounced queue doc with the
  full `rem` and the right `drop`; cancel → topic in `drop`; expired once-reminder → `drop` on next visit; delay copy
  shown before saving (ar / en, hourly variant); 31st reminder refused; enable writes exactly one
  queue doc with the full `want` set for ar/en; changing types writes the new full set; unsubscribe-all → `want: []`
  + deleteToken; token change → prevToken flow only for enabled devices, once per 7 days, after idle; first-time
  visitors: no env calls on load; throttled write → pending state + retry.
- JS (node:test with a fake `self`): SW quiet-hours silent flag, inbox cap 30, `safe(link)`, click calls
  `matchAll` with `includeUncontrolled: true` and focuses an existing window (else opens one), local-owned `type` → minimal silent notice + breadcrumb (no church text), repeated `nid` → same `tag`, not
  stacked.
- Rules emulator (§5). Sender queue tests (grouping, deletion, error handling).

## ١١. اختبار يدوي (Manual QA)

| Device | Steps | Expected |
|---|---|---|
| iPhone iOS 17/18 Safari, not installed | open `/notifications`; tap around | install-first card + read-only type preview, no enable button, **no permission prompt ever** |
| iPhone, install banner | tap «طريقة الإضافة» | steps sheet only (Share → Add to Home Screen); no permission prompt |
| iPhone installed PWA | enable → allow | test notification shows; one-off from admin arrives (≤ 30 min); tap opens the page inside the PWA |
| iPhone: Settings → Notifications → app → off | reopen page | blocked state with how-to |
| Android Chrome (not installed) | enable, choose season alerts | season alert arrives on a season start day; no daily verse push (local-only type, not offered on the web) |
| iPhone installed PWA | «ذكّرني قبل ١٥ دقيقة» on a service 40 min ahead (test project, dry run off) | delay copy shown before saving; reminder arrives between −5 and +30 min of the chosen time; tap opens the service |
| Any browser | «أضف إلى التقويم» with «قبل ساعة» | calendar event with a 60-min alert |
| Any browser | cancel a reminder | next queue doc has it in `drop`; nothing arrives |
| Android Chrome installed PWA | tap notification | opens in the PWA window |
| Desktop Chrome / Edge / Firefox / Safari macOS | enable, test, announcement | works; Firefox shows its own permission UI |
| Quiet hours | set now inside | silent notification, listed in inbox |
| Unsubscribe all | then admin sends | nothing arrives |
| Arabic / English | switch language | topics switch (new `want` = the `_en` topics; the sender removes the `_ar` ones) |
| PageSpeed | Lighthouse mobile | no new network request on load |

## ١٢. CI

`ci.yml`: add `node --test web/*.test.mjs tool/*.test.mjs`. No new workflow (the sender from PR C drains the queue).

## ١٣. التوثيق (Docs / ADR)

ADR-060: lazy messaging SDK, plain SW at a private scope showing every push itself (no foreground gap), VAPID public
key in `settings/features`, queue + Admin-SDK topic management with per-token results (or the token-list
fallback), web «ذكّرني» as per-event topics (`rem` / `drop` strings, debounced, honest ~30-min delay copy, calendar
alternative), silent-not-dropped quiet hours, iOS installed-only with the install-first onboarding (no permission
request before standalone), web offers announcements, seasons and reminders, SW guard + `nid` dedupe. Arabic manual + `operations.md`
(VAPID rotation, what to tell iPhone users).

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| Topic management for web tokens fails or is retired | spike first; token-list fallback ready (storage, cost and privacy contracts in §5) |
| Sustained abuse fills the 1,000/day cap on successive days (legitimate opt-ins blocked) | detection: the sender summary records daily queue count and «cap reached»; two consecutive capped days → owner response in LAUNCH §10: (1) temporarily clear «مفتاح Web Push (VAPID)» in `/admin` — with no key the enable button is disabled (PR A) — so no new queue writes are attempted (existing subscriptions keep working; the key is pasted back afterwards, unchanged, so no one must re-enable), (2) enable App Check enforcement on Firestore for the web (accepting the PageSpeed cost, ADR-037) or tighten the rules, then (3) turn opt-in back on. **Recovery of legitimate opt-ins:** their desired state is kept locally (`pendingWant`) and re-sent automatically on the next visit once writes succeed — nothing for the user to redo; topic limit (≤ 2), 3 s spacing and the cap stay unchanged |
| iOS web push limits (installed only, 16.4+, can be revoked silently if many pushes are not shown) | always show a notification; clear UI guidance |
| Spam writes to `push_queue` (CodeRabbit: "per-client limits"; rejected requests still cost rule reads — §5) | strict validation, 3 s global spacing **and a 1,000-per-day cap** (worst case 2,000 writes + ~3,000 rule reads + 1,000 sender reads + 1,000 deletes per day — about 10–15 % of each Spark quota, so contact messages and admin saves keep working), create-only, sender deletes. True per-client limits need an identity: **App Check enforcement on Firestore** would make every visitor load reCAPTCHA on every page (rejected by ADR-037 for PageSpeed) and anonymous Auth gives no real per-person limit; both stay listed as later hardening if abuse is ever seen (sender summary shows daily queue counts). An attacker can at worst fill the day's cap — legitimate opt-ins then wait until the next day (pending state retries automatically); client retries with jitter (≤ 5 tries) and shows «الخدمة مشغولة، حاول بعد قليل» / «حاول غدًا» when the cap is reached; later hardening: enforce App Check on Firestore for web |
| SW conflicts with Flutter's cleanup SW | separate scope; test on real devices; fallback: register at `/push/` scope with the SW file under `/push/` |
| VAPID key rotated → old tokens invalid | runbook: rotating means everyone must re-enable — avoid |
| Same person opted in on the Android APK **and** in Chrome on the same phone → two copies of an announcement | different devices / installs cannot share a dedupe set; the web `/notifications` page on Android shows «لديك تطبيق Android؟ فعّل الإشعارات من التطبيق بدلًا من المتصفح» and the APK's page reminds the user to turn off browser notifications |
| PageSpeed | nothing on load; Lighthouse check in QA |

## ١٥. ما يفعله المالك (Owner steps — click by click)

1. https://console.firebase.google.com/project/asafra-church-portal/settings/cloudmessaging → section **Web
   configuration** → **Web Push certificates** → **Generate key pair**.
2. Copy the long **Key pair** value (public key, ~88 characters, starts with `B`). Never share the private key
   (Firebase keeps it).
3. `/admin` → «التطبيق والإشعارات» → «مفتاح Web Push (VAPID)» → paste → **حفظ**.
4. Check the Cloud Messaging tab shows **Firebase Cloud Messaging API (V1): Enabled** (PR C step 1).
5. Test on your own phone (installed PWA on iPhone, Chrome on Android) before switching `push` on for everyone.
