# الإطلاق والتشغيل (Launch & operations — everything outside the code)

Everything needed to make Phase 2 real, after (or alongside) PRs A–E: consoles, keys, signing, hosting, user
guidance, privacy, real-device tests, release, rollback, monitoring, the admin runbook and the launch-day checklist.

## ١. ملخص الإعدادات خارج الكود (One-time setup summary)

| # | Where | What | PR | Who |
|---|---|---|---|---|
| 1 | Your computer | create the APK signing keystore + 2 backups | B | owner |
| 2 | GitHub → Settings → Secrets → Actions | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | B | owner |
| 3 | GitHub → Releases | first tag `apk-v1.1.0` → APKs attached (after the chain is merged) | B | owner |
| 4 | `/admin` → «التطبيق والإشعارات» | APK URLs, version, build, size | B | admin |
| 5 | Google Cloud → APIs | enable **Firebase Cloud Messaging API** | C | owner |
| 6 | Google Cloud → IAM → Service accounts | `push-sender` with **Firebase Cloud Messaging API Admin** + **Cloud Datastore User**, JSON key | C | owner |
| 7 | GitHub → Secrets / Variables | secret `FIREBASE_SA_PUSH`, variable `PUSH_DRY_RUN=true` | C | owner |
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
   1.2.0» → Arabic notes → **Publish**. `android.yml` builds, signs, attaches `church-portal-arm64.apk` +
   `church-portal-arm32.apk` (~10–15 min).
3. Check the release page: both files present; note the sizes.
4. `/admin` → «التطبيق والإشعارات»: الإصدار `1.2.0`, رقم البناء `3`, الحجم → **حفظ**. The APK URLs use
   `/releases/latest/download/…` so they never change.
5. Installed apps see «تحديث متاح» (their build < 3) → download → install over the old one (same key → data kept).
6. Hosting choice: **GitHub Releases** (public repo). Firebase Hosting `/downloads/` would allow only ~18
   downloads/day of a 20 MB APK on Spark (360 MB/day).

## ٥. إرشادات المستخدم (User guidance texts — shown in the app and on the site)

**تثبيت تطبيق Android (من خارج المتجر):**
1. اضغط «تحميل التطبيق» وانتظر انتهاء التحميل.
2. افتح الملف من الإشعار أو من «التنزيلات».
3. إذا ظهرت رسالة أن التثبيت من هذا المصدر غير مسموح: اضغط «الإعدادات» ← فعّل «السماح من هذا المصدر» ← ارجع
   واضغط «تثبيت». (Android 8 وأحدث: الإذن خاص بالمتصفح الذي حمّلت منه، مثل Chrome.)
4. إذا ظهر تحذير Google Play Protect: اضغط «تفاصيل إضافية» ← «التثبيت على أي حال». التطبيق رسمي من موقع الكنيسة.
5. بعد التثبيت يمكنك إلغاء «السماح من هذا المصدر».

**الإشعارات على Android 13 وأحدث:** عند التفعيل يسألك الهاتف «السماح بإرسال الإشعارات؟» ← «سماح». إذا رفضت:
الإعدادات ← التطبيقات ← كنيسة مكسيموس ودوماديوس ← الإشعارات ← تشغيل.

**إذا تأخرت الإشعارات (توفير البطارية):** بعض الهواتف (شاومي، أوبو، ريلمي، هواوي، سامسونج) توقف التطبيقات في
الخلفية: الإعدادات ← البطارية (أو التطبيقات) ← كنيسة مكسيموس ودوماديوس ← «بدون قيود». على سامسونج: أزل التطبيق من
«التطبيقات في وضع السكون». قد تتأخر الإشعارات المجدولة بضع دقائق — هذا طبيعي (لا نطلب إذن «المنبّهات الدقيقة»).

**iPhone / iPad (بدون App Store):**
1. افتح الموقع في **Safari**.
2. اضغط زر المشاركة (مربع وسهم لأعلى).
3. اختر «إضافة إلى الشاشة الرئيسية» ← «إضافة».
4. افتح الكنيسة من الأيقونة الجديدة. الإشعارات تعمل بهذه الطريقة فقط وعلى iOS 16.4 أو أحدث
   (الإعدادات ← عام ← حول ← إصدار iOS).
5. للإيقاف: صفحة «الإشعارات» في التطبيق، أو الإعدادات ← الإشعارات ← الكنيسة.

## ٦. الخصوصية (Privacy notice — PDPL, Egypt Law 151/2020)

Add to the privacy texts (`lib/core/l10n.dart`, the notifications page, `documentation/`), approved by the owner
(corrected after CodeRabbit on the plan PR: the web flow does transfer the chosen types with the token):

> **الإشعارات:** إذا فعّلت الإشعارات تبقى ساعات الهدوء وسجل الإشعارات على جهازك فقط. لإيصال الإشعارات يعطي متصفحك أو
> التطبيق «رمز جهاز» عشوائيًا من خدمة Google Firebase Cloud Messaging لا يحتوي على اسمك أو رقمك أو بريدك.
> - **في تطبيق Android:** يسجّل التطبيق هذا الرمز مباشرة لدى Google في قناة «إعلانات الكنيسة» بلغتك فقط؛ باقي
>   الإشعارات (آية اليوم، المواسم، الأعياد، التذكيرات) تُجدول على هاتفك دون إرسال أي شيء.
> - **على الموقع وتطبيق الويب (iPhone):** يُرسَل الرمز مع **أنواع الإشعارات التي اخترتها ولغتك** إلى قاعدة بيانات
>   الكنيسة على Google Firebase (خوادم قد تكون خارج مصر) لدقائق حتى تسجّله أداة الإرسال لدى Google ثم يُحذف من
>   قاعدة البيانات. يحتفظ Google بالاشتراك ما دمت مشتركًا.
> يمكنك الإيقاف في أي وقت من صفحة «الإشعارات» (يُلغى الاشتراك ويُحذف الرمز) أو من إعدادات الهاتف.
>
> **Notifications:** quiet hours and your notification history stay on your device. To deliver notifications your
> browser or the app gets a random device token from Google Firebase Cloud Messaging; it contains no name, phone
> number or e-mail.
> - **Android app:** the app registers this token directly with Google for the church-announcements channel in your
>   language only; everything else (verse, seasons, feasts, reminders) is scheduled on your phone and sends nothing.
> - **Website / iPhone web app:** the token, **the notification types you chose and your language** are sent to the
>   church's Google Firebase database (servers may be outside Egypt) for a few minutes until the sender registers
>   them with Google, then deleted from the database. Google keeps the subscription while you stay subscribed.
> You can stop at any time from the Notifications page (unsubscribes and deletes the token) or your phone's settings.

