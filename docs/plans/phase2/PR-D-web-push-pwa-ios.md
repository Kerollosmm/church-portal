# PR D — إشعارات الويب + التطبيق المثبت على iPhone (Web push, PWA, iPhone)

| | |
|---|---|
| Branch → base | `feat/p2d-web-push` → `feat/p2c-notification-manager` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-060** |
| Depends on | PR A (prefs page, `pushVapidKey`, SW scaffold), PR C (sender, topics, deep links) |
| Owner console work | generate the **VAPID** key pair and paste the public key in `/admin` (§15) |
| Live effect after merge | nothing until `push` is on **and** `pushVapidKey` is set |

## ١. الهدف (Goal)

Visitors on **Android Chrome / Samsung Internet / desktop browsers** and **iPhone/iPad users who installed the site
to the Home Screen (iOS/iPadOS 16.4+)** can opt in per type and receive the church's notifications (daily types
from the sender + admin announcements), with the same complete UX as the APK: explainer, blocked state, quiet
hours, test notification, inbox, deep links, unsubscribe-all — with **zero cost on page load**.

## ٢. قصص المستخدم (User stories)

- على iPhone: أضيف الموقع للشاشة الرئيسية (خطوات PR A)، أفتحه من الأيقونة، أفعّل الإشعارات وأختار الأنواع.
- على Chrome في Android أو الكمبيوتر: أفعّل من صفحة «الإشعارات» بدون تثبيت.
- أضغط الإشعار فيفتح الصفحة المحددة داخل التطبيق المثبت (أو في تبويب الموقع المفتوح).
- أرى سجل الإشعارات في الصفحة؛ «جرّب إشعارًا» يعمل فورًا؛ ساعات الهدوء تجعل الإشعار صامتًا.
- «إيقاف كل الإشعارات» يوقف كل شيء فعلًا (حتى من الخادم).

## ٣. الخصائص الفرعية (Complete sub-features)

