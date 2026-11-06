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
2. Lay the **notification foundation** used by PRs B–D: the type model, the preferences page with its complete UX,
   and the admin switches — all behind `settings/features.push` (default **off**), so nothing about notifications is
   visible on the live site until the owner turns it on after PR C/D.

## ٢. قصص المستخدم (User stories)

- كزائر على Android أرى «حمّل تطبيق الكنيسة» مع رقم الإصدار والحجم، وبضغطة واحدة يبدأ التحميل.
- كزائر على iPhone أرى «أضف الموقع إلى الشاشة الرئيسية» وعند الضغط تظهر ٣ خطوات بالأيقونات الحقيقية لـ Safari.
- إذا ضغطت ✕ لا يظهر الشريط مرة أخرى قبل المدة التي حددها المشرف (افتراضي ٣٠ يومًا)؛ «ذكّرني لاحقًا» يخفيه ٣ أيام.
- إذا كنت أفتح الموقع من التطبيق المثبت (PWA) أو من تطبيق Android لا أرى الشريط أبدًا.
- كمشرف أغيّر النصوص والروابط ورقم الإصدار والحجم والمدد من `/admin` بدون نشر جديد.
- (after `push` is on) as a visitor I open «الإشعارات», read what each type means, choose the types I want, and only
  then does the browser ask for permission. If I blocked it, I see how to re-enable it on my phone/browser.

## ٣. الخصائص الفرعية (Complete sub-features)

### 3.1 Install banner
| Sub-feature | Detail |
|---|---|
| OS detection | pure Dart `detectInstallOs(userAgent, platform, maxTouchPoints)` → `android` / `ios` (iPhone, iPod, iPad, **iPadOS that reports "Macintosh" with touch points > 1**) / `desktop` / `other`. In-app browsers (Facebook `FBAN/FBAV`, Instagram, WhatsApp `WhatsApp/`) flagged `inAppBrowser` → the iOS steps say "open in Safari first", Android download still works |
| Already installed | hidden when `matchMedia('(display-mode: standalone)')`, `(display-mode: minimal-ui)`, `navigator.standalone == true`, on any non-web build (`!kIsWeb` = the APK) and on `/admin`. The `appinstalled` event hides the banner **for the current browser session only** (`sessionStorage`), never permanently — so after the user uninstalls the PWA, a later browser visit shows the banner again (CodeRabbit on the plan PR). Where supported (Chrome Android), `navigator.getInstalledRelatedApps()` with a `related_applications` entry of type `webapp` for our own manifest confirms a still-installed PWA; unsupported → rely on the dismiss memory |
| Android action | `installAndroidUrl` set → button «تحميل التطبيق (١٨٫٤ م.ب • إصدار ١٫١٫٠)» opens the URL (download); optional small link «هاتف قديم؟» → `installAndroidUrl32`. URL blank → if the browser fired `beforeinstallprompt` (captured early in `index.html`) the button calls `prompt()`; else a sheet with "⋮ → تثبيت التطبيق / إضافة إلى الشاشة الرئيسية" |
| After APK tap | a short sheet: «بعد التحميل افتح الملف واسمح بالتثبيت من مصادر غير معروفة إذا طُلب» + link to the full guide (see LAUNCH-AND-OPERATIONS §5) |
| iPhone/iPad action | bottom sheet with 3 numbered steps using the real glyphs: 1 `Icons.ios_share` «اضغط زر المشاركة», 2 `Icons.add_box_outlined` «إضافة إلى الشاشة الرئيسية», 3 «إضافة». Note for iOS < 16.4 / non-Safari: «افتح الموقع في Safari». No screenshots (size) |
| Dismiss ✕ | stores `church_portal_install = {"until": "<ISO date>"}` in localStorage = now + `installReshowDays`; 0 = never again (`until` = far future) |
| Remind later | «ذكّرني لاحقًا» = now + `installRemindDays` |
| Timing | shown after the first real content (`ContentReady`, ADR-038) + 4 s, never over the loading screen; bottom of the viewport, above the safe-area inset; max width 560 px centred; does **not** change the hero |
| Accessibility | `Semantics(liveRegion)`, 48 dp targets, focus order title → action → later → ✕, works at 320 px × 200 % text, RTL/LTR |
| Admin | all texts, URLs, version, build, size, days, on/off |

