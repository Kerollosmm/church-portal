# PR B — تطبيق Android (APK) + الإشعارات المحلية (Android APK + local notifications)

| | |
|---|---|
| Branch → base | `feat/p2b-android-local-notifications` → `feat/p2a-install-prefs` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-058** |
| Depends on | PR A (type model `NotifyType`, `PushPrefs`, install fields `installApkBuild` / `installAndroidUrl`) |
| Owner console work | **signing keystore + 4 GitHub secrets** (§15). Without them CI produces debug-signed *test* APKs only |
| Live effect after merge | none on the website; a signed APK + its version manifest are published by a tag (§12) to the download host chosen in README §8 #6, then the URL goes into `/admin` |

## ١. الهدف (Goal)

A small, complete Android app built from the same Flutter code, downloaded from the site as an APK, that schedules
**local notifications on the phone** — the **local-owned** types on Android: **verse of the day** and the day's
**Katameros readings** (rolling ~9-day window, inexact; tapping opens the full verse / full readings, offline), feasts /
commemorations, and the user's own **«ذكّرني» event reminders** (exact time when allowed, reboot-safe, following
edits) — from data it already loads plus static Hosting JSON (no server, no extra Firestore reads), following the
admin's configuration (built-in defaults until PR C adds the admin editor) and the user's choices. Remote types
(admin event pushes and dynamic season alerts) arrive by FCM in PR C and are **never** planned locally (README §3.1).
Because Xiaomi / Oppo / Vivo / Huawei / Samsung battery savers can kill local alarms, the app ships a **per-brand
guidance screen** and a **diagnostic check** (§3.6, owner 19:35). The app **updates itself**: it downloads the new APK inside the app,
verifies its SHA-256 against a version manifest and hands it to Android's package installer (§3.3).

## ٢. قصص المستخدم (User stories)

- أحمّل التطبيق من الموقع وأثبته، يفتح بشاشة البداية وأيقونة الختم، بالعربي أو الإنجليزي كما اخترت آخر مرة.
- أفتح «الإشعارات» في القائمة: أختار آية اليوم الساعة ٧ صباحًا، وقراءات القطمارس الساعة ٦:٣٠، وتنبيهات المواسم
  وإشعارات الأحداث (تصل من الكنيسة عبر الإنترنت).
- أضغط إشعار القطمارس فتفتح شاشة «قراءات اليوم» كاملة (البولس، الكاثوليكون، الإبركسيس، السنكسار، المزمور والإنجيل)
  حتى بدون إنترنت؛ وإشعار الآية يفتح الآية كاملة بمرجعها.
- على كارت «صلاة الساعة السادسة — الجمعة العظيمة» أضغط «ذكّرني» ← «قبل ساعة»؛ يرن التذكير في موعده بالضبط حتى لو
  أعدت تشغيل الهاتف، ولو غيّرت الكنيسة الموعد يتحرك التذكير معه، ولو أُلغيت الخدمة يُلغى ويُقال لي.
- هاتفي شاومي: صفحة «إذا لم تصلك الإشعارات» تشرح لي خطوة بخطوة «التشغيل التلقائي» و«بدون قيود» للبطارية، وزر
  «افحص الإشعارات» يخبرني ما المشكلة.
- تصلني الإشعارات حتى بدون إنترنت (مجدولة على الهاتف)، ولا تصلني في ساعات الهدوء.
- أضغط الإشعار فيفتح الصفحة المناسبة (مواعيد القداسات، الموسم، …).
- أرى سجل آخر الإشعارات داخل التطبيق.
- عند صدور إصدار جديد أرى «تحديث متاح»، أضغط «تحديث الآن» فيُحمَّل داخل التطبيق مع شريط تقدم، ثم تظهر شاشة التثبيت
  من Android مباشرة — بدون فتح المتصفح أو صفحة الإصدارات.
- زر الرجوع في Android يرجع للصفحة الأم ثم للرئيسية ثم يخرج من التطبيق.
- لا توجد لوحة تحكم داخل التطبيق.

## ٣. الخصائص الفرعية (Complete sub-features)

### 3.1 App shell
| Sub-feature | Detail |
|---|---|
| Admin compiled out | `router.dart`: `if (kIsWeb) GoRoute(AppConfig.adminPath …)` — `kIsWeb` is a compile-time constant, so the admin code is tree-shaken out of the APK; `/admin` deep link → 404 |
| Assistant | App Check on Android needs Play Integrity (Play-only). In the APK, «اسأل الكنيسة» opens `https://maximos-domadios-church.web.app/ask` in the browser (`url_launcher`, external) — decision #10 |
| Language memory | `LanguageStore` on Android via `shared_preferences` (today a no-op on non-web) |
| Back button | `PopScope` in `AppShell`: detail → `parentRouteOf(location)`, sub-page → `/`, Home → exit (double-press «اضغط مرة أخرى للخروج» snackbar) |
| Share | existing share link on detail pages → the Android share sheet through `share_plus` **only if** the size budget allows (small native code); otherwise «نسخ الرابط» + snackbar (current web behaviour). Decision recorded in ADR-058 |
| Offline | Firestore offline persistence + bundled seed (already). Verify airplane-mode start shows cached content |
| Splash + icon | existing `LaunchTheme` + adaptive icon from `tool/gen_branding.sh`; Android 12+ splash API uses `windowSplashScreenBackground` `#FBF3E4` + seal (`values-v31/styles.xml`) |
| Dark mode | follows the **site theme** (occasion palettes incl. dark Holy Week), not the system dark mode — same as the web; ADR-058 records it. `values-night` launch theme uses the cream background to avoid a dark flash |
| Update prompt | the APK is built with `--dart-define=APP_BUILD=<pubspec build number>` (CI reads it from `pubspec.yaml`); `AppConfig.appBuild` (full integer, no ABI offset arithmetic — `package_info_plus`'s versionCode includes Flutter's per-ABI offset and would be ambiguous above 999, CodeRabbit) < `installApkBuild` (already in the streamed `settings/features`, so the check costs nothing) → fetch the **version manifest** (§3.3) → banner «تحديث متاح — الإصدار ١٫٢٫٠ (١٨٫٤ م.ب)» → «تحديث الآن» runs the **in-app update** (§3.3). Dismiss per version; no redirect to the browser or to a releases page |
| Install banner | hidden (`!kIsWeb`) |