| Sub-feature | Detail |
|---|---|
| Support detection | `'Notification' in window && 'serviceWorker' in navigator && 'PushManager' in window`; iOS: only when standalone (else → install steps from PR A); Firefox private windows / Safari < 16 → «غير مدعوم في هذا المتصفح» |
| Explainer → tap → permission | PR A flow; `Notification.requestPermission()` inside the click handler (iOS requires a user gesture) |
| Token | on grant: inject `/push_client.js` (once), which `import()`s `https://www.gstatic.com/firebasejs/<SDK_VERSION>/firebase-messaging.js` (same version FlutterFire loaded: `window.firebase_core.SDK_VERSION`, fallback `13.1.0` from `firebase_core_web 4.1.0`), registers `/firebase-messaging-sw.js` with scope `/firebase-cloud-messaging-push-scope`, `getToken(messaging, {vapidKey, serviceWorkerRegistration})` |
| Subscribe to topics | browsers cannot subscribe themselves → write ONE doc `push_queue/{auto}` = `{op:'sub', token, topics:['web_announcements_ar',…], createdAt: serverTimestamp()}`; the sender (PR C) drains it with the **Instance ID API** `https://iid.googleapis.com/iid/v1:batchAdd` / `:batchRemove` (OAuth token of `push-sender`, header `access_token_auth: true`) and deletes the doc |
| Change types / language | diff → one queue doc with `sub` + `unsub` lists |
| Unsubscribe all | queue `unsub` all web topics + `deleteToken()` + clear prefs |
| Token refresh | on each visit with permission granted the client calls `getToken` (cheap, cached); if it differs from the stored one → queue `sub` with the new token and `unsub` with `prevToken` |
| Quiet hours | the SW reads quiet hours from IndexedDB (written by the page) and shows notifications **silently** (`silent: true`, no vibrate) inside the window — it never drops a push (iOS/Chrome penalise invisible pushes) |
| Test notification | page → `registration.showNotification(title, {body, icon:'/icons/Icon-192.png', badge:'/icons/badge-72.png', data:{link}})` |
| Inbox | the SW appends each shown notification to IndexedDB `church_portal_push/inbox` (last 30); the page lists them with time + link; «مسح السجل» |
| Deep link | SW `notificationclick`: `link = safe(data.link)`; focus an existing client of the origin and `postMessage({type:'open', link})` (the app listens and calls `router.go`) or `clients.openWindow(link)`; installed PWA opens in its standalone window (manifest `scope: /`) |
| Fallback | invalid link → `/`; deleted page → app 404 «الرجوع للرئيسية» |
| Blocked state | PR A texts + detection of `permission === 'denied'` on every visit (shows the how-to) |
| iOS specifics | permission only from the Home Screen app; shows «يجب فتح التطبيق من الشاشة الرئيسية»; badge count not used; notifications show the site icon (apple-touch-icon) |
| Admin test | PR C «جرّب على هذا الجهاز» uses the same SW |

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
  allow create, update: if request.resource.data.keys().hasOnly(['lastAt', 'lastId', 'day', 'count'])
    && request.resource.data.lastAt == request.time
    && request.resource.data.lastId is string && request.resource.data.lastId.matches('^[A-Za-z0-9]{10,64}$')
    && !exists(/databases/$(database)/documents/push_queue/$(request.resource.data.lastId))
    && existsAfter(/databases/$(database)/documents/push_queue/$(request.resource.data.lastId))
    // spacing: one queue write per 3 s overall
    && (resource == null || request.time > resource.data.lastAt + duration.value(3, 's'))
    // daily cap: `day` = the UTC date of request.time (the client writes today's UTC midnight as a Timestamp);
    // count restarts at 1 each day; at most 1,000 per day. Final syntax confirmed by the emulator tests.
    && request.resource.data.day == request.time.date()
    && request.resource.data.count is int && request.resource.data.count <= 1000
    && (resource == null || resource.data.day != request.resource.data.day
          ? request.resource.data.count == 1
          : request.resource.data.count == resource.data.count + 1);
}
match /push_queue/{id} {
  allow read, update, delete: if false;          // only the sender (Admin SDK) reads / deletes
  allow create: if validPushQueue(request.resource.data)
    && getAfter(/databases/$(database)/documents/meta/push_rate).data.lastAt == request.time
    && getAfter(/databases/$(database)/documents/meta/push_rate).data.get('lastId', '') == id;
}
function validPushQueue(d) {
  return d.keys().hasOnly(['op', 'token', 'prevToken', 'sub', 'unsub', 'createdAt'])
    && d.op in ['sub', 'unsub', 'change']
    && d.token is string && d.token.matches('^[A-Za-z0-9:_-]{100,400}$')
    && (!('prevToken' in d) || (d.prevToken is string && d.prevToken.matches('^[A-Za-z0-9:_-]{100,400}$')))
    && d.get('sub', []) is list && d.get('sub', []).size() <= 10
    && d.get('unsub', []) is list && d.get('unsub', []).size() <= 10
    && d.get('sub', []).concat(d.get('unsub', [])).hasOnly(webTopics())   // the 10 web_<type>_<ar|en> names
    && d.createdAt == request.time;
}
```
Tests: valid sub passes in a batch with the throttle; alone → denied; second within 3 s → denied; count 1,001 →
denied; new UTC day resets the count to 1 (count 2 on a new day → denied); `day` not today → denied; bad token,
unknown topic, 11 topics, read/update/delete → denied.

**Fallback if the IID API stops working** (it is old; verify in step 1): collection `push_subscribers/{sha256(token)}`
`{token, topics, updatedAt}` written by the client (same validation), and the sender sends to each token with
`message.token` (reads N docs per daily run — fine below ~1,000 subscribers: 1,000 reads × ~5 sends/day = 5k
reads). ADR-060 records which path was used.

## ٦. التكلفة (Cost)

Page load: **0** (no SW registration, no SDK, no Firestore) until the user taps «تفعيل». Per opt-in / change: 2
writes (queue + throttle), hard-capped at 1,000 queue writes per day by the rules; sender: 1 read + 1 delete per queued doc + IID call (free). FCM free.

## ٧. الملفات (Files)

Create / complete:
- `web/push_client.js` — `window.churchPush = { enable({vapidKey, firebaseConfig}), getToken(), deleteToken(), test(n), inbox(), clearInbox(), setQuiet(q) }`; ES module dynamic imports from gstatic; no globals besides `churchPush`.
- `web/firebase-messaging-sw.js` — `importScripts('https://www.gstatic.com/firebasejs/<v>/firebase-app-compat.js', '…/firebase-messaging-compat.js')`; config from the registration URL query (`?apiKey=…&projectId=…&messagingSenderId=…&appId=…`, no duplicated config); `messaging.onBackgroundMessage` → read quiet hours (IndexedDB) → `self.registration.showNotification(title, {body, icon, badge, dir: lang==='ar'?'rtl':'ltr', lang, tag: key, silent, data:{link}})` → inbox append; `notificationclick` deep link; **no `fetch` handler** (no effect on page loads; Flutter's own SW is a self-unregistering cleanup worker at scope `/` — different scope, verify it does not unregister ours).
- `web/icons/badge-72.png` (monochrome seal for Android Chrome's status bar; generated by `tool/gen_branding.sh`).
- `lib/core/push_env_web.dart` (complete) — JS interop to `churchPush`; message listener for `{type:'open'}` → router.
- `lib/data/web_push_repository.dart` — writes the queue + throttle batch.
- `test/web_push_test.dart` (fake env), rules tests.
- `documentation/features/notifications.md` (web + iPhone sections), ADR-060.

Modify:
- `lib/ui/pages/notifications_page.dart` (web sections), `lib/ui/widgets/app_shell.dart` (listen to SW messages),
  `firestore.rules`, `tool/rules_test/rules.test.mjs`, `tool/push_sender.js` (drain queue: batchAdd/batchRemove
  grouped by topic, max 1,000 tokens per call; delete processed docs; IID errors per token logged without the
  token), `web/manifest.json` (`"id": "/"`, `"scope": "/"`; keep `display: standalone` — required for iOS push),
  `firebase.json` (headers for `/firebase-messaging-sw.js`: `Cache-Control: no-cache`, `Service-Worker-Allowed` not
  needed for a narrower scope).
- Privacy texts (`lib/core/l10n.dart` `pushPrivacy`), `documentation/features/pwa-and-caching.md`.

## ٨. الحزم (Packages)

No Dart package (uses PR C's `firebase_messaging` only on Android; on web its SDK is ignored at load and our own
`push_client.js` imports the gstatic modules lazily). JS: Firebase JS SDK from gstatic, same version as FlutterFire.

## ٩. خطوات التنفيذ (Step-by-step)

1. **Spike (½ day)**: with a test VAPID key on the PR preview channel, get a token on Android Chrome and an
   installed iPhone PWA; call IID `batchAdd` with the `push-sender` token from a local script; send to the topic.
   Record results (IID OK? iOS OK?) in ADR-060 and pick the queue or the fallback.
2. Rules + emulator tests for `push_queue` + throttle.
3. `push_client.js` + SW (complete) + Dart interop; enable / disable / token refresh; queue writes.
4. Sender: drain queue (+ tests with a fake IID).
5. Page: quiet hours, test, inbox, iOS states; deep-link messages.
6. PageSpeed check: Lighthouse mobile on the preview (no new requests on load; score ≥ previous − 2).
7. Docs + ADR-060.

## ١٠. الاختبارات (Tests)

- Dart (fake env): states (unsupported, ios not installed, default, granted, denied); enable writes exactly one
  queue doc with the right topics for ar/en; changing types writes sub+unsub diff; unsubscribe-all → unsub all +
  deleteToken; token change → prevToken flow; nothing happens on page load (no env calls before tap).
- JS (node:test with a fake `self`): SW quiet-hours silent flag, inbox cap 30, `safe(link)`, click focuses or
  opens.
- Rules emulator (§5). Sender queue tests (grouping, deletion, error handling).

## ١١. اختبار يدوي (Manual QA)

| Device | Steps | Expected |
|---|---|---|
| iPhone iOS 17/18 Safari, not installed | open `/notifications` | install steps, no enable button |
| iPhone installed PWA | enable → allow | test notification shows; one-off from admin arrives (≤ 30 min); tap opens the page inside the PWA |
| iPhone: Settings → Notifications → app → off | reopen page | blocked state with how-to |
| Android Chrome (not installed) | enable, choose verse | daily verse arrives after the admin time |
| Android Chrome installed PWA | tap notification | opens in the PWA window |
| Desktop Chrome / Edge / Firefox / Safari macOS | enable, test, announcement | works; Firefox shows its own permission UI |
| Quiet hours | set now inside | silent notification, listed in inbox |
| Unsubscribe all | then admin sends | nothing arrives |
| Arabic / English | switch language | topics switch (unsub _ar, sub _en) |
| PageSpeed | Lighthouse mobile | no new network request on load |

## ١٢. CI

`ci.yml`: add `node --test web/*.test.mjs tool/*.test.mjs`. No new workflow (the sender from PR C drains the queue).

## ١٣. التوثيق (Docs / ADR)

ADR-060: lazy messaging SDK, SW at a private scope, VAPID public key in `settings/features`, queue + IID (or the
token-list fallback), silent-not-dropped quiet hours, iOS installed-only. Arabic manual + `operations.md`
(VAPID rotation, what to tell iPhone users).

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| IID API deprecated / blocked | spike first; token-list fallback ready |
| iOS web push limits (installed only, 16.4+, can be revoked silently if many pushes are not shown) | always show a notification; clear UI guidance |
| Spam writes to `push_queue` | strict validation, 3 s global spacing **and a 1,000-per-day cap** (worst case 2,000 writes + 1,000 deletes/day, well inside Spark's 20k), create-only, sender deletes; client retries with jitter (≤ 5 tries) and shows «الخدمة مشغولة، حاول بعد قليل» / «حاول غدًا» when the cap is reached; later hardening: enforce App Check on Firestore for web |
| SW conflicts with Flutter's cleanup SW | separate scope; test on real devices; fallback: register at `/push/` scope with the SW file under `/push/` |
| VAPID key rotated → old tokens invalid | runbook: rotating means everyone must re-enable — avoid |
| PageSpeed | nothing on load; Lighthouse check in QA |

## ١٥. ما يفعله المالك (Owner steps — click by click)

1. https://console.firebase.google.com/project/asafra-church-portal/settings/cloudmessaging → section **Web
   configuration** → **Web Push certificates** → **Generate key pair**.
2. Copy the long **Key pair** value (public key, ~88 characters, starts with `B`). Never share the private key
   (Firebase keeps it).
3. `/admin` → «التطبيق والإشعارات» → «مفتاح Web Push (VAPID)» → paste → **حفظ**.
4. Check the Cloud Messaging tab shows **Firebase Cloud Messaging API (V1): Enabled** (PR C step 1).
5. Test on your own phone (installed PWA on iPhone, Chrome on Android) before switching `push` on for everyone.