### 3.2 Notification preferences (behind `push`)
| Sub-feature | Detail |
|---|---|
| Type model | `NotifyType` (`announcements`, `verse_daily`, `seasons`, `feasts`, `occasions`), ar/en labels + one-line descriptions, icons, FCM topic names (`web_<type>_<lang>`, `app_announcements_<lang>`) |
| Route `/notifications` | «الإشعارات» page; in the drawer and footer only when `push` is on. When off → the normal 404 (not indexable) |
| Explainer | before any browser prompt: what we send, how often, no personal data, «يمكنك الإيقاف في أي وقت» |
| Per-type toggles | only `pushTypes` offered by the admin; quiet default = all off; first opt-in pre-ticks `announcements` + `seasons` |
| Permission on tap only | `Notification.requestPermission()` only from the «تفعيل الإشعارات» button, never on load |
| States | `unsupported` (no `Notification`/`PushManager`/`serviceWorker`), `iosNeedsInstall` (iOS not standalone → show the install steps), `default`, `granted`, `denied` (blocked) |
| Blocked state | how to re-enable: Chrome Android «🔒 → الأذونات → الإشعارات → سماح», iPhone «الإعدادات → الإشعارات → كنيسة مكسيموس ودوماديوس», desktop Chrome/Edge/Firefox/Safari one line each |
| Unsubscribe all | «إيقاف كل الإشعارات» → clears choices; PR D also deletes the FCM token and queues an unsubscribe |
| Storage | localStorage `church_portal_push` = `{"types":[…],"lang":"ar","quiet":{"from":"22:00","to":"07:00"},"updatedAt":…}`; nothing in Firestore |
| Web scaffold | `web/firebase-messaging-sw.js` (no fetch handler, own scope) and `web/push_client.js` (lazy, injected on tap) — present but only used by PR D; with no `pushVapidKey` the enable button explains "قريبًا" and stays disabled |
| Not in this PR | quiet hours UI, test notification, inbox → PR B (Android) / PR D (web) — they need a delivery path |

## ٤. الشاشات (Screens)

- **Banner (Android)**: seal 40 px · title «تطبيق الكنيسة على هاتفك» · body · primary «تحميل التطبيق» + caption
  «الإصدار ١٫١٫٠ • ١٨٫٤ م.ب» · text button «لاحقًا» · ✕ (tooltip «إغلاق»).
- **Banner (iPhone)**: same; primary «طريقة الإضافة» → steps sheet.
- **Steps sheet (iPhone)**: 3 numbered rows with glyphs, «تم» button.
- **/notifications**: header (`CustomizablePageHeader`, page key `notifications`), explainer card, status card
  (granted / blocked / unsupported / install-first), type list (switch + label + description), «إيقاف كل
  الإشعارات», privacy line.
- **Admin `/admin` → «التطبيق والإشعارات»** (new destination, `Icons.install_mobile_outlined`): generic
  `ChurchInfoScreen` with `appSettingsDoc` (`DocDef('settings/features', …)`, writes only changed keys like
  `todaySettingsDoc`). Two groups: «شريط تثبيت التطبيق» and «الإشعارات (تجريبي)».

## ٥. نموذج البيانات + القواعد (Data model + rules)

New top-level keys in `settings/features` (see README §6 for the full contract): `installPrompt`,
`installTitleAr`, `installTitleEn`, `installBodyAr`, `installBodyEn`, `installAndroidUrl`, `installAndroidUrl32`,
`installApkVersion`, `installApkBuild`, `installApkSizeMb`, `installReshowDays`, `installRemindDays`, `push`,
`pushVapidKey`, `pushTypes`.