Sentry rules (ADR-034) apply: never log tokens, links' query strings or user text.

## ٧. خطة الاختبار على أجهزة حقيقية (Real-device test plan)

| Device | OS | Tests |
|---|---|---|
| Samsung (A-series) | Android 14/15 | APK install, every type, quiet hours, reboot, update over the old version, back button, Holy Week theme |
| Xiaomi / Redmi | Android 13/14 | battery-optimisation delay, permission flow |
| Old / low-end phone | Android 9–11, 32-bit | arm32 APK installs and runs |
| iPhone | iOS 17/18 | PWA install, web push, deep links, quiet hours, blocked state |
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
- **Instance ID API** (web topic subscription): if retired, switch to the token-list fallback (PR D §5).
- **GitHub scheduled workflows** are disabled after 60 days without repository activity.
- **Firebase JS SDK version** used by `push_client.js` follows FlutterFire; after upgrading `firebase_core`,
  re-test web push.

## ٩. قائمة الإصدار (Release checklist — every app release)

- [ ] PR merged with CI green; preview checked on a phone.
- [ ] `pubspec.yaml` version bumped (name + build).
- [ ] Tag `apk-vX.Y.Z` → `android.yml` green → both APKs on the release.
- [ ] Install the arm64 APK **over** the previous version on a test phone → data kept, notifications still planned.
- [ ] `/admin` version, build, size updated.
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
| Bad APK release | Android cannot downgrade: publish a fix with a **higher** build number; meanwhile mark the bad release "pre-release" and the previous one **Latest**; lower `installApkBuild` in `/admin` so nobody is prompted |
| Sender key leak | delete the key in Google Cloud → new key → update the secret |
| Spam in `push_queue` | throttle limits it; a rules PR with `allow create: if false`; the sender deletes queued docs |

## ١١. المتابعة (Monitoring)

- **Sentry** (ADR-034): web + Android errors with `section: 'push'` / `'install'`; alert rule → e-mail the owner on
  a new `production` issue.
- **GitHub Actions** failure e-mails for `push-sender.yml`, `android.yml`, `synaxarium.yml` (GitHub → Settings →
  Notifications → Actions → failed workflows only).
- **Sender run summary**: sent items, queue processed, errors (no tokens).
- **Firebase console → Messaging → Reports**: aggregate Android delivery (sent / received / opened).
- **Firestore usage**: Firebase console → Firestore → Usage, weekly during the first month.

## ١٢. دليل المشرف (Admin runbook)

| When | What |
|---|---|
| Weekly (5 min) | `/admin` → «الإشعارات» → السجل: any `error`? upcoming one-offs correct? |
| Before each feast / season | one-off announcement with a deep link to the season page; check the season dates (they drive "season starts") |
| Daily verse | automatic; fixed / season verses as today |
| Monthly | GitHub → Actions: `push-sender` ran recently (not disabled); Sentry clean |
| Every app release | §9 |
| Yearly | rotate the sender key; open the keystore backup; review texts |
| Every 3 months | §8 watch items |

Admin golden rules: title ≤ 40 chars, body ≤ 120 shows fully; always set a deep link; at most ~1 announcement a
day; never personal data in a notification.

## ١٣. يوم الإطلاق (Launch-day checklist)

**قبلها بأسبوع**
- [ ] Whole PR chain merged (HANDOFF §5.6); Lighthouse mobile ≥ 61 on the live site.
- [ ] Keystore created + 2 backups; secrets set; first signed APK released; `/admin` APK fields filled.
- [ ] FCM API enabled; `push-sender` SA + `FIREBASE_SA_PUSH`; dry runs (`PUSH_DRY_RUN=true`) correct for 3 days.
- [ ] VAPID key saved in `/admin`.
- [ ] Real-device plan (§7) passed and recorded.
- [ ] Privacy texts approved (§6).
- [ ] Types & texts reviewed by the priest / secretariat; verse time agreed.
- [ ] Android developer-verification status for Egypt checked (§8).

**يوم الإطلاق**
- [ ] `/admin` → «الإشعارات» → offered types → `push` **on**.
- [ ] GitHub → Variables → `PUSH_DRY_RUN` = `false`.
- [ ] Owner's phones: APK + iPhone PWA, all types on, a test one-off (+15 min, link `/mass-schedule`) received.
- [ ] Announce (church, WhatsApp channel, Facebook): site link + «حمّل التطبيق» + iPhone steps (§5) + short screen
      recording.
- [ ] Check Sentry and the sender summary at noon and evening.

**بعدها بأسبوع**
- [ ] Review delivery reports, error log, Firestore usage, servants' feedback; adjust times / texts.
- [ ] Tag the first fix release if needed.
