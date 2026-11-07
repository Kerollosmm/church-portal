# الإطلاق والتشغيل (Launch & operations — everything outside the code)

Everything needed to make Phase 2 real, after (or alongside) PRs A–E: consoles, keys, signing, hosting, user
guidance, privacy, real-device tests, release, rollback, monitoring, the admin runbook and the launch-day checklist.

## ١. ملخص الإعدادات خارج الكود (One-time setup summary)

| # | Where | What | PR | Who |
|---|---|---|---|---|
| 1 | Your computer | create the APK signing keystore + 2 backups | B | owner |
| 2 | GitHub → Settings → Secrets → Actions | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | B | owner |
| 2b | GitHub → new public repo + Secrets / Variables | APK host (README §8 #6, **decided 6 Nov 2026**): create `Kerollosmm/church-portal-apk` (owner, or the agent with the owner's approval at PR B time), fine-grained token for that repo only (Contents: Read and write) → secret `RELEASES_REPO_TOKEN`; variables `APK_HOST=releases-repo`, `APK_BASE_URL`; retention = newest 5 releases (automatic) | B | owner |
| 3 | GitHub → Releases | first tag `apk-v1.1.0` → APKs + `version.json` attached and published (after the chain is merged) | B | owner |
| 4 | `/admin` → «التطبيق والإشعارات» | APK URLs, version, build, size | B | admin |
| 5 | Google Cloud → APIs | enable **Firebase Cloud Messaging API** | C | owner |
| 6 | Google Cloud → IAM → Service accounts | `push-sender` with **Firebase Cloud Messaging API Admin** + **Cloud Datastore User**, JSON key | C | owner |
| 7 | GitHub → Secrets / Variables | secret `FIREBASE_SA_PUSH`, variable `PUSH_DRY_RUN=true` | C | owner |
| 7b | Sentry → Crons (+ GitHub secret) | cron monitor `push-sender` + secret `SENTRY_CRONS_URL` (optional, recommended; §14) | C | owner |
| 7c | GitHub → Actions | `keepalive.yml` present and its first manual run green (§14) | C | owner |
| 7d | GitHub → Settings → Environments → `production` | Required reviewers (recommended hygiene, not required — README §8 #19) | — | owner |
| 8 | Firebase console → Cloud Messaging → Web Push certificates | **Generate key pair**, paste the public key in `/admin` | D | owner (or Hark's browser session) |
| 9 | `/admin` → «الإشعارات» | types offered, texts, times; `push` on (launch day) | C/D | admin |
| 10 | GitHub → Variables | `PUSH_DRY_RUN=false` (launch day) | C | owner |
| 11 | Android Developer Console | developer account + register package `com.asafrachurch.church_portal` (before 2027) | B | owner |

Click-by-click steps are in each PR file §15 (B: keystore / secrets / release; C: API / service account / secret;
D: VAPID).

## ٢. Firebase / Google Cloud — تفاصيل (details)

- **FCM is free** on Spark; no billing account needed. Topics: up to 2,000 topic subscriptions per app instance;
  no limit on subscribers per topic; fan-out to a large topic can take minutes.
- **Service-account scopes**: the Admin SDK uses `https://www.googleapis.com/auth/firebase.messaging` (send) and
  `https://www.googleapis.com/auth/datastore` / `cloud-platform` (Firestore). The two roles grant exactly that. The
  deploy account (`FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`) is **not** reused (least privilege: a leaked
  sender key cannot deploy the site).
- **Key rotation**: yearly or on suspicion — new key → update the secret → delete the old key.
- **App Check**: unchanged (assistant only). FCM does not need it.
- **Android app in Firebase**: already registered (`com.asafrachurch.church_portal`). The release SHA-256
  fingerprint is optional (App Check / Google sign-in only).

## ٣. مفتاح التوقيع (APK signing keystore)

- Created once (PR B §15). **Losing it = the app can never be updated** (users must uninstall, losing their
  settings) **and** the package cannot be registered for Android developer verification (§8).
- Backups: (1) USB stick in the church office safe, (2) password-manager entry with the `.jks` attached (or an
  encrypted zip in Google Drive), (3) passwords in the same password manager. Test once:
  `keytool -list -keystore <backup>.jks` must list the alias `church-portal`.
- Never commit the `.jks` or `android/key.properties` (git-ignored by PR B).
- Debug-signed APKs (PR artifacts) are for testers only; never publish them as "latest".

## ٤. بناء وإصدار وتحديث الـ APK (APK build → version → hosting → update)

1. Bump `version:` in `pubspec.yaml` (`1.2.0+3`: name `1.2.0`, build `3`) in a normal PR; merge.
2. GitHub → **Releases** → **Draft a new release** → tag `apk-v1.2.0` (create on publish) → title «تطبيق الكنيسة
   1.2.0» → Arabic notes → **Publish**. `android.yml` builds, signs, writes `version.json` (sizes, SHA-256, cert
   fingerprint), attaches all three files, mirrors the APKs to the releases repo `Kerollosmm/church-portal-apk` (README §8 #6) and puts `version.json` on our Hosting (~10–15 min).
3. Check: the release has both APKs + `version.json`; `https://maximos-domadios-church.web.app/app/android/version.json`
   shows build `3`; the APK URL in it downloads and its size matches.
4. `/admin` → «التطبيق والإشعارات»: الإصدار `1.2.0`, الحجم, then **رقم البناء `3` last** → **حفظ**. (The download
   links are stable per host: `<APK_BASE_URL>church-portal-arm64.apk`.)
5. Installed apps see «تحديث متاح» (their build < 3) → «تحديث الآن» → the app downloads the APK itself, checks its
   SHA-256 against `version.json`, asks once for «السماح بتثبيت التحديثات» for the church app, and opens Android's
   installer → update over the old one (same key → data kept). No browser, no releases page.
6. **Hosting (README §8 #6, decided 6 Nov 2026 19:57):** the APKs are assets of GitHub Releases in the separate
   **public** repo `Kerollosmm/church-portal-apk`; the manifest `version.json` (~500 B: version, size, SHA-256,
   download URL → the Release asset) stays on our Firebase Hosting. Why: Spark's Hosting transfer cap (10 GB/month;
   past it the whole site is disabled until next month after a short grace period) is never touched by APK
   downloads; public downloads work whatever the main repo's visibility; the main repo stays light. The workflow
   keeps the newest 5 releases there (older ones and their tags are deleted). Rejected: (a) Firebase Hosting
   `/app/android/`, (c) the main repo's Releases (only while it is public). Emergency switch later = change
   `APK_HOST` / `APK_BASE_URL`, publish the next release, update the `/admin` link; installed apps follow the
   manifest automatically. If the token expired, the release job fails red — renew `RELEASES_REPO_TOKEN` and re-run.

## ٥. إرشادات المستخدم (User guidance texts — shown in the app and on the site)

**تثبيت تطبيق Android (من خارج المتجر)** — the canonical text of PR A's visual guide (§3.3; 5 steps with
screenshot placeholders, Arabic + English there):
1. اضغط «تحميل التطبيق». إذا قال المتصفح «قد يكون هذا الملف ضارًا»: تأكد أن العنوان `maximos-domadios-church.web.app`
   ثم «تنزيل على أي حال».
2. افتح الملف من إشعار «اكتمل التنزيل» أو من «التنزيلات».
3. إذا ظهرت رسالة أن التثبيت من هذا المصدر غير مسموح: «الإعدادات» ← فعّل «السماح من هذا المصدر» للمتصفح ← ارجع
   واضغط «تثبيت». (Android 8 وأحدث: الإذن خاص بالمتصفح الذي حمّلت منه، مثل Chrome.)
4. Google Play Protect: اسمح بفحص التطبيق إذا طُلب؛ إذا قال إنه لا يعرف المطوّر: «مزيد من التفاصيل» ← «التثبيت على
   أي حال». التطبيق رسمي من موقع الكنيسة.
5. بعد التثبيت يمكنك (وهو الأكثر أمانًا) إيقاف «السماح من هذا المصدر» للمتصفح.
**للأمان:** حمّل من موقع الكنيسة فقط لا من ملفات مرسلة على واتساب · الكنيسة لا تطلب أبدًا إيقاف Play Protect بالكامل ·
الإصدار والحجم على الزر يطابقان الملف. (الشكل قد يختلف حسب الهاتف.)

**تحديث التطبيق:** عند ظهور «تحديث متاح» اضغط «تحديث الآن» — يُحمَّل التحديث داخل التطبيق ويُفحص تلقائيًا. أول مرة
فقط يطلب Android «السماح بتثبيت التطبيقات من هذا المصدر» **لتطبيق الكنيسة** (ليس للمتصفح): فعّله وارجع، ثم «تحديث».
بياناتك وإعداداتك تبقى كما هي.

**الإشعارات على Android 13 وأحدث:** عند التفعيل يسألك الهاتف «السماح بإرسال الإشعارات؟» ← «سماح». إذا رفضت:
الإعدادات ← التطبيقات ← كنيسة مكسيموس ودوماديوس ← الإشعارات ← تشغيل.

**إذا تأخرت الإشعارات (توفير البطارية):** بعض الهواتف (شاومي، أوبو، ريلمي، هواوي، سامسونج) توقف التطبيقات في
الخلفية. داخل التطبيق: «الإشعارات» ← «إذا لم تصلك الإشعارات» يعرض خطوات هاتفك بالتحديد (التشغيل التلقائي، «بدون
قيود» للبطارية، إزالة التطبيق من «التطبيقات في وضع السكون» على سامسونج)، و«افحص الإشعارات» يخبرك ما الذي يمنعها. آية
اليوم والقراءات قد تتأخر بضع دقائق — هذا طبيعي؛ تذكيراتك («ذكّرني») ترن في موعدها بالضبط.

**«ذكّرني»:** اضغط «ذكّرني» على أي قداس أو خدمة أو مناسبة واختر الوقت (في الموعد / قبل ١٥ دقيقة / قبل ساعة / قبل
يوم). في تطبيق Android يرن في موعده بالضبط. على الموقع و iPhone يصل عبر الإنترنت **وقد يتأخر حتى ٣٠ دقيقة تقريبًا**؛
للتنبيه في الموعد بالضبط اضغط «أضف إلى التقويم». تجد كل تذكيراتك في «الإشعارات» ← «تذكيراتي».

**iPhone / iPad (بدون App Store):**
1. افتح الموقع في **Safari**.
2. اضغط زر المشاركة (مربع وسهم لأعلى).
3. اختر «إضافة إلى الشاشة الرئيسية» ← «إضافة».
4. افتح الكنيسة من الأيقونة الجديدة. الإشعارات تعمل بهذه الطريقة فقط وعلى iOS 16.4 أو أحدث
   (الإعدادات ← عام ← حول ← إصدار iOS). من داخل التطبيق المثبّت: «الإشعارات» ← «تفعيل الإشعارات» ← «سماح».
   (في Safari العادي لا يظهر زر التفعيل ولا يُطلب أي إذن — هذا مقصود.)
5. على الويب و iPhone تصل إشعارات الكنيسة للأحداث وتنبيهات المواسم وتذكيراتك «ذكّرني»؛ آية اليوم وقراءات القطمارس
   والأعياد تجدها في الصفحة الرئيسية وشاشة «قراءات اليوم» (وكإشعارات محلية في تطبيق Android).
6. للإيقاف: صفحة «الإشعارات» في التطبيق، أو الإعدادات ← الإشعارات ← الكنيسة.

## ٦. الخصوصية (Privacy notice — PDPL, Egypt Law 151/2020)

Add to the privacy texts (`lib/core/l10n.dart`, the notifications page, `documentation/`), approved by the owner
(corrected after CodeRabbit on the plan PR: the web flow does transfer the chosen types with the token):

> **الإشعارات:** إذا فعّلت الإشعارات تبقى ساعات الهدوء وسجل الإشعارات على جهازك فقط. لإيصال الإشعارات يعطي متصفحك أو
> التطبيق «رمز جهاز» عشوائيًا من خدمة Google Firebase Cloud Messaging لا يحتوي على اسمك أو رقمك أو بريدك.
> - **في تطبيق Android:** يسجّل التطبيق هذا الرمز مباشرة لدى Google في قناتي «إعلانات الكنيسة» و«تنبيهات المواسم»
>   (حسب اختيارك) بلغتك فقط؛ باقي الإشعارات (آية اليوم، قراءات القطمارس، الأعياد، وتذكيراتك «ذكّرني») تُجدول على
>   هاتفك دون إرسال أي شيء.
>   لتحديث التطبيق يحمّل التطبيق ملف الإصدار الجديد من موقع الكنيسة ويطلب منك إذن تثبيته؛ لا يُرسل شيئًا عنك.
> - **على الموقع وتطبيق الويب (iPhone):** يُرسَل الرمز مع **أنواع الإشعارات التي اخترتها ولغتك** إلى قاعدة بيانات
>   الكنيسة على Google Firebase (خوادم قد تكون خارج مصر) لدقائق حتى تسجّله أداة الإرسال لدى Google ثم يُحذف من
>   قاعدة البيانات. يحتفظ Google بالاشتراك ما دمت مشتركًا. إذا استخدمت «ذكّرني» يُرسل بنفس الطريقة اسم القناة الخاصة
>   بكل تذكير (الحدث ووقت التذكير فقط، دون أي بيانات عنك).
> يمكنك الإيقاف في أي وقت من صفحة «الإشعارات» (يُلغى الاشتراك ويُحذف الرمز) أو من إعدادات الهاتف.
>
> **Notifications:** quiet hours and your notification history stay on your device. To deliver notifications your
> browser or the app gets a random device token from Google Firebase Cloud Messaging; it contains no name, phone
> number or e-mail.
> - **Android app:** the app registers this token directly with Google for the church-announcements and season-alert
>   channels you chose, in your language only; everything else (verse, Katameros readings, feasts and your «Remind me»
>   reminders) is scheduled on your phone and sends nothing. To update itself the app downloads the new version file from the church's download
>   address and asks your permission to install it; nothing about you is sent.
> - **Website / iPhone web app:** the token, **the notification types you chose and your language** are sent to the
>   church's Google Firebase database (servers may be outside Egypt) for a few minutes until the sender registers
>   them with Google, then deleted from the database. Google keeps the subscription while you stay subscribed. If you
>   use «Remind me», the channel name of each reminder (the event and lead time only, nothing about you) travels the
>   same way.
> You can stop at any time from the Notifications page (unsubscribes and deletes the token) or your phone's settings.

*Alternative paragraph — only if PR D falls back to the token list:* replace the website bullet with «يُحفَظ الرمز مع
أنواع الإشعارات التي اخترتها ولغتك في قاعدة بيانات الكنيسة على Google Firebase **طوال مدة اشتراكك**، ويُحذف عند
الإيقاف» / "the token, your chosen types and language are stored in the church's Google Firebase database **for as
long as you stay subscribed** and deleted when you unsubscribe".

Sentry rules (ADR-034) apply: never log tokens, links' query strings or user text.

## ٧. خطة الاختبار على أجهزة حقيقية (Real-device test plan)

| Device | OS | Tests |
|---|---|---|
| Samsung (A-series) | Android 14/15 | APK install following the PR A visual guide, every type, quiet hours, reboot, **in-app update** N → N+1, back button, Holy Week theme, exact «ذكّرني» after reboot, Katameros tap offline |
| Xiaomi / Redmi (HyperOS) | Android 13/14 | battery-saver guidance + diagnostic check, Autostart, permission flow, verse / Katameros over 8 days |
| Oppo / Realme, Vivo, Huawei / Honor (if available) | any | guidance buttons open the right screens; test reminder arrives |
| Old / low-end phone | Android 9–11, 32-bit | arm32 APK installs and runs |
| iPhone | iOS 17/18 | Safari tab: install-first card, **no permission prompt**; PWA install, then web push (event pushes, season alerts, «ذكّرني» with the delay copy), «أضف إلى التقويم», deep links, quiet hours, blocked state |
| iPhone | iOS ≤ 16.3 (if available) | "update iOS" message |
| Android Chrome (not installed) | any | web push |
| Windows / Mac: Chrome, Edge, Safari, Firefox | — | web push, no install banner |

Run each PR's §11 table on these, Arabic and English; record results in the PR (see HANDOFF §6).

## ٨. مخاطر خارجية يجب متابعتها (External watch items)

- **Android developer verification** (checked 6 Nov 2026,
  https://developer.android.com/developer-verification/guides): since **30 Sep 2026** apps installed on certified
  Android devices through participating stores must be registered to a verified developer in Brazil, Indonesia,
  Singapore and Thailand; Google says it expands **globally to all apps on certified devices in 2027** — that
  includes our sideloaded APK in Egypt. Unregistered apps then need the "advanced flow" (Developer options, restart,
  24-hour wait) or ADB — not acceptable for parishioners. **Before 2027:** sign up at
  https://android.google.com/developerconsole (Android Developer Console, for apps outside Google Play), choose
  **Full distribution** (identity verification) or **Limited distribution** (students / hobbyists, no identity
  verification, limited devices — check current limits), and **register `com.asafrachurch.church_portal`** by
  uploading an APK signed with the release key. Re-check every 3 months for Egypt's date and fees.
- **iOS web push** rules change with iOS releases; re-test after each major iOS release.
- **Web topic subscription** (Admin SDK `subscribeToTopic` for web tokens): if it stops working, switch to the
  token-list fallback (PR D §5) and change the privacy text (§6, alternative paragraph).
- **GitHub scheduled workflows** are disabled after 60 days without repository activity → `keepalive.yml` +
  health alerts (§14); watch the first 60-day window after launch.
- **Katameros API** (`api.katameros.app`, open source, no SLA) feeds `/data/today.json` and `/data/readings/*`:
  if it changes shape or disappears, the app keeps the last published days and falls back to computed feasts;
  `synaxarium.yml` failure e-mails show it.
- **English readings**: references only, no NKJV text (README §8 #17, decided 6 Nov 2026); switching to a
  public-domain English translation (WEB / ASV) later is a data change only.
- **Repo visibility**: if `Kerollosmm/church-portal` is made private → APK downloads are unaffected (separate public
  releases repo, §8 #6), but the 15-min cron exceeds the free Actions minutes → hourly cron (README §8 #15).
- **`RELEASES_REPO_TOKEN` expiry** (fine-grained token, releases repo only): renew before the date set at creation.
- **Firebase Hosting transfer**: APKs are not hosted there (§8 #6); glance at Hosting → Usage monthly (readings
  files + site traffic), weekly only if `APK_HOST=firebase` is ever used as an emergency switch.
- **Firebase JS SDK version** used by `push_client.js` follows FlutterFire; after upgrading `firebase_core`,
  re-test web push.

## ٩. قائمة الإصدار (Release checklist — every app release)

- [ ] PR merged with CI green; preview checked on a phone.
- [ ] `pubspec.yaml` version bumped (name + build).
- [ ] Tag `apk-vX.Y.Z` → `android.yml` green → both APKs on the release.
- [ ] Install the arm64 APK **over** the previous version on a test phone → data kept, notifications still planned.
- [ ] `version.json` live with the new build; SHA-256 matches (`sha256sum` of the downloaded file).
- [ ] In-app update tested from the previous version on a real phone (progress, permission, installer, data kept).
- [ ] `/admin` version, size updated, then build number (last).
- [ ] Sentry: no new crash in 24 h (environment `production`).
- [ ] Arabic release notes on the GitHub Release.

## ١٠. التراجع (Rollback)

| Problem | Action (fastest first) |
|---|---|
| Wrong notification scheduled | `/admin` → «الإشعارات» → delete the row (if not yet sent) |
| Sender misbehaving | GitHub → Actions → «Push sender (FCM)» → **⋯ → Disable workflow**; or `PUSH_DRY_RUN=true`; or `/admin` `push` off |
| Notifications UI problem on the site | `/admin` → «التطبيق والإشعارات» → `push` off |
| Install banner problem | `/admin` → «شريط تثبيت التطبيق» off |
| Bad web release | GitHub → the merged PR → **Revert** → merge → auto-deploy; or Firebase console → Hosting → release history → **Rollback** |
| Bad APK release | Android cannot downgrade: publish a fix with a **higher** build number; meanwhile lower `installApkBuild` in `/admin` so nobody is prompted, re-publish the previous `version.json` (`node tool/publish_hosting_file.js`), and mark the bad release "pre-release" and the previous one **Latest** |
| Sender stopped (health card red / Sentry missed check-in) | §14 «المُرسِل متوقف»: re-enable the workflow, check the last run's error; due pushes and reminders go out with the next run (catch-up) |
| Wrong reminder slots (planner bug) | `/admin` → «أنواع الإشعارات» → untick «ذكّرني» as offered (web reminders stop at the next run; APK reminders are local and unaffected) → fix PR |
| Sender key leak | delete the key in Google Cloud → new key → update the secret |
| Spam in `push_queue` | throttle + daily cap limit it; capped two days in a row → clear the VAPID key in `/admin` temporarily (enable button disabled; paste the same key back later), then App Check enforcement on Firestore or a rules PR with `allow create: if false`; the sender deletes queued docs; legitimate pending opt-ins resend themselves later (PR D §14) |

## ١١. المتابعة (Monitoring)

- **Sentry** (ADR-034): web + Android errors with `section: 'push'` / `'install'`; alert rule → e-mail the owner on
  a new `production` issue.
- **GitHub Actions** failure e-mails for `push-sender.yml`, `android.yml`, `synaxarium.yml` (GitHub → Settings →
  Notifications → Actions → failed workflows only).
- **Sender run summary**: trigger (`cron` / `manual`), sent items (event pushes, season alerts, reminder slots),
  retries, expired / late-skipped items, queue processed, cap reached, errors (no tokens).
- **Sender health**: `/admin` health card (amber > 1 h, red > 3 h) + Sentry cron monitor `push-sender` (e-mail on
  missed / failed check-ins) + `push.sender_stale` Sentry message (§14).
- **Firebase console → Messaging → Reports**: aggregate Android delivery (sent / received / opened).
- **Firestore usage**: Firebase console → Firestore → Usage — **daily** for the first two weeks after `push` is on
  (reads included: rejected `push_queue` requests still cost rule reads, PR D §5), then weekly.

## ١٢. دليل المشرف (Admin runbook)

| When | What |
|---|---|
| Weekly (5 min) | `/admin` → «الإشعارات» → السجل: any `error`? upcoming one-offs correct? |
| Before each feast / season | one-off announcement with a deep link to the season page; check the season dates (they drive "season starts") |
| Daily verse | automatic; fixed / season verses as today |
| Monthly | GitHub → Actions: `push-sender` ran recently, `keepalive.yml` ran on the 1st and is green; Sentry clean |
| Every app release | §9 |
| Yearly | rotate the sender key; open the keystore backup; review texts |
| Every 3 months | §8 watch items |

Admin golden rules: title ≤ 40 chars, body ≤ 120 shows fully; always set a deep link (or pick the event); at most ~1
event push a day; pushes are **scheduled, not instant** — set the time 30 min before you need it to arrive; never
personal data in a notification; never send the verse, Katameros, a feast or a «remind me» style mass reminder as a
push (they are local in the app and users set their own reminders — duplicate).

## ١٣. يوم الإطلاق (Launch-day checklist)

**قبلها بأسبوع**
- [ ] Whole PR chain merged (HANDOFF §5.6); Lighthouse mobile ≥ 61 on the live site.
- [ ] Keystore created + 2 backups; secrets set; first signed APK released; `/admin` APK fields filled.
- [ ] FCM API enabled; `push-sender` SA + `FIREBASE_SA_PUSH`; dry runs (`PUSH_DRY_RUN=true`) correct for 3 days.
- [ ] `keepalive.yml` manual run green; Sentry cron monitor receiving check-ins; `/admin` health card green (§14).
- [ ] `/data/readings/*.json` live for the next 9 days (open one in the browser); reading screen OK offline on a phone.
- [ ] Releases repo `Kerollosmm/church-portal-apk` live with the first release, `RELEASES_REPO_TOKEN` + variables
      set, manifest URLs point at its Release assets, and the in-app update tested from build N to N+1 on a real phone.
- [ ] VAPID key saved in `/admin`.
- [ ] Real-device plan (§7) passed and recorded.
- [ ] Privacy texts approved (§6).
- [ ] Types & texts reviewed by the priest / secretariat; verse time agreed.
- [ ] Android developer-verification status for Egypt checked (§8).

**يوم الإطلاق**
- [ ] `/admin` → «الإشعارات» → offered types → `push` **on**.
- [ ] GitHub → Variables → `PUSH_DRY_RUN` = `false`.
- [ ] Owner's phones: APK + iPhone PWA, all types on, a test event push (+15 min, link `/mass-schedule`) received
      exactly once within ~30 min; a «ذكّرني» on each phone (APK on the minute; iPhone within ~30 min).
- [ ] Announce (church, WhatsApp channel, Facebook): site link + «حمّل التطبيق» + iPhone steps (§5) + short screen
      recording.
- [ ] Check Sentry and the sender summary at noon and evening.

**بعدها بأسبوع**
- [ ] Review delivery reports, error log, Firestore usage, servants' feedback; adjust times / texts.
- [ ] Tag the first fix release if needed.

## ١٤. استمرار التشغيل وصحة المُرسِل (Keep-alive + sender health runbook — owner 19:35)

> Replaces the former «urgent-dispatch token» runbook: the instant-dispatch design was **removed** on 6 Nov 2026
> 19:31 (speed is not important). There is no dispatch token to create, rotate or revoke.

**Why:** GitHub disables scheduled workflows in a public repo after **60 days without repository activity**
(https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/disabling-and-enabling-a-workflow).
The sender, `synaxarium.yml` (commemoration + Katameros readings files) and the keep-alive itself are scheduled.

**Keep-alive (set up once with PR C):** `.github/workflows/keepalive.yml` runs on the 1st of every month and calls
`PUT /repos/Kerollosmm/church-portal/actions/workflows/<file>/disable` followed by `/enable` for `push-sender.yml`
and `synaxarium.yml` (plus `/enable` on itself) with the run's own `GITHUB_TOKEN` (`permissions: actions: write`) — no
personal token, no commit, nothing pushed to `main` (PR C §17). After merge: GitHub → Actions → «Keep scheduled
workflows enabled» → **Run workflow** → green. **First 60 days after launch:** note the date of the last commit;
around day 55 check GitHub → Actions that no workflow shows "This scheduled workflow is disabled" — if one does,
click **Enable workflow** and fall back to the alerts below (and tell the developer to revisit PR C §17).

**Sender health — what alerts you:**
1. `/admin` → «الإشعارات»: «آخر تشغيل للمُرسِل» — amber after 1 h, **red after 3 h**.
2. Sentry cron monitor `push-sender` (free plan includes one cron monitor — https://docs.sentry.io/pricing/): e-mail
   after 3 missed / failed check-ins or no check-in for 3 h. Setup: PR C §15 step 6 (secret `SENTRY_CRONS_URL`).
3. Sentry issue `push.sender_stale` raised by an admin's browser that sees a red card.
4. GitHub failed-run e-mails (§11).

**«المُرسِل متوقف» — what to do (10 min):**
1. GitHub → Actions → «Push sender (FCM)»: if it says *disabled* → **Enable workflow**; then **Run workflow**
   (dry run off only if `PUSH_DRY_RUN` is already `false`; otherwise keep the default) → green?
2. If runs fail: open the last run → error. Common: `FIREBASE_SA_PUSH` key deleted / expired → new key (PR C §15
   step 3–4); FCM API disabled → enable; Firestore quota exhausted → wait for the reset (Pacific midnight) and check
   usage (§11).
3. Nothing is lost: the next successful run **catches up** — event pushes due in the last 24 h are sent, reminders
   still before their event are sent, older ones are marked «فات موعده» / skipped (visible in `/admin`).
4. If GitHub Actions itself is down: wait; status at https://www.githubstatus.com.

**`production` environment (recommended hygiene, not required):** GitHub → repo → **Settings** → **Environments** →
`production` → **Required reviewers** → add yourself → **Save protection rules**. Then `seed.yml` (whose `force` /
`admin_email` inputs can overwrite production data or add an owner) and rules deploys wait for your approval. No
Phase 2 feature depends on it any more (README §8 #19); it simply protects against a mistaken manual run.