Dart (`lib/domain/app_install.dart`, `lib/domain/push.dart`, pure):
```dart
class InstallSettings { bool enabled; String titleAr, titleEn, bodyAr, bodyEn, androidUrl, androidUrl32,
  apkVersion; int apkBuild; double apkSizeMb; int reshowDays, remindDays; factory fromMap(Map m); }
class PushSettings { bool enabled; String vapidKey; List<NotifyType> offered; bool get webReady => enabled && vapidKey.isNotEmpty; }
```
Both parsed in `FeatureSettings.fromMap` as `install` / `pushSettings` (never written by `toMap`, like `today`).

`firestore.rules` → `validFeatures`: add the 15 keys to `keysAllowed([...])` and two gates (only evaluated when
one of their keys changes, so the 1,000-expression budget of other saves is untouched):
```
&& (!changed.hasAny(['installPrompt','installTitleAr','installTitleEn','installBodyAr','installBodyEn',
     'installAndroidUrl','installAndroidUrl32','installApkVersion','installApkBuild','installApkSizeMb',
     'installReshowDays','installRemindDays'])
    || (optBool(d,'installPrompt') && str(d,'installTitleAr',120) && str(d,'installTitleEn',120)
        && str(d,'installBodyAr',300) && str(d,'installBodyEn',300)
        && optUrlOrPath(d,'installAndroidUrl',500) && optUrlOrPath(d,'installAndroidUrl32',500)
        && d.get('installApkVersion','').matches('^$|^[0-9]+([.][0-9]+){0,3}$')
        && optInt(d,'installApkBuild',0,999999) && optNumber(d,'installApkSizeMb',0,200)
        && optInt(d,'installReshowDays',0,365) && optInt(d,'installRemindDays',1,60)))
&& (!changed.hasAny(['push','pushVapidKey','pushTypes'])
    || (optBool(d,'push') && d.get('pushVapidKey','').matches('^$|^[A-Za-z0-9_-]{80,100}$')
        && optList(d,'pushTypes',5)
        && d.get('pushTypes',[]).hasOnly(['announcements','verse_daily','seasons','feasts','occasions'])
        && d.get('pushTypes',[]).toSet().size() == d.get('pushTypes',[]).size()))
```
Also allow the page key `notifications` wherever `validPageHeaders` lists the customizable pages (the page header
override of `/notifications`), and add it to `CustomizablePages.all`.

Rules tests (`tool/rules_test/rules.test.mjs`): admin can set each key; stranger cannot; bad URL (`javascript:`),
version `1.x`, build −1, size 500, reshow 400, remind 0, VAPID with spaces, unknown type, duplicate type → denied;
an unrelated save (e.g. `heroMotion`) still passes with the worst-case page headers.

## ٦. التكلفة (Read / write cost)

+0 visitor reads (same `settings/features` stream), +0 writes (localStorage only), admin saves only. Network: the
banner adds no request; `push_client.js` (~3 KB) and the gstatic messaging module load only on the user's tap
(PR D).

## ٧. الملفات (Files)

