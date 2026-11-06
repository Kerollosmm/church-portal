# الإطلاق والتشغيل (Launch & operations — everything outside the code)

Everything needed to make Phase 2 real, after (or alongside) PRs A–E: consoles, keys, signing, hosting, user
guidance, privacy, real-device tests, release, rollback, monitoring, the admin runbook and the launch-day checklist.

## ١. ملخص الإعدادات خارج الكود (One-time setup summary)

| # | Where | What | PR | Who |
|---|---|---|---|---|
| 1 | Your computer | create the APK signing keystore + 2 backups | B | owner |
| 2 | GitHub → Settings → Secrets → Actions | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | B | owner |
| 2b | GitHub → Variables (+ new public repo if chosen) | APK host decision (README §8 #6): `APK_HOST`, `APK_BASE_URL`; for `releases-repo` create `Kerollosmm/church-portal-apk` + secret `RELEASES_REPO_TOKEN` | B | owner |
| 3 | GitHub → Releases | first tag `apk-v1.1.0` → APKs + `version.json` attached and published (after the chain is merged) | B | owner |
| 4 | `/admin` → «التطبيق والإشعارات» | APK URLs, version, build, size | B | admin |
| 5 | Google Cloud → APIs | enable **Firebase Cloud Messaging API** | C | owner |
| 6 | Google Cloud → IAM → Service accounts | `push-sender` with **Firebase Cloud Messaging API Admin** + **Cloud Datastore User**, JSON key | C | owner |
| 7 | GitHub → Secrets / Variables | secret `FIREBASE_SA_PUSH`, variable `PUSH_DRY_RUN=true` | C | owner |
| 7b | GitHub → Developer settings → Fine-grained tokens, then `/admin` | urgent-dispatch token (this repo, Actions: write only, 90 days) saved in «رمز الإرسال الفوري» (§14) | C | owner |
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
   fingerprint), attaches all three files and publishes them to the chosen host (~10–15 min).
3. Check: the release has both APKs + `version.json`; `https://maximos-domadios-church.web.app/app/android/version.json`
   shows build `3`; the APK URL in it downloads and its size matches.
4. `/admin` → «التطبيق والإشعارات»: الإصدار `1.2.0`, الحجم, then **رقم البناء `3` last** → **حفظ**. (The download
   links are stable per host: `<APK_BASE_URL>church-portal-arm64.apk`.)
5. Installed apps see «تحديث متاح» (their build < 3) → «تحديث الآن» → the app downloads the APK itself, checks its
   SHA-256 against `version.json`, asks once for «السماح بتثبيت التحديثات» for the church app, and opens Android's
   installer → update over the old one (same key → data kept). No browser, no releases page.