### 3.2 Local notifications
| Sub-feature | Detail |
|---|---|
| Permission explainer | the PR A page; Android 13+ `POST_NOTIFICATIONS` requested via `flutter_local_notifications` `requestNotificationsPermission()` only after the tap |
| Blocked state | Android: «الإعدادات ← التطبيقات ← كنيسة مكسيموس ودوماديوس ← الإشعارات ← سماح» + button that opens the app's notification settings (`AppSettings`-style intent via the plugin's `openNotificationSettings` / `android.settings.APP_NOTIFICATION_SETTINGS`) |
| Per-type toggles | only admin-offered `pushTypes`; local types on Android (`verse_daily`, `katameros_daily`, `feasts`, `reminders`) drive the planner, remote types (`announcements`, `seasons`) drive FCM topic subscription (PR C) — the page groups them «على هاتفك» / «من الكنيسة عبر الإنترنت» |
| Times | verse time (admin default 07:00), Katameros time (admin default 06:30), feasts (07:30); the user may override verse / Katameros within the page («وقت آية اليوم», «وقت القراءات»). Reminder leads are chosen per reminder (§3.4) |
| Quiet hours | user «ساعات الهدوء» from–to (default 22:00–07:00, can switch off): verse / Katameros / feasts inside the window move to its end; **user reminders ring normally** by default (the user asked for them; README §8 #18) unless «التذكيرات تحترم ساعات الهدوء» is on (then shown silently) |
| Test notification + diagnostics | «جرّب إشعارًا» → `show()` now; «اختبار بعد دقيقتين» schedules a test alarm with the **same mode** as reminders (exact if allowed) and asks on the next open «هل وصلك الإشعار؟»; «افحص الإشعارات» runs the diagnostic check (§3.6) |
| Inbox | «سجل الإشعارات»: the last 30 *delivered* items = planned items whose time has passed (the plan is stored) + FCM pushes received (PR C) + fired reminders; stored in `shared_preferences`; tapping opens the link / reading |
| Deep link | payload `link` → `router.go(safeNotificationLink(link))`; verse / Katameros payload `{type, date}` → `/readings/<date>?tab=verse|katameros`; app started from a notification → `getNotificationAppLaunchDetails()` → initial location; deleted page → existing 404 with «الرجوع للرئيسية»; switched-off section → FeatureGate «غير متاح» |
| Unsubscribe all | cancels all pending alarms (incl. reminders, which stay in «تذكيراتي» as paused) + clears prefs (PR C: also unsubscribes the FCM topics) |
| Re-sync (reschedule) | re-plan on: app start / **app open**, resume (`AppLifecycleState.resumed`), prefs or reminder change, `settings/features` / liturgies / meetings / seasons stream change (admin edits), date or time-zone change (resume + `DateTime.now().timeZoneOffset` compare), **device reboot** (plugin's `ScheduledNotificationBootReceiver` + `RECEIVE_BOOT_COMPLETED` restores alarms; additionally a one-off `workmanager` task on boot re-plans from the snapshot), app update (`MY_PACKAGE_REPLACED`) |
| Planning window | **daily types (verse, Katameros, feasts): rolling ~9 days** (owner 19:31) — refreshed on every app open / resume and by the background task **when fewer than 4 planned days remain**; **reminders:** every reminder the user set up to 60 days ahead (recurring «كل مرة» reminders: next 4 occurrences). At most **80 pending** alarms (Android allows ~500 per app): `cancelAllPendingNotifications()` (pending alarms only; notifications already shown stay) then schedule, reminders first, then earliest first (ids = stable hash `local:type:date:key`, a namespace disjoint from FCM display ids = hash(`nid`)). The planner's input type set is `NotifyType.values.where((t) => isLocalOwned(t, android))` — it can never schedule `announcements` or `seasons` (unit-tested) |
| Background replenishment | `workmanager` periodic task (**every 24 h**, inexact, network not required): re-plans from a **snapshot** of the planner inputs (verses, admin config, seasons, liturgies / meetings for reminders, `dayEvents`, cached readings) that each foreground plan writes to `shared_preferences` — so the ~9-day window keeps sliding even if the app stays closed (CodeRabbit on the plan PR). **Freshness:** the worker never opens Firestore (no background reads, no listener); admin changes reach the phone at the **next app open** (the foreground stream re-plans at once). If network is available the worker downloads the **missing** `/data/readings/<date>.json` files and `/data/today.json` (Hosting, no Firestore); offline it proceeds from the cache. The snapshot records `savedAt`; the page shows «آخر تحديث للمواعيد: …» and, when older than 7 days, «افتح التطبيق مع الإنترنت لتحديث المواعيد». A last-minute change that must reach everyone is sent as an event push (FCM, PR C). If an OEM blocks background work the plan still covers ~9 days; the page then says «افتح التطبيق مرة كل أسبوع على الأقل لتستمر الإشعارات» and the OEM guidance (§3.6) applies |
| Channels | one channel per type (`verse_daily`, `katameros_daily`, `feasts`, `reminders` (importance high), `seasons`, `announcements`) with Arabic names, so users can mute a channel in system settings (`seasons` / `announcements` are used by the FCM display path of PR C) |
| Exactness | **verse, Katameros, feasts: inexact** `AndroidScheduleMode.inexactAllowWhileIdle` (± ~10 min in Doze), no exact-alarm permission needed. **User reminders: exact** `exactAllowWhileIdle` when `canScheduleExactNotifications()` is true — manifest `USE_EXACT_ALARM` (Android 13+, granted at install) + `SCHEDULE_EXACT_ALARM` `maxSdkVersion="32"` (Android 12 / 12L, granted by default) — README §8 #16; **fallback** when exact is unavailable (permission revoked by the user / OEM): inexact scheduled **10 min earlier** and the sheet / «تذكيراتي» say «قد يصل التذكير قبل موعده بدقائق». Android 11 and older: exact allowed without permission |
| Battery optimisation | per-brand guidance screen + diagnostic check (§3.6) |
| Content sources | `verse_daily`: `dailyVerseFor` (bundled `assets/verses/daily_verses.json`, admin fixed / season verses from `settings/features`); `katameros_daily`: `/data/readings/<date>.json` (§3.5; title «قراءات اليوم — {feast}» with the Gospel reference); `feasts`: `copticFeastsOn` (computed) + `/data/today.json` titles when cached; `reminders`: the user's `ReminderStore` (PR A) reconciled with `occurrencesForDay` of liturgies / season programme services / meetings + `dayEvents` (§3.4). Texts from `notifyTypes` templates (PR C) or built-in defaults. **Not local:** `seasons` and `announcements` — FCM only (README §3.1) |

### 3.3 In-app update (download → verify → install)
| Sub-feature | Detail |
|---|---|
| Version manifest | static JSON `https://maximos-domadios-church.web.app/app/android/version.json` (≈ 500 B, `Cache-Control: no-cache`; always on our own Hosting, whatever the APK host — README §8 #6) generated by CI at release: `{"schema":1, "version":"1.2.0", "build":3, "minSupportedBuild":1, "publishedAt":"2027-01-10T08:00:00Z", "notesAr":"…", "notesEn":"…", "certSha256":"AB:CD:…", "apks":{"arm64-v8a":{"url":"…/church-portal-arm64.apk","sha256":"<64 hex>","size":18350000}, "armeabi-v7a":{…}}}`. Fetched only when `installApkBuild > APP_BUILD` (and on the update banner tap); `build` in the manifest must equal `installApkBuild`, else «جارٍ تجهيز التحديث، حاول لاحقًا» (the admin saved the number before the files went live) |
| ABI choice | `Build.SUPPORTED_ABIS[0]` via the platform channel → `arm64-v8a` or `armeabi-v7a` entry |
| Download inside the app | `dart:io` `HttpClient` streaming (follows redirects — needed for GitHub release URLs) into `getApplicationCacheDirectory()/updates/church-portal-<build>.apk.part`; progress bar with MB / % and «إلغاء»; resumes with `Range` after a dropped connection; Wi-Fi hint when the size is > 10 MB on mobile data; runs while the app is in the foreground (no extra background service — the screen stays on the update sheet; leaving the app pauses and the next tap resumes) |
| Integrity | streaming SHA-256 (`package:crypto`, already a dependency) + exact `size` against the manifest; mismatch → delete the file, «الملف تالف أو غير مكتمل — أعد المحاولة» (3 tries, then «تعذّر التحديث الآن»). The manifest is fetched over HTTPS from our own Hosting, so a compromised download host cannot pass the hash check; Android itself additionally rejects an APK not signed with the installed app's key |
| Signature pre-check | before launching the installer, the platform channel compares the downloaded APK's signing certificate with the installed app's (and with `certSha256`), branching by API level: **API ≥ 28** `getPackageArchiveInfo(path, GET_SIGNING_CERTIFICATES)` / `getPackageInfo(own, GET_SIGNING_CERTIFICATES)` → `signingInfo`; **API < 28** `GET_SIGNATURES` → `PackageInfo.signatures` for both (on some API < 28 devices `getPackageArchiveInfo` needs `applicationInfo.sourceDir`/`publicSourceDir` set to the path first); SHA-256 of the certificate bytes compared in both branches; mismatch (e.g. a debug-signed test build on the phone) → «هذا الإصدار لا يمكن تثبيته فوق النسخة الحالية — احذف التطبيق ثم ثبّته من الموقع» instead of Android's vague «لم يتم تثبيت التطبيق» |
| Unknown-apps permission | `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>`; `canRequestPackageInstalls()` false → explainer sheet (placeholder screenshot like PR A §3.3, ar/en: «اسمح لتطبيق الكنيسة بتثبيت التحديثات — مرة واحدة فقط») → `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` with `package:com.asafrachurch.church_portal` → on resume re-check → continue. This is the permission **for the church app itself** (not the browser) |
| Launch the installer | `Intent.ACTION_VIEW` with a `FileProvider` content URI (`${applicationId}.updates`, `res/xml/update_paths.xml` → `<cache-path name="updates" path="updates/"/>`), MIME `application/vnd.android.package-archive`, `FLAG_GRANT_READ_URI_PERMISSION` + `FLAG_ACTIVITY_NEW_TASK`. Android shows its own «هل تريد تحديث هذا التطبيق؟» → «تحديث»; the app restarts on the new version with its data (same key) |
| Implementation choice | a small **Kotlin platform channel** `church_portal/installer` in `MainActivity.kt` (~80 lines: `supportedAbi`, `canRequestInstalls`, `openUnknownSourcesSettings`, `apkCertMatches(path)`, `installApk(path)`) — no extra plugin, minimal size. Alternative: `open_filex` (FileProvider + install intent); check on pub.dev at implementation time that its version does not add unwanted permissions and record the choice in ADR-058 |
| Same signing key | upgrades work **only** with the same release key (LAUNCH §3). Debug-signed test installs must be uninstalled once (the pre-check explains it) |
| Clean-up | on start, delete `updates/*` when `APP_BUILD >= build` of the file; never keep more than one APK |
| Forced minimum | `APP_BUILD < minSupportedBuild` → the banner cannot be dismissed (app still usable); used only for a security fix |
| Fallback | after 3 failed downloads: «حمّل من موقع الكنيسة» opens the site's install banner (`/?install=android`), never a GitHub page |
| Privacy / Sentry | errors as `section: 'update'` with HTTP status / step only — no URLs with tokens, no file paths with user data |

### 3.4 تذكيراتي المحلية (User reminders «ذكّرني» — local on the APK, owner 19:31)
| Sub-feature | Detail |
|---|---|
| Set | PR A's `RemindMeButton` + sheet; the APK's `ReminderScheduler` schedules `start − lead` (Cairo time via `tz` `Africa/Cairo`) at once and the sheet says «سيصلك التذكير في موعده على هذا الهاتف» (or the fallback line when exact is unavailable). First reminder → notification permission flow (Android 13+) if not yet granted |
| Exact time | `exactAllowWhileIdle` (§3.2 «Exactness»), fallback inexact −10 min |
| Survives reboot / update | boot receiver + `MY_PACKAGE_REPLACED`; plus re-plan on next app open |
| Follows edits | on every data change / app open `reconcileReminders` (PR A): **moved** (same `eventKey`, new time — e.g. the admin changes the Holy Week service from 18:00 to 19:00) → rescheduled, inbox line «تغيّر موعد … إلى ٧:٠٠ م»; **removed / hidden** → alarm cancelled, «تذكيراتي» shows «أُلغي الحدث» and the inbox records it; **changed key** (a `day-` event whose title / time was edited) → matched by date + start ± 3 h + similar title; else «تغيّر الحدث — أعد ضبط التذكير» |
| Recurring «كل مرة» | the next 4 occurrences scheduled; refreshed with the window; respects season replacement (a regular mass replaced during Holy Week does not ring) |
| Notification | channel `reminders` (high importance), title «تذكير: صلاة الساعة السادسة» / body «بعد ساعة — ١٢:٠٠ م • الكنيسة الكبرى», tap → the item's detail page; action button «إيقاف هذا التذكير» (for «كل مرة» → stop all) |
| Dedupe | id `local:reminders:<eventKey>:<date>:<lead>`; an FCM event push carrying the same `eventKey` within ±60 min uses slot `event:<eventKey>` (README §3.1 rule 5): the later one replaces the earlier |
| «تذكيراتي» | PR A list, now live: next fire time, exact / approximate badge, cancel, change lead |

### 3.5 الآية والقطمارس — شاشة القراءة (Verse + Katameros, rolling ~9-day local window, reading screen)
| Sub-feature | Detail |
|---|---|
| Data file | `/data/readings/<YYYY-MM-DD>.json` per Cairo day, yesterday … +9 days, built by `tool/fetch_readings.js` (new; same Katameros API `https://api.katameros.app/readings/gregorian/<dd-mm-yyyy>?languageId=3|2` already used by `fetch_synaxarium.js`) and published by `synaxarium.yml` together with `/data/today.json`. Shape: `{"date","coptic","titleAr","titleEn","sections":[{"key":"vespers|matins|liturgy","titleAr","titleEn","readings":[{"kind":"psalm|gospel|pauline|catholic|acts|synaxarium","titleAr","titleEn","refAr","refEn","introAr","introEn","textAr","textEn","conclusionAr","conclusionEn"}]}],"source":"api.katameros.app","bibleAr":"Van Dyck","bibleEn":"NKJV|refs-only"}`. Size checked 6 Nov 2026 on the API: ≈ 32 KB ar + 22 KB en per day raw (≈ 12–15 KB gzip). English text per decision README §8 #17 (until decided: `refs-only` — references + introductions, no NKJV verse text). A day whose API call fails keeps the previously published file (same rule as `today.json`) |
| Hosting persistence | `tool/publish_hosting_file.js` gains a multi-file mode (one new version, many files) and `deploy.yml` fetches the current `/data/readings/*.json` into each build (like `today.json`), so a code deploy never drops them; `firebase.json` header `Cache-Control: public, max-age=3600` for `/data/readings/**` |
| Download on the phone | on app open / resume and in the background task: for each day of the window not in the cache (`getApplicationSupportDirectory()/readings/<date>.json`, or `shared_preferences` if small enough), GET the file once; never re-download a cached day (except yesterday/today if `fetchedAt` changed — `ETag`); prune days older than yesterday. ≈ 15 KB gzip per new day per device |
| Notifications | `verse_daily` at the verse time: title «آية اليوم», body = the verse (first ~120 chars) + reference; `katameros_daily` at the readings time: title «قراءات اليوم — {feast}», body «إنجيل القداس: {ref}»; payload `{"type","date"}`; inexact; quiet hours move them to the window's end; a day with no cached readings file at planning time schedules a generic «قراءات اليوم» notification that opens the screen (which fetches the file if online, else says «اتصل بالإنترنت لتحميل قراءات هذا اليوم») |
| Reading screen `/readings/<date>` | new route (web too, PR D links it from Home): tabs «الآية» / «القطمارس»; verse tab = full verse text + reference + «مشاركة»; Katameros tab = sections (عشية / باكر / قداس) with collapsible readings (intro, text, conclusion), Coptic date + feast header, font-size buttons (A− / A+, remembered), RTL / LTR, «المصدر: katameros.app» credit (+ NKJV notice if English text is shown); date switcher ‹ › within the cached window; **works offline** from the cache; 320 px × 200 % text |
| Window refresh | ~9 days of daily notifications are always planned when the app is opened at least weekly (§3.2 «Planning window»); the page shows «الإشعارات مجدولة حتى {date}» |
| Strictly local | never FCM: `topicFor` throws for both types; the client guard drops them (README §3.1) |

### 3.6 توفير البطارية والفحص (OEM battery savers — guidance + diagnostic check, owner 19:35)
| Sub-feature | Detail |
|---|---|
| Brand detection | `Build.MANUFACTURER` / `Build.BRAND` via the Kotlin channel → `xiaomi` (incl. Redmi / POCO, MIUI / HyperOS), `oppo` / `realme` / `oneplus` (ColorOS), `vivo` (Funtouch / OriginOS), `huawei` / `honor` (EMUI / MagicOS), `samsung` (One UI), `other` |
| Guidance screen «إذا لم تصلك الإشعارات» | `/notifications/battery`: steps for the detected brand first (others collapsible), Arabic + English, with «افتح الإعدادات» buttons that try known OEM activities and fall back to the app's details page (`ACTION_APPLICATION_DETAILS_SETTINGS`): **Xiaomi** — «التشغيل التلقائي» on (`com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity`), Battery saver → «بدون قيود», lock the app in Recents; **Oppo / Realme / OnePlus** — «السماح بالتشغيل التلقائي», «السماح بنشاط الخلفية», Battery → «بدون قيود» (`com.coloros.safecenter/.permission.startup.StartupAppListActivity`, variants); **Vivo** — «استهلاك طاقة مرتفع في الخلفية» on + Autostart (`com.vivo.permissionmanager/.activity.BgStartUpManagerActivity`); **Huawei / Honor** — App launch → «إدارة يدوية»: تشغيل تلقائي، تشغيل ثانوي، تشغيل في الخلفية (`com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity`); **Samsung** — Battery → «بدون قيود», remove from «التطبيقات في وضع السكون / السكون العميق», add to «التطبيقات التي لا تدخل في وضع السكون»; **all** — `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` (list; no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission). Activity names vary by OS version — each button is a try-list wrapped in try/catch; reference https://dontkillmyapp.com (verify per brand at implementation time). Screenshot placeholders like PR A §3.3 |
| Diagnostic check «افحص الإشعارات» | one screen with ✓ / ⚠ rows and a fix button each: notifications permission granted; each used channel enabled (`getNotificationChannels` importance ≠ none); exact alarms allowed (`canScheduleExactNotifications`) — needed only for reminders; battery optimisation ignored (`PowerManager.isIgnoringBatteryOptimizations`); pending alarm count + next three (`pendingNotificationRequests`); planned-until date; last background run (`workmanager` stamp; ⚠ if > 48 h → likely killed by the OEM → guidance screen); last FCM token refresh (PR C); readings cache days. «اختبار بعد دقيقتين» schedules a test with the reminders' mode, the user may close the app; on the next open «هل وصلك الإشعار التجريبي؟» نعم / لا → «لا» opens the brand guidance. Results never leave the phone (no Sentry content; only an anonymous breadcrumb `push.diag` with ✓/⚠ flags if the user taps «أرسل التقرير») |
| When shown | link on `/notifications`; banner on `/notifications` when the check finds ⚠ (e.g. background run > 48 h old) or the brand is in the list and the user has not opened the guide yet; never a pop-up on Home |

## ٤. الشاشات (Screens)

- `/notifications` on Android (PR A page + Android sections): status, per-type switches, «وقت آية اليوم» and «وقت
  القراءات» time pickers, «تذكيراتي» (live), «ساعات الهدوء» switch + two time pickers + «التذكيرات تحترم ساعات
  الهدوء», «جرّب إشعارًا» / «اختبار بعد دقيقتين», «افحص الإشعارات», «إذا لم تصلك الإشعارات», «سجل الإشعارات»,
  «إيقاف كل الإشعارات».
- `/readings/<date>` reading screen (verse / Katameros tabs, §3.5).
- `/notifications/battery` brand guidance + diagnostic screen (§3.6).
- Update banner (top of Home, palette `notice` roles): «تحديث متاح» + «تحميل» + ✕.
- Notification look: small icon = monochrome seal (`res/drawable/ic_stat_seal.xml`, white vector), colour
  `#6E1C1C` (`android:color` in channel / `color:` in `AndroidNotificationDetails` — native resource, not `lib/ui`),
  title + body, tap → link.

## ٥. نموذج البيانات + القواعد (Data model + rules)

No new Firestore keys or rules in this PR (reads `installApkBuild`, `installAndroidUrl`, `pushTypes` from PR A and,
once PR C lands, `notifyTypes`). Built-in defaults live in `lib/domain/push.dart` (`NotifyTypeConfig.defaults`:
verse 07:00, Katameros 06:30, feasts 07:30, reminder leads `[0, 15, 60, 1440]` default 60; seasons 08:00 on the
start day is the **sender's** default, PR C).

Device storage (`shared_preferences`): `church_portal_push` (same JSON as web), `church_portal_lang`,
`church_portal_notify_plan` (list of `{id,type,at,title,body,link}` for the inbox), `church_portal_inbox` (FCM),
`church_portal_reminders` (PR A store), `church_portal_diag` (last background run, test result, guide seen),
readings cache files `readings/<date>.json`,
`church_portal_seen_nids` (last 100 FCM `nid`s, PR C), `church_portal_update_dismissed` (build number),
`church_portal_update` (`{build, bytes, etag}` for resuming a partial download). Static file (Hosting, not
Firestore): `/app/android/version.json` (§3.3).

## ٦. التكلفة (Cost)

Firestore +0 (the planner reads the providers the app already streams — liturgies, meetings, seasons and
`settings/features` are already streamed by the schedule / Home pages; it does not start any listener that those pages
would not). Network: `/data/today.json` (already fetched by Home) + **each day's readings file once per device**
(≈ 12–15 KB gzip; ≈ 15 MB/day of Hosting transfer for 1,000 APK users, ~4 % of Spark's 360 MB/day), and — only when an
update exists — one ~500 B manifest fetch plus the APK download from the chosen host (README §8 #6: on Firebase
Hosting every APK download counts against the project's 10 GB/month transfer). CI: Android build ~8–12 min per run
on `ubuntu-latest` (free while the repo is public; on a private repo ≈ 10 billed minutes per build).

## ٧. الملفات (Files)

Create:
- `lib/domain/notify_plan.dart` — pure `List<PlannedNotification> planNotifications({required DateTime now, required PushPrefs prefs, required NotifyConfig config, required List<Reminder> reminders, required inputs…})` (Cairo time via `CairoTime`, quiet hours incl. the reminders rule, ~9-day window, reminder exact/inexact mode, ids).
- `lib/domain/readings.dart` — `DayReadings` model + parser (tolerant; unknown kinds kept generic); `lib/data/readings_store.dart` (+ stub for web: HTTP + browser cache) — cache, missing-day download, prune.
- `lib/ui/pages/readings_page.dart` — `/readings/<date>` (verse / Katameros tabs).
- `lib/ui/pages/notification_health_page.dart` — brand guidance + diagnostic check (§3.6); `lib/domain/oem_guide.dart` (pure: brand → steps + intent try-lists).
- `tool/fetch_readings.js` + `tool/fetch_readings.test.mjs` (API → per-day files, keep-previous on failure, `refs-only` English mode).
- `lib/data/local_notifications.dart` — `LocalNotifier` wrapper around `FlutterLocalNotificationsPlugin` (init, channels, permission, `zonedSchedule`, cancelAll, launch details), conditional import so web never links it (`local_notifications_stub.dart`).
- `lib/state/notify_providers.dart` — `notifyPlannerProvider` (listens to prefs / features / seasons / now-day, debounced 2 s, re-plans).
- `lib/ui/widgets/update_banner.dart` (banner + update sheet: progress, cancel, permission explainer, errors).
- `lib/data/app_updater.dart` (+ `app_updater_stub.dart` for web) — manifest fetch/parse, ABI pick, resumable
  download, SHA-256 + size check, platform-channel calls; `lib/domain/app_update.dart` (pure: `UpdateManifest`,
  `UpdateDecision decideUpdate({appBuild, installApkBuild, manifest, dismissedBuild})`).
- `android/app/src/main/kotlin/com/asafrachurch/church_portal/MainActivity.kt` (installer channel, §3.3; device
  channel: manufacturer / brand, `isIgnoringBatteryOptimizations`, open OEM settings try-list, §3.6),
  `android/app/src/main/res/xml/update_paths.xml`.
- `tool/make_apk_manifest.mjs` — CI: writes `version.json` (sizes, SHA-256, cert fingerprint via `apksigner verify
  --print-certs`, notes from `android/RELEASE_NOTES.md`).
- `lib/core/locale_storage_io.dart` (shared_preferences) — conditional import update in `locale_storage.dart`.
- `android/app/src/main/res/drawable/ic_stat_seal.xml`, `android/app/src/main/res/values-v31/styles.xml`.
- `android/key.properties.example` (documented, real file git-ignored); `android/RELEASE_NOTES.md` (Arabic notes shown on the GitHub Release, edited per release).
- `.github/workflows/android.yml` (§12).
- `test/notify_plan_test.dart`, `test/android_shell_test.dart`, `test/app_update_test.dart`, `test/readings_test.dart`,
  `test/reminder_scheduler_test.dart`, `test/oem_guide_test.dart`.
- `documentation/features/android-app.md` (rewrite), ADR-058.

Modify:
- `pubspec.yaml` (§8), `android/app/build.gradle.kts` (signing from env / `key.properties`, `isMinifyEnabled = true`, `isShrinkResources = true`, core-library desugaring), `android/app/src/main/AndroidManifest.xml` (permissions incl. `REQUEST_INSTALL_PACKAGES`, `RECEIVE_BOOT_COMPLETED`, `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM` with `android:maxSdkVersion="32"` (README §8 #16), `MY_PACKAGE_REPLACED` receiver, the `FileProvider`
`<provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.updates"
android:exported="false" android:grantUriPermissions="true">` + plugin receivers, `android:label` Arabic name kept), `android/app/proguard-rules.pro` (plugin keep rules if R8 strips them).
- `lib/router.dart` (`kIsWeb` admin guard, initial location from a launch notification), `lib/ui/widgets/app_shell.dart` (PopScope, update banner, drawer «الإشعارات»), `lib/ui/pages/notifications_page.dart` (Android sections), `lib/ui/pages/assistant_page.dart` / nav (open web `/ask` on Android), `lib/main.dart` (init `LocalNotifier` after first frame — never block start-up).
- `.gitignore` (`android/key.properties`, `*.jks`, `*.keystore`).
- `.github/workflows/synaxarium.yml` (also build + publish `/data/readings/*.json`), `.github/workflows/deploy.yml`
  (carry the readings files into every build), `tool/publish_hosting_file.js` (multi-file mode), `firebase.json`
  (readings cache header), `lib/router.dart` (`/readings/:date`, `/notifications/battery`), `lib/ui/widgets/today_widgets.dart`
  («اقرأ القراءات» on Home → `/readings/<today>`).
- Docs: memory bank 03/06/08/10/11, `documentation/features/android-app.md`, `documentation/operations.md` (release steps), `documentation/en/operations.md`.

## ٨. الحزم (Packages — checked on pub.dev 6 Nov 2026)

| Package | Version | Why | Notes |
|---|---|---|---|
| `flutter_local_notifications` | `^23.0.0` | scheduled local notifications | needs Flutter ≥ 3.44 (repo builds on stable 3.47); depends on `timezone ^0.11.0` (repo already `^0.11.2`); requires **core library desugaring** (`isCoreLibraryDesugaringEnabled = true`, `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`) |
| `workmanager` | `^0.10.10` (Flutter ≥ 3.38) | daily background re-plan (replenishment) | Android WorkManager; verify the version on pub.dev at implementation time |
| `package_info_plus` | `^10.2.2` | version name for display (the update check uses `APP_BUILD`) | optional |
| `shared_preferences` | `^2.5.6` | already a dependency | prefs, inbox, language |
| `crypto` | `^3.0.8` | already a dependency | SHA-256 of the downloaded APK |
| `path_provider` | verify on pub.dev | cache directory for the update file | only if not reachable through an existing dependency; or return the path from the platform channel instead (no package) |
| `open_filex` | optional, verify on pub.dev | install intent | only if the Kotlin channel is not used (§3.3) |
| `share_plus` | optional (`^12`) | system share sheet | add only if the APK budget allows |
| `firebase_messaging` | — | **PR C** (announcements) | not in this PR |

## ٩. خطوات التنفيذ (Step-by-step)

0. `tool/fetch_readings.js` + workflow publishing (per-day files, keep-previous) + `readings.dart` parser + reading
   screen (usable on the web too).
1. `planNotifications` (pure) + exhaustive tests first. Egypt observes summer time again (EEST, since 2023): always
   use `CairoTime` / `tz` `Africa/Cairo`, never a fixed +2 offset; tests cover a summer and a winter date and the
   switch nights.
2. Android build config: desugaring, minify/shrink, signing from env (falls back to debug when no secret), verify
   `flutter build apk --release --split-per-abi` locally or in CI.
3. `kIsWeb` admin guard; Android language store; PopScope back handling; assistant opens web `/ask`.
4. `LocalNotifier` + channels + permission flow; wire `/notifications` Android sections.
5. Planner provider: re-plan triggers (start, resume, prefs, features, day change); boot receiver; inputs snapshot +
   `workmanager` daily replenishment (test: closed app for 3 simulated days still has a full ~9-day window).
6. Inbox, test notification, quiet hours, unsubscribe all.
6b. `ReminderScheduler` (exact / fallback, reconcile on data change, boot / package-replaced, notification action).
6c. Readings download + verse / Katameros notifications (rolling ~9 days, refresh when < 4 days) + deep link to
    `/readings/<date>`.
6d. OEM guidance screen + diagnostic check (Kotlin device channel, try-lists).
7. Update banner (`installApkBuild`) + in-app update (§3.3): manifest, download with progress, SHA-256, signature
   pre-check, unknown-apps permission flow, FileProvider install intent, clean-up.
8. `android.yml` workflow: APK artifacts on PRs, signed release on tag, manifest generation, publish to the chosen
   download host (§12).
9. Docs + ADR-058; size report (APK per ABI) in the PR body.
10. Real-device pass (§11) on at least: Android 14/15 Samsung, Android 13 Xiaomi/Redmi, Android 10 or 11 low-end
    (armeabi-v7a), Android 8.1 (minSdk check: Flutter default `minSdk 21+`; plugin needs ≥ 21).

## ١٠. الاختبارات (Tests)

- `notify_plan_test.dart`: verse at 07:00 and Katameros at 06:30 Cairo for a **9-day window**; refresh triggered when
  < 4 days remain; quiet hours move 06:30 → 07:00 for daily types while a user reminder at 06:00 **rings** (default)
  and is silent with the switch on; reminder 60 min before a Holy Week service (season replaces the regular
  schedule) and before a `dayEvents` item; «كل مرة» on a Sunday liturgy → next 4 occurrences, none on a replaced day;
  exact mode when allowed, inexact −10 min otherwise; moved event → rescheduled; removed → cancelled + inbox note;
  **no season-start or announcement item** (remote-owned); feasts around Nativity (29 Kiahk) and Pascha; offered-types
  filter; ≤ 80 items, reminders first; stable ids; payload `{type, date}` for verse / Katameros; templates ar/en;
  past times skipped; DST switch nights.
- `readings_test.dart`: parse a real API-shaped fixture (ar + en), `refs-only` mode, missing day → generic
  notification + fetch on open, cache prune, offline open shows cached text.
- `oem_guide_test.dart`: brand mapping (Redmi → xiaomi, realme → oppo, honor → huawei), try-list fallback to app
  details; diagnostic rows from fake device states (permission off, channel off, exact denied, battery optimised,
  background stale > 48 h).
- Shell: `/admin` is not a route when `kIsWeb` is false (test via injectable `isWeb` param of the router builder);
  back-button mapping (`parentRouteOf`); update banner shown only when `installApkBuild` > local build;
  language persists through the IO store (fake).
- Planner: never emits `announcements` or `seasons` items, whatever the prefs.
- `app_update_test.dart` (fake HTTP + fake channel): manifest parse / schema mismatch / `build` ≠ `installApkBuild`;
  ABI pick; progress events; resume after a cut (Range); wrong SHA-256 or size → file deleted + error; cert
  mismatch → uninstall-first message; permission false → explainer → settings → resume → install called once;
  `minSupportedBuild` → non-dismissable; clean-up of old files; no URL of a releases page is ever launched.
- Widget: Android `/notifications` sections render, toggles call the planner (fake `LocalNotifier`), permission
  requested only after tap.

## ١١. اختبار يدوي (Manual QA — real devices)

| # | Scenario | Expected |
|---|---|---|
| 1 | Download APK from the banner in Chrome, install (unknown sources flow) | installs; icon + Arabic name; splash cream + seal |
| 2 | First open offline (airplane mode) | seed/cached content, no crash |
| 3 | Notifications page → enable verse at now+2 min | system permission dialog (Android 13+), notification arrives within ~10 min; tap opens Home verse |
| 4 | Quiet hours covering now+2 min | arrives at quiet end |
| 5 | Reboot phone | pending notifications still arrive |
| 6 | Kill app from recents for 24 h | daily verse still arrives |
| 7 | Change language EN → kill → reopen | still EN; notifications EN after re-plan |
| 8 | Admin changes a `dayEvents` item time (web) → open app | reminder re-planned |
| 9 | Back button on detail page / sub-page / Home | parent / Home / exit (double press) |
| 10 | Publish build N+1 (`installApkBuild`) | «تحديث متاح» → «تحديث الآن» → in-app progress → (first time) «السماح بتثبيت التحديثات» for the church app → Android's update dialog → app restarts on N+1 with data kept (same key!) |
| 10b | Turn Wi-Fi off mid-download, then on | resumes from where it stopped |
| 10c | Serve a manifest with a wrong SHA-256 (test channel) | «الملف تالف…», file deleted, nothing installed |
| 10d | Debug-signed build installed, release update offered | uninstall-first message, no Android error |
| 11 | Deleted custom page link in the inbox | 404 «الرجوع للرئيسية» |
| 12 | Themes (Golden hour, Holy Week dark) | readable; status bar contrast |
| 13 | 320-px-class phone (e.g. small Android Go) + largest font | no overflow |
| 14 | Xiaomi (HyperOS) with battery saver | diagnostic shows ⚠ background stale; guidance opens Autostart; after «بدون قيود» + Autostart, verse and a test reminder arrive on time |
| 15 | Oppo / Realme, Vivo, Huawei / Honor, Samsung | each guidance button opens the right screen or falls back to app details; texts match the phone (note differences for the guide) |
| 16 | Set «ذكّرني قبل ١٥ دقيقة» for a service at now+20 min, reboot the phone | rings at the exact minute (Android 13+: `USE_EXACT_ALARM`) |
| 17 | Revoke «المنبّهات والتذكيرات» for the app (Android 14 settings) | «تذكيراتي» shows «تقريبي»; reminder arrives ≤ 10 min early; diagnostic shows ⚠ exact alarms |
| 18 | Admin moves the service by 1 h / hides it → open the app | reminder moved / cancelled with the note |
| 19 | Tap the Katameros notification in airplane mode | full readings of that day from the cache |
| 20 | Don't open the app for 8 days (background allowed) | verse / Katameros keep arriving; window refreshed by the worker |

## ١٢. CI (`.github/workflows/android.yml`)

```yaml
name: Android APK
on:
  pull_request: { paths: ['lib/**','android/**','pubspec.*','assets/**','.github/workflows/android.yml'] }
  push: { tags: ['apk-v*'] }
  workflow_dispatch: {}
jobs:
  apk:
    runs-on: ubuntu-latest
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - name: Keystore (release only)
        if: startsWith(github.ref, 'refs/tags/apk-v')
        env: { KS: '${{ secrets.ANDROID_KEYSTORE_BASE64 }}' }
        run: echo "$KS" | base64 -d > "$RUNNER_TEMP/release.jks"
      - name: Build split APKs
        env:
          ANDROID_KEYSTORE_PATH: ${{ startsWith(github.ref, 'refs/tags/apk-v') && format('{0}/release.jks', runner.temp) || '' }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: |
          APP_VERSION=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
          BUILD=${APP_VERSION#*+}
          flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
            --dart-define=APP_BUILD=$BUILD --obfuscate --split-debug-info=build/symbols \
            --dart-define=SENTRY_ENVIRONMENT=${{ startsWith(github.ref, 'refs/tags/') && 'production' || 'preview' }} \
            --dart-define=GIT_SHA=$GITHUB_SHA --dart-define=APP_VERSION=$APP_VERSION
          ls -l build/app/outputs/flutter-apk/
      - name: APK size budget (fails before upload / release)
        run: |
          check() { f=build/app/outputs/flutter-apk/$1; max=$2; sz=$(stat -c %s "$f"); echo "$1: $sz B (max $max)"; [ "$sz" -le "$max" ] || { echo "::error::$1 over budget"; exit 1; }; }
          check app-arm64-v8a-release.apk ${{ vars.APK_ARM64_MAX || 20971520 }}
          check app-armeabi-v7a-release.apk ${{ vars.APK_ARM32_MAX || 18874368 }}
      - run: rm -f "$RUNNER_TEMP/release.jks"
        if: always()
      - uses: actions/upload-artifact@v5
        with: { name: apk, path: build/app/outputs/flutter-apk/*.apk, retention-days: 14 }
      - name: GitHub Release (tags only)
        if: startsWith(github.ref, 'refs/tags/apk-v')
        env: { GH_TOKEN: '${{ github.token }}' }
        run: |
          cd build/app/outputs/flutter-apk
          mv app-arm64-v8a-release.apk church-portal-arm64.apk
          mv app-armeabi-v7a-release.apk church-portal-arm32.apk
          node "$GITHUB_WORKSPACE/tool/make_apk_manifest.mjs" --base-url "${{ vars.APK_BASE_URL }}" \
            church-portal-arm64.apk church-portal-arm32.apk > version.json
          gh release create "$GITHUB_REF_NAME" church-portal-arm64.apk church-portal-arm32.apk version.json \
            --title "تطبيق الكنيسة $GITHUB_REF_NAME" --notes-file "$GITHUB_WORKSPACE/android/RELEASE_NOTES.md" --latest
      # Publish for the public (README §8 #6). The release above is only the canonical archive: it works even if the
      # repo is private (deploy.yml can read it with GITHUB_TOKEN), but private release assets are NOT downloadable
      # by the public.
      - name: Mirror to the public releases repo (APK_HOST=releases-repo)
        if: startsWith(github.ref, 'refs/tags/apk-v') && vars.APK_HOST == 'releases-repo'
        env: { GH_TOKEN: '${{ secrets.RELEASES_REPO_TOKEN }}' }    # fine-grained, that repo only, Contents: write
        run: |
          cd build/app/outputs/flutter-apk
          gh release create "$GITHUB_REF_NAME" church-portal-arm64.apk church-portal-arm32.apk \
            -R Kerollosmm/church-portal-apk --title "تطبيق الكنيسة $GITHUB_REF_NAME" --notes-file "$GITHUB_WORKSPACE/android/RELEASE_NOTES.md" --latest
    permissions: { contents: write }

  # Hosting writes are serialised with deploy.yml / synaxarium.yml (same group, never cancelled mid-release).
  publish-hosting:
    needs: apk
    if: startsWith(github.ref, 'refs/tags/apk-v')
    runs-on: ubuntu-latest
    timeout-minutes: 20
    concurrency: { group: hosting-live, cancel-in-progress: false }
    permissions: { contents: read }
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with: { node-version: 22 }
      - run: npm install --no-audit --no-fund      # google-auth-library for publish_hosting_file.js (clean runner)
        working-directory: tool
      - name: Fetch the release files
        env: { GH_TOKEN: '${{ github.token }}' }
        run: gh release download "$GITHUB_REF_NAME" -D rel -p 'version.json' -p 'church-portal-*.apk'
      - name: Publish manifest (+ APKs when hosted on Firebase) to Hosting
        env: { SA: '${{ secrets.FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL }}' }
        run: |
          printf '%s' "$SA" > "$RUNNER_TEMP/sa.json"; export GOOGLE_APPLICATION_CREDENTIALS="$RUNNER_TEMP/sa.json"
          cd rel
          if [ "${{ vars.APK_HOST }}" = "firebase" ]; then
            node "$GITHUB_WORKSPACE/tool/publish_hosting_file.js" church-portal-arm64.apk /app/android/church-portal-arm64.apk
            node "$GITHUB_WORKSPACE/tool/publish_hosting_file.js" church-portal-arm32.apk /app/android/church-portal-arm32.apk
          fi
          node "$GITHUB_WORKSPACE/tool/publish_hosting_file.js" version.json /app/android/version.json   # last: switch-over
      - if: always()
        run: rm -f "$RUNNER_TEMP/sa.json"
```
- `build.gradle.kts` reads `ANDROID_KEYSTORE_PATH` etc. from env (or `android/key.properties` locally); empty →
  debug signing (PR / preview builds).
- Repo variables: `APK_HOST` = `firebase` | `releases-repo` | `this-repo` (README §8 #6) and `APK_BASE_URL` = the
  public folder the manifest points at: `https://maximos-domadios-church.web.app/app/android/` (firebase),
  `https://github.com/Kerollosmm/church-portal-apk/releases/latest/download/` (releases-repo) or
  `https://github.com/Kerollosmm/church-portal/releases/latest/download/` (this-repo — **only while this repo is
  public**). For the two GitHub hosts the manifest's URLs use `releases/download/<tag>/…` (not `latest`) so a hash
  always matches its file; on Firebase the fixed `/app/android/*.apk` files are replaced first and the manifest
  last.
- `/admin` APK link = `<APK_BASE_URL>church-portal-arm64.apk` (and `…arm32.apk`).
- **Hosting persistence:** `tool/publish_hosting_file.js` (ADR-040) clones the live version, so the next normal
  `deploy.yml` deploy would drop `/app/android/*`. `deploy.yml` therefore gains a step that downloads the latest
  `apk-v*` release's `version.json` (and, when `APK_HOST=firebase`, the two APKs) with `gh release download`
  (`GITHUB_TOKEN`, works on a private repo too) into `build/web/app/android/` before `firebase deploy`, plus a
  `firebase.json` header `Cache-Control: no-cache` for `/app/android/version.json` and
  `Content-Type: application/vnd.android.package-archive` + `Content-Disposition: attachment` for `*.apk`.
- Sentry: upload Dart symbols (`sentry-dart-plugin`) optional later; obfuscation map kept as artifact.

## ١٣. التوثيق (Docs / ADR)

ADR-058: APK host per README §8 #6 with the version manifest always on our Hosting, split-per-abi arm64 + arm32
(no x86), local-only types on Android (verse, Katameros, feasts with inexact alarms in a rolling ~9-day window; user
reminders with exact alarms via `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` ≤ 32 and an inexact fallback), per-day
readings JSON on Hosting + offline reading screen, OEM guidance + diagnostic check, admin compiled out, assistant via the web, dark mode = site theme, **in-app update** (manifest +
SHA-256 + signature pre-check + `REQUEST_INSTALL_PACKAGES` + FileProvider installer intent), debug-signed until the
keystore exists.

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| **Lost keystore** → no updates possible (users must uninstall) | two offline backups + password manager (LAUNCH §3) |
| Debug-signed early installs can't upgrade to release-signed | publish to users only release-signed builds; debug builds are for testers |
| OEM battery killers delay or drop alarms (Xiaomi, Oppo, Vivo, Huawei, Samsung) | per-brand guidance + diagnostic check (§3.6); exact alarms only for reminders; re-plan on every open and on boot; the worker's stamp reveals a killed app; FCM not used for local types |
| `USE_EXACT_ALARM` would be rejected on Google Play (alarm / calendar apps only) | sideloaded APK only (decision #1); if the app ever goes to Play, switch to `SCHEDULE_EXACT_ALARM` with the user grant flow (README §8 #16) |
| NKJV licence for English readings | `refs-only` until README §8 #17 is decided |
| Readings files dropped by a code deploy / API outage | `deploy.yml` carries them; keep-previous per day; app shows cached days and a generic notification |
| Play Protect warns about an unknown app | normal for sideloading; PR A visual guide; signing with the same key builds reputation |
| `REQUEST_INSTALL_PACKAGES` looks sensitive to Play Protect / users | used only for self-update, explained in the sheet; no other install source; listed in the privacy text; the app never installs anything but its own signed update |
| APK downloads take the **whole site** offline (Firebase Hosting on Spark: 10 GB/month transfer for the project; past it, after a short grace period, sites are disabled until the next month — https://firebase.google.com/docs/hosting/usage-quotas-pricing) | README §8 #6: prefer a public releases host; on Firebase watch Hosting usage weekly (LAUNCH §11), keep APKs small (PR E), and switch `APK_HOST` before the monthly total nears ~7 GB |
| Update installs fail after a key change | never change the key; signature pre-check explains uninstall-first for test builds |
| Google Android developer verification (4 countries since 30 Sep 2026, global 2027) | LAUNCH §8: register in the Android Developer Console and register the package with the release-signed APK before it applies in Egypt |
| APK size > 25 MB | budget in PR E: arm64 ≤ 20 MB; remove `share_plus` if needed; `--obfuscate`; R8 |
| Plan runs out if the app is not opened for ~9 days **and** the OEM blocks background work | daily `workmanager` replenishment from the snapshot; boot + resume re-plan; diagnostic ⚠ + guidance; FCM event pushes still arrive (PR C); in-app note |

## ١٥. ما يفعله المالك (Owner steps — click by click)

1. **Create the keystore** (once, on your own computer with Java/Android Studio installed):
   ```bash
   keytool -genkeypair -v -keystore church-portal-release.jks -storetype JKS -keyalg RSA -keysize 4096 \
     -validity 10000 -alias church-portal
   ```
   Choose a strong password (store password = key password is fine). Name: الكنيسة / Organisation: Church of
   Sts Maximus & Domadius / Country: EG.
2. **Back it up now**: copy `church-portal-release.jks` + the password to (a) a USB stick kept at the church office,
   (b) your password manager (as an attachment) or an encrypted zip in your Google Drive. **If it is lost, the app
   can never be updated.**
3. `base64 -w0 church-portal-release.jks > ks.txt` (Windows PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("church-portal-release.jks")) > ks.txt`).
4. GitHub → repo **Kerollosmm/church-portal** → **Settings** → **Secrets and variables** → **Actions** → **New
   repository secret**, four times:
   - `ANDROID_KEYSTORE_BASE64` = content of `ks.txt`
   - `ANDROID_KEYSTORE_PASSWORD` = the store password
   - `ANDROID_KEY_ALIAS` = `church-portal`
   - `ANDROID_KEY_PASSWORD` = the key password
   Then delete `ks.txt`.
5. (Optional, for the assistant via App Check later) `keytool -list -v -keystore church-portal-release.jks -alias
   church-portal` → copy SHA-256 → Firebase console → ⚙ Project settings → Your apps → Android → **Add
   fingerprint**.
6. **Choose the download host** (README §8 #6) and set repo variables `APK_HOST` + `APK_BASE_URL` (GitHub →
   Settings → Secrets and variables → Actions → Variables). For `releases-repo`: create the **public** repo
   `Kerollosmm/church-portal-apk` (README only), then a fine-grained token for **that repo only**, Contents: Read
   and write → secret `RELEASES_REPO_TOKEN`.
7. **First release**: bump `version:` in `pubspec.yaml` (e.g. `1.1.0+2`) in a PR, merge, then GitHub → **Releases**
   → **Draft a new release** → tag `apk-v1.1.0` → **Publish** (or `git tag apk-v1.1.0 && git push origin
   apk-v1.1.0`). The workflow attaches the two APKs + `version.json` and publishes them to the chosen host.
8. Open `https://maximos-domadios-church.web.app/app/android/version.json` — it shows the new build and hashes.
9. `/admin` → «التطبيق والإشعارات»: رابط APK = `<APK_BASE_URL>church-portal-arm64.apk`; رابط الهواتف القديمة =
   `…arm32.apk`; الإصدار `1.1.0`; رقم البناء `2` (**save this last** — it is what makes installed apps offer the
   update); الحجم (MB).