Create:
- `lib/domain/app_install.dart` — `InstallSettings`, `InstallOs`, `detectInstallOs`, `InstallBannerDecision shouldShowInstallBanner({settings, os, standalone, installedEvent, dismissedUntil, now, path, isWeb})`, `InstallAction resolveInstallAction(...)` (`apk` / `pwaPrompt` / `androidSteps` / `iosSteps` / `none`).
- `lib/domain/push.dart` — `NotifyType` enum + labels/descriptions/icons keys, `PushSettings`, `PushPrefs` (encode/decode JSON, defaults, `firstOptInTypes`), `topicFor(type, lang, {web})`, `PushPermissionState`, `safeNotificationLink(String)` (in-app path only, else `/`).
- `lib/core/install_env.dart` + `install_env_stub.dart` + `install_env_web.dart` — `userAgent`, `platform`, `maxTouchPoints`, `isStandalone`, `hasDeferredPrompt`, `Future<bool> promptInstall()`, `readJson/writeJson(key)` (localStorage, try/catch like `locale_storage_web.dart`).
- `lib/core/push_env.dart` + `push_env_stub.dart` + `push_env_web.dart` — `isSupported`, `permission`, `Future<String> requestPermission()`; (PR D adds token calls).
- `lib/ui/widgets/install_banner.dart` — `InstallBanner` (ConsumerStatefulWidget) + `showIosInstallSteps` / `showAndroidSteps` sheets.
- `lib/ui/pages/notifications_page.dart` — `NotificationsPage`.
- `web/firebase-messaging-sw.js` — scaffold (see PR D for the full file); `web/push_client.js` — scaffold.
- `test/install_banner_test.dart`, `test/push_prefs_test.dart`.
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
- `lib/core/l10n.dart` — ~45 strings `[ar, en]`.
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
5. `InstallBanner` + sheets; place in `AppShell`; widget tests with a fake env (inject via provider
   `installEnvProvider`).
6. `NotificationsPage` + route + nav/footer entries behind `push`; widget tests per permission state.
7. Admin `appSettingsDoc` + destination; admin widget test (fields render, save writes only changed keys).
8. `web/firebase-messaging-sw.js` + `web/push_client.js` scaffolds (no registration in this PR).
9. Small-screen check of the banner at 320 / 360 / 390 / 768 / 1024 px, ar + en, 200 % text.
10. Docs (memory bank, Arabic `documentation/`, English `documentation/en/`), ADR-057, open tasks.
11. `flutter analyze`, `flutter test`, rules tests, release build; compare `main.dart.js` size (budget **+20 KB gz**).
12. Screenshots 390 px Arabic: Android banner, iPhone banner + steps sheet, preferences page (flag forced on in the
    test harness only).

## ١٠. الاختبارات (Tests)

- `detectInstallOs` matrix; `shouldShowInstallBanner` (disabled, desktop, standalone, installed event, `/admin`,
  dismissed until future/past, reshow 0 = never, remind later, not web).
- `resolveInstallAction`: apk URL wins; no URL + prompt → pwaPrompt; no prompt → androidSteps; iOS → iosSteps.
- `PushPrefs` encode/decode round trip, corrupted JSON → defaults, unknown types dropped, offered filter.
- `safeNotificationLink`: `/mass-schedule` ok, `/page/x?y=1#z` ok, `https://evil`, `javascript:`, `//evil.com`,
  empty → `/`.
- Widgets: banner shows on Android/iOS, hidden on desktop & standalone; ✕ writes `until`; «لاحقًا» writes remind
  date; the APK button calls `launch` with the URL; iOS steps sheet opens; 320 px × 200 % no overflow (ar/en).
- `/notifications`: hidden (404) with `push` off; with `push` on each state renders; toggles persist; permission
  requested only after tap (fake env counts calls); «إيقاف كل الإشعارات» clears.
- Admin: `appSettingsDoc` fields, validators (URL, version pattern, VAPID pattern).
- Existing guards stay green: no hard-coded colours in `lib/ui` (palette roles only), accessibility sweep,
  PageSpeed tests.

## ١١. اختبار يدوي (Manual QA)

| Device | Checks |
|---|---|
| Android Chrome (real phone) | **install the PWA, uninstall it, revisit in the browser → banner shows again** (unless dismissed); banner after content; APK button downloads (use a test URL); without URL the install prompt appears; ✕ → gone after reload; «لاحقًا» → gone; installed PWA → no banner |
| Samsung Internet | banner + steps fallback |
| iPhone Safari (iOS 17/18) | banner → steps sheet; after Add to Home Screen, opening from the icon → no banner |
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

ADR-057 "Install banner + notification preferences foundation": OS detection rules, APK-first on Android, iOS
steps instead of an App Store link, dismiss memory in localStorage, `push` default off, settings as top-level keys,
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