6. **Hosting choice (owner, README §8 #6):**
   | Host | Public download works if… | Cost / risk |
   |---|---|---|
   | (a) Firebase Hosting `/app/android/` | always | counts against the project's Hosting transfer (Spark 10 GB/month; past it the whole site is disabled until next month after a short grace period); watch usage weekly (§11), switch before ~7 GB/month |
   | (b) public repo `Kerollosmm/church-portal-apk` Releases (**recommended**) | always (repo public, contains only releases) | free, no effect on the site's quota; one extra token `RELEASES_REPO_TOKEN` (that repo only, Contents: write) |
   | (c) this repo's Releases | **only while `Kerollosmm/church-portal` is public** — release assets of a private repo are not downloadable by the public | free; GitHub reports the repo public on 6 Nov 2026, the owner called it private → confirm |
   The manifest itself is always on our Hosting (tiny). Changing host later = change `APK_HOST` / `APK_BASE_URL`,
   publish the next release, update the `/admin` link; installed apps follow the manifest automatically.

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
الخلفية: الإعدادات ← البطارية (أو التطبيقات) ← كنيسة مكسيموس ودوماديوس ← «بدون قيود». على سامسونج: أزل التطبيق من
«التطبيقات في وضع السكون». قد تتأخر الإشعارات المجدولة بضع دقائق — هذا طبيعي (لا نطلب إذن «المنبّهات الدقيقة»).

**iPhone / iPad (بدون App Store):**
1. افتح الموقع في **Safari**.
2. اضغط زر المشاركة (مربع وسهم لأعلى).
3. اختر «إضافة إلى الشاشة الرئيسية» ← «إضافة».
4. افتح الكنيسة من الأيقونة الجديدة. الإشعارات تعمل بهذه الطريقة فقط وعلى iOS 16.4 أو أحدث
   (الإعدادات ← عام ← حول ← إصدار iOS). من داخل التطبيق المثبّت: «الإشعارات» ← «تفعيل الإشعارات» ← «سماح».
   (في Safari العادي لا يظهر زر التفعيل ولا يُطلب أي إذن — هذا مقصود.)
5. على الويب و iPhone تصل إعلانات الكنيسة وتنبيهات المواسم فقط؛ آية اليوم والأعياد ومواعيد القداس تجدها في الصفحة
   الرئيسية للموقع (وكإشعارات محلية في تطبيق Android).
6. للإيقاف: صفحة «الإشعارات» في التطبيق، أو الإعدادات ← الإشعارات ← الكنيسة.

## ٦. الخصوصية (Privacy notice — PDPL, Egypt Law 151/2020)

Add to the privacy texts (`lib/core/l10n.dart`, the notifications page, `documentation/`), approved by the owner
(corrected after CodeRabbit on the plan PR: the web flow does transfer the chosen types with the token):

> **الإشعارات:** إذا فعّلت الإشعارات تبقى ساعات الهدوء وسجل الإشعارات على جهازك فقط. لإيصال الإشعارات يعطي متصفحك أو
> التطبيق «رمز جهاز» عشوائيًا من خدمة Google Firebase Cloud Messaging لا يحتوي على اسمك أو رقمك أو بريدك.
> - **في تطبيق Android:** يسجّل التطبيق هذا الرمز مباشرة لدى Google في قناتي «إعلانات الكنيسة» و«تنبيهات المواسم»
>   (حسب اختيارك) بلغتك فقط؛ باقي الإشعارات (آية اليوم، الأعياد، تذكيرات القداس) تُجدول على هاتفك دون إرسال أي شيء.
>   لتحديث التطبيق يحمّل التطبيق ملف الإصدار الجديد من موقع الكنيسة ويطلب منك إذن تثبيته؛ لا يُرسل شيئًا عنك.
> - **على الموقع وتطبيق الويب (iPhone):** يُرسَل الرمز مع **أنواع الإشعارات التي اخترتها ولغتك** إلى قاعدة بيانات
>   الكنيسة على Google Firebase (خوادم قد تكون خارج مصر) لدقائق حتى تسجّله أداة الإرسال لدى Google ثم يُحذف من
>   قاعدة البيانات. يحتفظ Google بالاشتراك ما دمت مشتركًا.
> يمكنك الإيقاف في أي وقت من صفحة «الإشعارات» (يُلغى الاشتراك ويُحذف الرمز) أو من إعدادات الهاتف.
>
> **Notifications:** quiet hours and your notification history stay on your device. To deliver notifications your
> browser or the app gets a random device token from Google Firebase Cloud Messaging; it contains no name, phone
> number or e-mail.
> - **Android app:** the app registers this token directly with Google for the church-announcements and season-alert
>   channels you chose, in your language only; everything else (verse, feasts, mass reminders) is scheduled on your
>   phone and sends nothing. To update itself the app downloads the new version file from the church's download
>   address and asks your permission to install it; nothing about you is sent.
> - **Website / iPhone web app:** the token, **the notification types you chose and your language** are sent to the
>   church's Google Firebase database (servers may be outside Egypt) for a few minutes until the sender registers
>   them with Google, then deleted from the database. Google keeps the subscription while you stay subscribed.
> You can stop at any time from the Notifications page (unsubscribes and deletes the token) or your phone's settings.

Sentry rules (ADR-034) apply: never log tokens, links' query strings or user text.

## ٧. خطة الاختبار على أجهزة حقيقية (Real-device test plan)

| Device | OS | Tests |
|---|---|---|
| Samsung (A-series) | Android 14/15 | APK install following the PR A visual guide, every type, quiet hours, reboot, **in-app update** N → N+1, back button, Holy Week theme |
| Xiaomi / Redmi | Android 13/14 | battery-optimisation delay, permission flow |
| Old / low-end phone | Android 9–11, 32-bit | arm32 APK installs and runs |
| iPhone | iOS 17/18 | Safari tab: install-first card, **no permission prompt**; PWA install, then web push (announcements, season alerts), deep links, quiet hours, blocked state |
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
- **Urgent-dispatch token expiry** (`admin_secrets/github_dispatch.expiresOn`): the admin card warns 14 days before;
  rotate per §14. An expired token only slows urgent sends to the cron (fallback), it never loses one.
- **Repo visibility**: if `Kerollosmm/church-portal` is made private → APK host (c) stops working publicly and the
  15-min cron exceeds the free Actions minutes → hourly cron (README §8 #15).
- **Firebase Hosting transfer** (only if APKs are hosted there): Firebase console → Hosting → Usage, weekly.
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
| Urgent sends misbehaving / token suspected leaked | GitHub → Settings → Developer settings → Fine-grained tokens → **Delete** the token; `/admin` → «رمز الإرسال الفوري» → delete; urgent rows still go out with the next cron run (§14) |
| Sender key leak | delete the key in Google Cloud → new key → update the secret |
| Spam in `push_queue` | throttle limits it; a rules PR with `allow create: if false`; the sender deletes queued docs |

## ١١. المتابعة (Monitoring)

- **Sentry** (ADR-034): web + Android errors with `section: 'push'` / `'install'`; alert rule → e-mail the owner on
  a new `production` issue.
- **GitHub Actions** failure e-mails for `push-sender.yml`, `android.yml`, `synaxarium.yml` (GitHub → Settings →
  Notifications → Actions → failed workflows only).
- **Sender run summary**: trigger (`cron` / `urgent` / `manual`), sent items, queue processed, errors (no tokens).
- **Dispatch failures**: rows with `dispatch = failed:<code>` in `/admin` (401 = token expired / revoked → §14).
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
| Every 90 days | rotate the urgent-dispatch token (§14) |
| Yearly | rotate the sender key; open the keystore backup; review texts |
| Every 3 months | §8 watch items |

Admin golden rules: title ≤ 40 chars, body ≤ 120 shows fully; always set a deep link; at most ~1 announcement a
day; «عاجل» only for real emergencies / a live broadcast starting now (it reaches everyone within ~2 minutes); never
personal data in a notification; never send the verse, a feast or a mass reminder as a one-off (they are already
local in the app — duplicate).

## ١٣. يوم الإطلاق (Launch-day checklist)

**قبلها بأسبوع**
- [ ] Whole PR chain merged (HANDOFF §5.6); Lighthouse mobile ≥ 61 on the live site.
- [ ] Keystore created + 2 backups; secrets set; first signed APK released; `/admin` APK fields filled.
- [ ] FCM API enabled; `push-sender` SA + `FIREBASE_SA_PUSH`; dry runs (`PUSH_DRY_RUN=true`) correct for 3 days.
- [ ] Urgent-dispatch token saved (§14); a dry-run urgent send shows «في الطابور» → the run appears in Actions within
      a minute with trigger `urgent`.
- [ ] APK host chosen and the in-app update tested from build N to N+1 on a real phone.
- [ ] VAPID key saved in `/admin`.
- [ ] Real-device plan (§7) passed and recorded.
- [ ] Privacy texts approved (§6).
- [ ] Types & texts reviewed by the priest / secretariat; verse time agreed.
- [ ] Android developer-verification status for Egypt checked (§8).

**يوم الإطلاق**
- [ ] `/admin` → «الإشعارات» → offered types → `push` **on**.
- [ ] GitHub → Variables → `PUSH_DRY_RUN` = `false`.
- [ ] Owner's phones: APK + iPhone PWA, all types on, a test one-off (+15 min, link `/mass-schedule`) received, and
      one urgent test to the test topic received in ~1–2 min — exactly once.
- [ ] Announce (church, WhatsApp channel, Facebook): site link + «حمّل التطبيق» + iPhone steps (§5) + short screen
      recording.
- [ ] Check Sentry and the sender summary at noon and evening.

**بعدها بأسبوع**
- [ ] Review delivery reports, error log, Firestore usage, servants' feedback; adjust times / texts.
- [ ] Tag the first fix release if needed.

## ١٤. رمز الإرسال الفوري (Urgent-dispatch token runbook — create, store, rotate, revoke)

Why: `/admin` triggers `push-sender.yml` immediately for urgent one-offs (PR C §16). Spark has no Cloud Functions,
so the admin's browser calls GitHub's API itself with a token that must never be public.

**Create (owner, ~3 min)**
1. Owner Google accounts used for `/admin` have **2-step verification** on (the token is readable by owner-role
   admins only).
2. GitHub (account `Kerollosmm`) → avatar → **Settings** → **Developer settings** → **Personal access tokens** →
   **Fine-grained tokens** → **Generate new token**.
3. Token name `church-portal-urgent-dispatch`; **Expiration: 90 days** (custom date); Resource owner `Kerollosmm`.
4. **Repository access → Only select repositories → `Kerollosmm/church-portal`**.
5. **Repository permissions → Actions: Read and write.** Leave everything else at **No access** (Metadata: Read-only
   is added automatically). **Never add Contents** (that would allow pushing code) — if dispatch is refused, use the
   Worker option below instead.
6. **Generate token** → copy it once (starts with `github_pat_`).
7. `/admin` → «الإشعارات» → «رمز الإرسال الفوري» → paste, set «ينتهي في» to the same date → **حفظ**. The card then
   shows only «محفوظ — ينتهي في …». Do not keep the token anywhere else (no notes, chats, e-mails).
8. Test: with `PUSH_DRY_RUN=true`, «إرسال عاجل الآن» to the test topic → chip «في الطابور» → GitHub → Actions shows a
   «Push sender (FCM)» run with trigger `urgent` within a minute.

**Rotate (every 90 days, or when an admin with owner role leaves)**: create a new token as above → paste it in
`/admin` (overwrites) → test → GitHub → Fine-grained tokens → **Delete** the old one. Calendar reminder 7 days before
expiry; the admin card warns from 14 days before.

**Revoke (suspected leak)**: GitHub → Fine-grained tokens → **Delete** (instant) → `/admin` → delete the token →
GitHub → Actions: cancel unknown runs, re-enable any disabled workflow, check `deploy.yml` / `seed.yml` /
`android.yml` runs of the last days → create a new token later. Nothing else needs changing: the token could never
read code or secrets.

**Expired / missing token** → urgent rows show «فشل الإرسال الفوري — سيُرسل في الدورة التالية» and go out with the next
cron run (15–30 min). Nothing is lost.

**Optional hardening — Cloudflare Worker proxy (token never reaches a browser)**: free Cloudflare account →
Workers → new Worker `church-dispatch` → secret `GITHUB_TOKEN` (same fine-grained token) + variable `OWNER_UIDS` →
code (~60 lines, kept in `tool/dispatch-worker/` if adopted): accept `POST {row_id}` only from the site origin, verify
the `Authorization: Bearer <Firebase ID token>` against Google's public keys (`aud`/`iss` =
`asafra-church-portal`, not expired, `uid` in `OWNER_UIDS`), then call the GitHub dispatch API. `/admin` then calls
the Worker instead of GitHub and `admin_secrets/github_dispatch` is deleted. Free tier ≈ 100k requests/day.

