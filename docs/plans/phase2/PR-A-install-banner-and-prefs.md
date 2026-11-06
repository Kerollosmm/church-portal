# PR A — شريط تثبيت التطبيق + صفحة تفضيلات الإشعارات (Install banner + notification preferences)

| | |
|---|---|
| Branch → base | `feat/p2a-install-prefs` → `docs/phase2-plans` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-057** |
| Depends on | nothing (first code PR of Phase 2) |
| Owner console work | none |
| Live effect after merge | the install banner appears on phones (admin switch `installPrompt`, default on); everything about notifications stays **hidden** (`push` default off) |

## ١. الهدف (Goal)

1. Phones visiting the site get a small, dismissible card offering the app: **Android → download the APK** (or the
   browser's own install), **iPhone/iPad → step-by-step "Add to Home Screen"**. Desktop and already-installed
   visitors never see it.
2. Lay the **notification foundation** used by PRs B–D: the type model (6 types incl. Katameros and user reminders),
   the preferences page with its complete UX, the **«ذكّرني» button + lead-time sheet + «تذكيراتي» list** (stored on
   the device; delivery is wired in PR B for the APK and PR D for the web), and the admin switches — all behind `settings/features.push` (default **off**), so nothing about notifications is
   visible on the live site until the owner turns it on after PR C/D.

## ٢. قصص المستخدم (User stories)

- كزائر على Android أرى «حمّل تطبيق الكنيسة» مع رقم الإصدار والحجم، وبضغطة واحدة يبدأ التحميل، ويظهر لي دليل مصوّر
  خطوة بخطوة يشرح رسالة «قد يكون هذا الملف ضارًا» وتحذير Google Play Protect وإذن «تثبيت التطبيقات غير المعروفة»
  بأمان.
- كزائر على iPhone أرى «أضف الموقع إلى الشاشة الرئيسية» وعند الضغط تظهر ٣ خطوات بالأيقونات الحقيقية لـ Safari.
- إذا ضغطت ✕ لا يظهر الشريط مرة أخرى قبل المدة التي حددها المشرف (افتراضي ٣٠ يومًا)؛ «ذكّرني لاحقًا» يخفيه ٣ أيام.
- إذا كنت أفتح الموقع من التطبيق المثبت (PWA) أو من تطبيق Android لا أرى الشريط أبدًا.
- كمشرف أغيّر النصوص والروابط ورقم الإصدار والحجم والمدد من `/admin` بدون نشر جديد.
- (after `push` is on) as a visitor I open «الإشعارات», read what each type means, choose the types I want, and only
  then does the browser ask for permission. If I blocked it, I see how to re-enable it on my phone/browser.
- (after `push` is on) على كارت أي قداس أو خدمة أو مناسبة (مثل صلاة الساعة السادسة يوم الجمعة العظيمة) أضغط
  «ذكّرني»، أختار «قبل ساعة»، وأرى التذكير في «تذكيراتي» حيث أستطيع تغييره أو إلغاءه.

## ٣. الخصائص الفرعية (Complete sub-features)

### 3.1 Install banner
| Sub-feature | Detail |
|---|---|
| OS detection | pure Dart `detectInstallOs(userAgent, platform, maxTouchPoints)` → `android` / `ios` (iPhone, iPod, iPad, **iPadOS that reports "Macintosh" with touch points > 1**) / `desktop` / `other`. In-app browsers (Facebook `FBAN/FBAV`, Instagram, WhatsApp `WhatsApp/`) flagged `inAppBrowser` → the iOS steps say "open in Safari first", Android download still works |
| Already installed | hidden when `matchMedia('(display-mode: standalone)')`, `(display-mode: minimal-ui)`, `navigator.standalone == true`, on any non-web build (`!kIsWeb` = the APK) and on `/admin`. The `appinstalled` event hides the banner **for the current browser session only** (`sessionStorage`), never permanently — so after the user uninstalls the PWA, a later browser visit shows the banner again (CodeRabbit on the plan PR). **Stale flag in the same tab** (CodeRabbit round 1 follow-up: `sessionStorage` survives reloads of that tab): where `getInstalledRelatedApps()` exists, an empty result **clears** `church_portal_installed` and the banner shows again on that same tab; where it does not exist (Samsung Internet, Firefox, iOS Safari), the banner stays hidden in that tab until the tab is closed — a known, self-healing limitation (any new tab / later visit shows it), stated in ADR-057. Where supported (Chrome Android), `navigator.getInstalledRelatedApps()` with a `related_applications` entry of type `webapp` for our own manifest confirms a still-installed PWA; unsupported → rely on the dismiss memory |
| Android action | `installAndroidUrl` set → button «تحميل التطبيق (١٨٫٤ م.ب • إصدار ١٫١٫٠)» opens the URL (download); optional small link «هاتف قديم؟» → `installAndroidUrl32`. URL blank → if the browser fired `beforeinstallprompt` (captured early in `index.html`) the button calls `prompt()`; else a sheet with "⋮ → تثبيت التطبيق / إضافة إلى الشاشة الرئيسية" |
| After APK tap | the download starts **and** the **visual sideload guide** opens (§3.3): a step-by-step modal that explains the browser's «file might be harmful» bar, opening the file, allowing «install unknown apps» for the browser, the Google Play Protect prompt and how to turn the permission off again. Also reachable from a «طريقة التثبيت» link on the banner and from `/notifications` on Android browsers (same modal), so a user who closed it can reopen it |
| iPhone/iPad action | bottom sheet with 3 numbered steps using the real glyphs: 1 `Icons.ios_share` «اضغط زر المشاركة», 2 `Icons.add_box_outlined` «إضافة إلى الشاشة الرئيسية», 3 «إضافة», then «افتح الكنيسة من الأيقونة الجديدة». Note for iOS < 16.4 / non-Safari: «افتح الموقع في Safari». No screenshots (size). **The iOS banner and sheet never request notification permission and never touch `Notification` / `PushManager`** — on iOS the permission UI exists only inside the installed app (standalone, iOS 16.4+; PR D §3.1) |
| Dismiss ✕ | stores `church_portal_install = {"until": "<ISO date>"}` in localStorage = now + `installReshowDays`; 0 = never again (`until` = far future) |
| Remind later | «ذكّرني لاحقًا» = now + `installRemindDays` |
| Timing | shown after the first real content (`ContentReady`, ADR-038) + 4 s, never over the loading screen; bottom of the viewport, above the safe-area inset; max width 560 px centred; does **not** change the hero |
| Accessibility | `Semantics(liveRegion)`, 48 dp targets, focus order title → action → later → ✕, works at 320 px × 200 % text, RTL/LTR |
| Admin | all texts, URLs, version, build, size, days, on/off |

### 3.2 Notification preferences (behind `push`)
| Sub-feature | Detail |
|---|---|
| Type model | `NotifyType` (`announcements`, `verse_daily`, `katameros_daily`, `seasons`, `feasts`, `reminders`), ar/en labels + one-line descriptions, icons, and the **channel owner per platform** (README §3.1): `channelOf(type, platform)` → `local` for `verse_daily`, `katameros_daily`, `feasts` on the APK (none on the web — shown on Home), `local` for `reminders` on the APK and `remote` on the web, `remote` for `announcements`, `seasons` everywhere. `topicFor(type, lang, platform)` returns `web_<type>_<lang>` / `app_<type>_<lang>` **only for remote pairs with a fixed topic and throws `ArgumentError` otherwise** (`reminders` on the web uses `reminderTopic(eventKey, occurrence, lead, lang, {every})` → `web_rem_…`; on the APK it throws). `isLocalOwned(type, platform)` is the shared guard used by the Android handler (PR C) and mirrored in the SW (PR D). (`reminders` replaces the earlier blanket `occasions` type — owner 19:31) |
| Route `/notifications` | «الإشعارات» page; in the drawer and footer only when `push` is on. When off → the normal 404 (not indexable) |
| Explainer | before any browser prompt: what we send, how often, no personal data, «يمكنك الإيقاف في أي وقت» |
| Per-type toggles | only `pushTypes` offered by the admin, **filtered by platform**: web (browser / iPhone PWA) shows `announcements`, `seasons`, `reminders` with a muted line «آية اليوم وقراءات القطمارس والأعياد: في الصفحة الرئيسية» for the APK-only ones; the APK (PR B) shows all six; quiet default = all off; first opt-in pre-ticks `announcements` + `seasons` + `reminders` |
| Permission on tap only | `Notification.requestPermission()` only from the «تفعيل الإشعارات» button, never on load |
| States | `unsupported` (no `Notification`/`PushManager`/`serviceWorker`), `iosNeedsInstall` (iOS, not standalone: `display-mode: standalone` false and `navigator.standalone !== true` → install-first card + read-only type preview, **no enable button, no permission call**), `iosTooOld` (standalone but iOS < 16.4 → «حدّث iOS»), `inAppBrowser` (→ «افتح في Safari / Chrome»), `default`, `granted`, `denied` (blocked). Order of checks: in-app browser → iOS not standalone → iOS too old → unsupported → permission |
| Blocked state | how to re-enable: Chrome Android «🔒 → الأذونات → الإشعارات → سماح», iPhone «الإعدادات → الإشعارات → كنيسة مكسيموس ودوماديوس», desktop Chrome/Edge/Firefox/Safari one line each |
| Unsubscribe all | «إيقاف كل الإشعارات» → clears choices; PR D also deletes the FCM token and queues an unsubscribe |
| Storage | localStorage `church_portal_push` = `{"types":[…],"lang":"ar","quiet":{"from":"22:00","to":"07:00"},"updatedAt":…}`; nothing in Firestore |
| Web scaffold | `web/firebase-messaging-sw.js` (no fetch handler, own scope) and `web/push_client.js` (lazy, injected on tap) — present but only used by PR D; with no `pushVapidKey` the enable button explains "قريبًا" and stays disabled |
| «ذكّرني» button (scaffold) | `RemindMeButton(eventKey, occurrence, title, startsAt, recurring)` on liturgy / season-service / meeting cards, detail pages and today's events (`dayEvents`), shown only when `push` is on, `reminders` is offered and the source is in `reminderSources`; bell icon + «ذكّرني» (filled bell + chip «قبل ساعة» when set); 48 dp, `Semantics(label: 'ذكّرني بـ …')`. Hidden for occurrences already started |
| Lead-time sheet | bottom sheet: title + date/time of the occurrence; radio list from `reminderLeads` («في الموعد» / «قبل ١٥ دقيقة» / «قبل ساعة» / «قبل يوم»; labels generated for 5/10/30/120/180 too), default `reminderDefaultLead`; recurring item → segmented «هذه المرة فقط» / «كل مرة»; leads whose fire time is already past are disabled; platform line (filled in by PR B / PR D): APK «سيصلك التذكير في موعده بالضبط على هذا الهاتف»; web «يصل التذكير عبر الإنترنت وقد يتأخر حتى ٣٠ دقيقة تقريبًا» + «أضف إلى التقويم» (existing ADR-021 `.ics` action); «حفظ» / «إلغاء التذكير» |
| «تذكيراتي» | section on `/notifications` (and reachable from the chip): list sorted by next fire time — title, occurrence, lead, «كل مرة» badge, state («مجدول» / «انتهى» / «تغيّر الحدث — أعد ضبطه» / «أُلغي الحدث»); tap → the sheet; swipe / button «إلغاء»; «مسح المنتهية». Max 30 reminders per device (message when full) |
| Reminder storage | `ReminderStore` (device only): `church_portal_reminders` = `[{"eventKey","occurrence":"YYYY-MM-DD"\|null,"lead":60,"every":false,"title":{"ar","en"},"startsAt":ISO,"createdAt"}]` — localStorage on the web, `shared_preferences` on the APK; nothing in Firestore. Pure `reconcileReminders(stored, currentOccurrences, now)` → kept / moved (same key, new time) / changed (key missing, `day-` item edited) / removed / expired — used by PR B (reschedule) and PR D (topic clean-up) |
| Not in this PR | delivery of reminders (PR B local alarms / PR D web topics), quiet hours UI, test notification, inbox, reading screen → PR B (Android) / PR D (web) — they need a delivery path |

### 3.3 Android sideload guide (visual modal)
Opens right after the APK download starts (and from «طريقة التثبيت»). A `showModalBottomSheet` (full height on
phones, max width 560 px) with a `PageView` stepper: step dots, «التالي» / «السابق», «تم», swipe, RTL-aware order,
`Semantics` per step («الخطوة ٢ من ٥»), 48 dp targets, 320 px × 200 % text without overflow. Each step = a
**screenshot placeholder** (fixed 9:16 frame, 200 px tall on a 390 px phone, rounded, `outlineVariant` border, a
seal glyph + «صورة توضيحية» caption until the real image exists) + title + 1–3 short lines, Arabic and English from
`l10n.dart`. Images are optional static files `web/install-guide/android-<n>-<ar|en>.webp` (≤ 30 KB each, loaded
with `Image.network` **only when the modal opens** → +0 bytes on page load, not in `main.dart.js`, not in the APK);
if a file is missing or fails, the placeholder frame stays (no broken image). Real screenshots are taken by the
implementer on a Samsung (One UI) and a Pixel-style phone (Android 14/15), Arabic UI, cropped to the dialog,
personal data blurred, then committed (PR A or later) — wording on other brands varies, so the texts say «قد يختلف
الشكل حسب الهاتف».

| # | Placeholder (screenshot to take) | العربية | English |
|---|---|---|---|
| 1 | Chrome download bar «قد يكون هذا الملف ضارًا» with «تنزيل على أي حال» highlighted | **رسالة «قد يكون الملف ضارًا»**: يعرضها المتصفح لأي تطبيق من خارج متجر Play. تأكد أن العنوان في الأعلى هو `maximos-domadios-church.web.app` ثم اضغط «تنزيل على أي حال» | **"File might be harmful"**: the browser shows this for any app from outside the Play Store. Check that the address bar shows `maximos-domadios-church.web.app`, then tap "Download anyway" |
| 2 | Download-complete notification / Downloads list with the `.apk` | **افتح الملف**: من إشعار «اكتمل التنزيل» أو من «التنزيلات» اضغط على ملف تطبيق الكنيسة. حجمه **{size} م.ب** (يُعرض حجم الملف الذي اخترته: `installApkSizeMb` للرابط العادي أو `installApkSize32Mb` لرابط «هاتف قديم؟») | **Open the file** from the "Download complete" notification or Downloads; it is **{size} MB** (the size of the file you chose: `installApkSizeMb` for the normal link, `installApkSize32Mb` for the "older phone" link) |
| 3 | «لا يُسمح لهاتفك بتثبيت تطبيقات غير معروفة من هذا المصدر» → «الإعدادات»; then the «السماح من هذا المصدر» toggle | **اسمح مرة واحدة للتطبيق الذي فتح الملف**: اضغط «الإعدادات» ← فعّل «السماح من هذا المصدر» للتطبيق الظاهر في الصفحة — المتصفح (مثل Chrome) إذا فتحت الملف من إشعار التنزيل، أو «الملفات» / «ملفاتي» إذا فتحته من مدير الملفات ← ارجع | **Allow the app that opened the file, once**: tap "Settings" → turn on "Allow from this source" for the app shown on that page — the browser (e.g. Chrome) if you opened the file from the download notification, or Files / My Files if you opened it from a file manager → go back |
| 4 | Install dialog, then the Play Protect sheet («تطبيق غير آمن تم حظره» / «فحص التطبيق») with «مزيد من التفاصيل» → «التثبيت على أي حال» | **Google Play Protect**: قد يقترح فحص التطبيق — اسمح بالفحص. إذا قال إنه لا يعرف المطوّر: «مزيد من التفاصيل» ← «التثبيت على أي حال». هذا طبيعي لتطبيق من خارج المتجر | **Google Play Protect** may offer to scan the app — allow the scan. If it says the developer is unknown: "More details" → "Install anyway". Normal for an app from outside the store |
| 5 | App icon on the home screen + the «السماح من هذا المصدر» toggle switched off | **افتح التطبيق**، ثم (اختياري وأكثر أمانًا) ارجع إلى الإعدادات ← التطبيقات ← **نفس التطبيق الذي سمحت له في الخطوة ٣** (المتصفح أو مدير الملفات) ← «تثبيت التطبيقات غير المعروفة» وأوقف «السماح من هذا المصدر» | **Open the app**, then (optional, safer) go to Settings → Apps → **the same app you allowed in step 3** (browser or file manager) → "Install unknown apps" and switch "Allow from this source" off again |

Safety box at the bottom of every step («للأمان»): حمّل التطبيق من موقع الكنيسة فقط، لا من ملفات مرسلة على واتساب أو
فيسبوك · الكنيسة لا تطلب أبدًا إيقاف Play Protect بالكامل أو أي إذن آخر · رقم الإصدار والحجم على الزر يجب أن
يطابقا الملف. (Only download from the church site, never from forwarded files; the church never asks you to turn
Play Protect off entirely; version and size on the button must match the file.) The same texts are the canonical
copy in LAUNCH-AND-OPERATIONS §5.

## ٤. الشاشات (Screens)

- **Banner (Android)**: seal 40 px · title «تطبيق الكنيسة على هاتفك» · body · primary «تحميل التطبيق» + caption
  «الإصدار ١٫١٫٠ • ١٨٫٤ م.ب» · text button «لاحقًا» · ✕ (tooltip «إغلاق»).
- **Banner (iPhone)**: same; primary «طريقة الإضافة» → steps sheet.
- **Steps sheet (iPhone)**: 3 numbered rows with glyphs, «تم» button.
- **/notifications**: header (`CustomizablePageHeader`, page key `notifications`), explainer card, status card
  (granted / blocked / unsupported / install-first), type list (switch + label + description), «تذكيراتي», «إيقاف كل
  الإشعارات», privacy line.
- **«ذكّرني»** button on event cards + lead-time sheet (§3.2).
- **Admin `/admin` → «التطبيق والإشعارات»** (new destination, `Icons.install_mobile_outlined`): generic
  `ChurchInfoScreen` with `appSettingsDoc` (`DocDef('settings/features', …)`, writes only changed keys like
  `todaySettingsDoc`). Two groups: «شريط تثبيت التطبيق» and «الإشعارات (تجريبي)».

## ٥. نموذج البيانات + القواعد (Data model + rules)

New top-level keys in `settings/features` (see README §6 for the full contract): `installPrompt`,
`installTitleAr`, `installTitleEn`, `installBodyAr`, `installBodyEn`, `installAndroidUrl`, `installAndroidUrl32`,
`installApkVersion`, `installApkBuild`, `installApkSizeMb`, `installApkSize32Mb`, `installReshowDays`, `installRemindDays`, `push`,
`pushVapidKey`, `pushTypes`, `reminderLeads`, `reminderDefaultLead` (`reminderSources` and `notifyTypes` come in PR C).

Dart (`lib/domain/app_install.dart`, `lib/domain/push.dart`, pure):
```dart
class InstallSettings { bool enabled; String titleAr, titleEn, bodyAr, bodyEn, androidUrl, androidUrl32,
  apkVersion; int apkBuild; double apkSizeMb, apkSize32Mb; int reshowDays, remindDays; factory fromMap(Map m); }
class PushSettings { bool enabled; String vapidKey; List<NotifyType> offered; List<int> reminderLeads; int defaultLead;
  bool get webReady => enabled && vapidKey.isNotEmpty; }
class Reminder { String eventKey; String? occurrence; int lead; bool every; Map<String,String> title; DateTime startsAt; }
```
Both parsed in `FeatureSettings.fromMap` as `install` / `pushSettings` (never written by `toMap`, like `today`).

`firestore.rules` → `validFeatures`: add the 18 keys to `keysAllowed([...])` and two gates (only evaluated when
one of their keys changes, so the 1,000-expression budget of other saves is untouched):
```
&& (!changed.hasAny(['installPrompt','installTitleAr','installTitleEn','installBodyAr','installBodyEn',
     'installAndroidUrl','installAndroidUrl32','installApkVersion','installApkBuild','installApkSizeMb','installApkSize32Mb',
     'installReshowDays','installRemindDays'])
    || (optBool(d,'installPrompt') && str(d,'installTitleAr',120) && str(d,'installTitleEn',120)
        && str(d,'installBodyAr',300) && str(d,'installBodyEn',300)
        && optUrlOrPath(d,'installAndroidUrl',500) && optUrlOrPath(d,'installAndroidUrl32',500)
        && d.get('installApkVersion','').matches('^$|^[0-9]+([.][0-9]+){0,3}$')
        && optInt(d,'installApkBuild',0,999999) && optNumber(d,'installApkSizeMb',0,200) && optNumber(d,'installApkSize32Mb',0,200)
        && optInt(d,'installReshowDays',0,365) && optInt(d,'installRemindDays',1,60)))
&& (!changed.hasAny(['push','pushVapidKey','pushTypes','reminderLeads','reminderDefaultLead'])
    || (optBool(d,'push') && d.get('pushVapidKey','').matches('^$|^[A-Za-z0-9_-]{80,100}$')
        && optList(d,'pushTypes',6)
        && d.get('pushTypes',[]).hasOnly(['announcements','verse_daily','katameros_daily','seasons','feasts','reminders'])
        && d.get('pushTypes',[]).toSet().size() == d.get('pushTypes',[]).size()
        && optList(d,'reminderLeads',4)
        && d.get('reminderLeads',[]).hasOnly([0,5,10,15,30,60,120,180,1440])
        && d.get('reminderLeads',[]).toSet().size() == d.get('reminderLeads',[]).size()
        && (!('reminderDefaultLead' in d) || d.get('reminderLeads',[0,15,60,1440]).hasAny([d.reminderDefaultLead]))))
```
Also allow the page key `notifications` wherever `validPageHeaders` lists the customizable pages (the page header
override of `/notifications`), and add it to `CustomizablePages.all`.

Rules tests (`tool/rules_test/rules.test.mjs`): admin can set each key; stranger cannot; bad URL (`javascript:`),
version `1.x`, build −1, size 500, reshow 400, remind 0, VAPID with spaces, unknown type (incl. the retired
`occasions`), duplicate type, lead 7, 5 leads, default lead not in the list → denied;
an unrelated save (e.g. `heroMotion`) still passes with the worst-case page headers.

## ٦. التكلفة (Read / write cost)

+0 visitor reads (same `settings/features` stream), +0 writes (localStorage only), admin saves only. Network: the
banner adds no request; `push_client.js` (~3 KB) and the gstatic messaging module load only on the user's tap
(PR D).

## ٧. الملفات (Files)

Create:
- `lib/domain/app_install.dart` — `InstallSettings`, `InstallOs`, `detectInstallOs`, `InstallBannerDecision shouldShowInstallBanner({settings, os, standalone, installedEvent, dismissedUntil, now, path, isWeb})`, `InstallAction resolveInstallAction(...)` (`apk` / `pwaPrompt` / `androidSteps` / `iosSteps` / `none`).
- `lib/domain/push.dart` — `NotifyType` enum + labels/descriptions/icons keys, `PushSettings`, `PushPrefs` (encode/decode JSON, defaults, `firstOptInTypes`), `channelOf` / `isLocalOwned` / `topicFor(type, lang, platform)` / `reminderTopic(...)`, `PushPermissionState`, `safeNotificationLink(String)` (in-app path only, else `/`).
- `lib/domain/reminders.dart` — `Reminder`, `EventKey` (`eventKeyFor(...)`, shared with PR C's sender port), `reconcileReminders(...)`, `leadLabel(lead, lang)`; `lib/data/reminder_store.dart` (+ web / io storage via `install_env`).
- `lib/ui/widgets/remind_me.dart` — `RemindMeButton`, `showReminderSheet`, `MyRemindersSection`.
- `lib/core/install_env.dart` + `install_env_stub.dart` + `install_env_web.dart` — `userAgent`, `platform`, `maxTouchPoints`, `isStandalone`, `hasDeferredPrompt`, `Future<bool> promptInstall()`, `readJson/writeJson(key)` (localStorage, try/catch like `locale_storage_web.dart`).
- `lib/core/push_env.dart` + `push_env_stub.dart` + `push_env_web.dart` — `isSupported`, `permission`, `Future<String> requestPermission()`; (PR D adds token calls).
- `lib/ui/widgets/install_banner.dart` — `InstallBanner` (ConsumerStatefulWidget) + `showIosInstallSteps` / `showAndroidSteps` sheets.
- `lib/ui/widgets/apk_install_guide.dart` — `showApkInstallGuide(context)` (§3.3: stepper, placeholders, safety box).
- `web/install-guide/README.md` — file names, size limit and how to capture / blur the five screenshots (images
  themselves optional; placeholders until added).
- `lib/ui/pages/notifications_page.dart` — `NotificationsPage`.
- `web/firebase-messaging-sw.js` — scaffold (see PR D for the full file); `web/push_client.js` — scaffold.
- `test/install_banner_test.dart`, `test/push_prefs_test.dart`, `test/reminders_test.dart`.
- `documentation/features/install-and-notifications.md` (Arabic), ADR-057 in `docs/memory-bank/10-decisions-and-history.md`.

Modify:
- `web/index.html` — early inline script in `boot-prefs`: `window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); window.__installPrompt = e; })` and `appinstalled` → `sessionStorage church_portal_installed=1` (session only — see «Already installed»).
- `lib/domain/features.dart` — parse `install` / `pushSettings`; `Sections`? **no** (not a public section; gating by `push`).
- `lib/state/providers.dart` — `installSettingsProvider`, `pushSettingsProvider` (`featuresProvider.select`), `pushPrefsProvider` (Notifier backed by `install_env` storage).
- `lib/ui/widgets/app_shell.dart` — add `InstallBanner` in the outer `Stack` (bottom, `PositionedDirectional`), drawer entry «الإشعارات» when `push` on.
- `lib/ui/widgets/common.dart` — footer link «الإشعارات» when `push` on.
- `lib/router.dart` — `GoRoute('/notifications')` (404 when `push` off; `setDocumentRouteMeta(indexable: false)`).
- `lib/domain/features.dart` `CustomizablePages` — add `notifications` (page header override).
- `lib/ui/admin/admin_schema.dart` — `appSettingsDoc`; `lib/ui/admin/admin_page.dart` — destination `app` («التطبيق والإشعارات»).
- `lib/core/l10n.dart` — ~95 strings `[ar, en]` (incl. the 5 guide steps + safety box, iOS states, «ذكّرني» sheet,
  lead labels, «تذكيراتي» states, the web delay line).
- `lib/ui/widgets/cards.dart`, `lib/ui/pages/item_detail_page.dart`, `lib/ui/widgets/today_widgets.dart` — place
  `RemindMeButton` (behind `push` + offered `reminders`).
- `firestore.rules`, `tool/rules_test/rules.test.mjs`.
- `lib/domain/sitemap.dart` — `/notifications` **not** in the sitemap.
- Docs: `docs/memory-bank/03,04,05,06,07,10,11`, `documentation/README.md`, `documentation/features/pwa-and-caching.md`, `documentation/features/feature-toggles.md`, `documentation/en/features.md`.

## ٨. الحزم (Packages)

None. Uses `package:web` (already `^1.1.2`) and `dart:js_interop`.

## ٩. خطوات التنفيذ (Step-by-step)

1. Domain first: `app_install.dart`, `push.dart` + unit tests (OS matrix of ~20 real UA strings: Android Chrome,
   Samsung Internet, Firefox Android, iPhone Safari 15/16/17/18, iPad iPadOS desktop UA with touch, Facebook /
   Instagram / WhatsApp in-app, Windows, macOS, Linux, ChromeOS).
2. `FeatureSettings` parsing + tests (defaults, bad values clamp, unknown types dropped).
3. Rules + emulator tests (`cd tool/rules_test && npm test`).
4. Web env (`install_env_web.dart`, `push_env_web.dart`) + `index.html` early capture.
5. `InstallBanner` + sheets + `apk_install_guide.dart`; place in `AppShell`; widget tests with a fake env (inject via provider
   `installEnvProvider`).
6. `NotificationsPage` + route + nav/footer entries behind `push`; widget tests per permission state.
6b. Reminders: `reminders.dart` (event keys, `reconcileReminders`) + tests; `RemindMeButton`, sheet, «تذكيراتي»;
   widget tests (no delivery yet — a fake `ReminderScheduler` records calls; PR B / PR D implement it).
7. Admin `appSettingsDoc` + destination; admin widget test (fields render, save writes only changed keys).
8. `web/firebase-messaging-sw.js` + `web/push_client.js` scaffolds (no registration in this PR).
9. Small-screen check of the banner at 320 / 360 / 390 / 768 / 1024 px, ar + en, 200 % text.
10. Docs (memory bank, Arabic `documentation/`, English `documentation/en/`), ADR-057, open tasks.
11. `flutter analyze`, `flutter test`, rules tests, release build; compare `main.dart.js` size (budget **+20 KB gz**).
12. Screenshots 390 px Arabic: Android banner, the sideload guide (step 1 and 4, placeholders), iPhone banner + steps
    sheet, preferences page incl. the iOS install-first state (flag forced on in the test harness only).

## ١٠. الاختبارات (Tests)

- `detectInstallOs` matrix; `shouldShowInstallBanner` (disabled, desktop, standalone, installed event, `/admin`,
  dismissed until future/past, reshow 0 = never, remind later, not web).
- `resolveInstallAction`: apk URL wins; no URL + prompt → pwaPrompt; no prompt → androidSteps; iOS → iosSteps.
- `PushPrefs` encode/decode round trip, corrupted JSON → defaults, unknown types dropped, offered filter.
- `topicFor`: `announcements` / `seasons` → `web_/app_<type>_<lang>`; `verse_daily` / `katameros_daily` / `feasts` →
  throws on both platforms; `reminders` → throws on the APK, `reminderTopic` on the web (`web_rem_lit-x-20270430_60_ar`,
  every-time variant without the date); topic names match `[a-zA-Z0-9-_.~%]+`; `isLocalOwned(type, platform)` table.
- Reminders: `eventKeyFor` stable; `reconcileReminders` (kept / moved / changed / removed / expired); 30-item cap;
  leads already past disabled; «كل مرة» only for recurring items.
- `safeNotificationLink`: `/mass-schedule` ok, `/page/x?y=1#z` ok, `https://evil`, `javascript:`, `//evil.com`,
  empty → `/`.
- Widgets: banner shows on Android/iOS, hidden on desktop & standalone; ✕ writes `until`; «لاحقًا» writes remind
  date; the APK button calls `launch` with the URL **and opens the sideload guide**; guide: 5 steps, next / back /
  done, RTL order, missing image → placeholder, 320 px × 200 % no overflow; iOS steps sheet opens and **the fake env
  records zero permission calls**; 320 px × 200 % no overflow (ar/en).
- `/notifications`: hidden (404) with `push` off; with `push` on each state renders (incl. `iosNeedsInstall`,
  `iosTooOld`, `inAppBrowser`); web lists `announcements` / `seasons` / `reminders` only; «تذكيراتي» lists, edits
  and cancels; «ذكّرني» hidden when `reminders` not offered; sheet at 320 px × 200 % text; toggles persist; permission
  requested only after tap (fake env counts calls); «إيقاف كل الإشعارات» clears.
- Admin: `appSettingsDoc` fields, validators (URL, version pattern, VAPID pattern).
- Existing guards stay green: no hard-coded colours in `lib/ui` (palette roles only), accessibility sweep,
  PageSpeed tests.

## ١١. اختبار يدوي (Manual QA)

| Device | Checks |
|---|---|
| Android Chrome (real phone) | **install the PWA, uninstall it, revisit in the browser → banner shows again** (unless dismissed); **same tab**: install, uninstall, reload the original tab → banner shows again (stale flag cleared by `getInstalledRelatedApps()`); Samsung Internet same-tab → stays hidden until a new tab (documented limitation); banner after content; APK button downloads (use a test URL) and the sideload guide opens; follow the guide end to end on Android 14/15 (Samsung + Pixel-style) and note any wording difference for the screenshots; without URL the install prompt appears; ✕ → gone after reload; «لاحقًا» → gone; installed PWA → no banner |
| Samsung Internet | banner + steps fallback |
| iPhone Safari (iOS 17/18) | banner → steps sheet, **no notification prompt at any point**; `/notifications` in Safari → install-first card; after Add to Home Screen, opening from the icon → no banner, and `/notifications` shows the enable button (PR D) |
| iPhone in Facebook/WhatsApp in-app browser | "open in Safari" hint |
| iPad | treated as iOS |
| Desktop Chrome / Safari / Firefox | no banner |
| Arabic + English | texts, RTL/LTR, numbers (Arabic digits in Arabic) |
| Themes | Golden hour, dark Holy Week, festive, Marian — banner uses palette roles, readable on all |
| 320 px, 200 % text | no overflow, buttons reachable |
| `/admin` | edit texts → banner updates live; `push` off → no «الإشعارات» anywhere |

## ١٢. CI

No workflow change. Existing `ci.yml` (analyze, test, build, seed diff, rules emulator) and `deploy.yml` (preview
channel `pr-<n>`) cover it.

## ١٣. التوثيق (Docs / ADR)

ADR-057 "Install banner + notification preferences foundation": OS detection rules, APK-first on Android with the
visual sideload guide, iOS steps instead of an App Store link (never a permission request outside standalone),
channel-owner model per platform (`topicFor` refuses local-owned pairs), the «ذكّرني» UI and device-only reminder
store with `reconcileReminders`, dismiss memory in localStorage, `push` default off, settings as top-level keys,
+0 reads. Arabic manual `documentation/features/install-and-notifications.md` with the admin labels.

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| Banner annoys visitors | shown once per `installReshowDays`, 4 s after content, small, admin can switch off |
| `beforeinstallprompt` not fired (Samsung, Firefox) | steps fallback; APK link is the primary path anyway |
| iPadOS desktop UA | touch-points check |
| localStorage blocked (private mode) | treated as "not dismissed"; banner shows at most once per page load |
| PageSpeed drop | no new request on load; widget code small; size budget checked |

## ١٥. ما يفعله المالك (Owner steps)

None before merge except the visual approval of the preview. After merge (optional): `/admin` → «التطبيق
والإشعارات» → leave «شريط تثبيت التطبيق» on; the APK URL stays blank until PR B publishes the first APK
(the banner then offers the browser's install on Android).
