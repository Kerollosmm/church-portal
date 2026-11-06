# PR B — تطبيق Android (APK) + الإشعارات المحلية (Android APK + local notifications)

| | |
|---|---|
| Branch → base | `feat/p2b-android-local-notifications` → `feat/p2a-install-prefs` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-058** |
| Depends on | PR A (type model `NotifyType`, `PushPrefs`, install fields `installApkBuild` / `installAndroidUrl`) |
| Owner console work | **signing keystore + 4 GitHub secrets** (§15). Without them CI produces debug-signed *test* APKs only |
| Live effect after merge | none on the website; a signed APK is published to GitHub Releases by a tag (§12), then its URL goes into `/admin` |

## ١. الهدف (Goal)

A small, complete Android app built from the same Flutter code, downloaded from the site as an APK, that schedules
**local notifications on the phone** (verse of the day, season starts, feasts, mass / occasion reminders) from
data it already loads — no server, no extra Firestore reads — following the admin's configuration (built-in
defaults until PR C adds the admin editor) and the user's per-type choices.

## ٢. قصص المستخدم (User stories)

- أحمّل التطبيق من الموقع وأثبته، يفتح بشاشة البداية وأيقونة الختم، بالعربي أو الإنجليزي كما اخترت آخر مرة.
- أفتح «الإشعارات» في القائمة: أختار آية اليوم الساعة ٧ صباحًا، وتذكير القداس قبل ساعة، وبداية المواسم.
- تصلني الإشعارات حتى بدون إنترنت (مجدولة على الهاتف)، ولا تصلني في ساعات الهدوء.
- أضغط الإشعار فيفتح الصفحة المناسبة (مواعيد القداسات، الموسم، …).
- أرى سجل آخر الإشعارات داخل التطبيق.
- عند صدور إصدار جديد أرى «تحديث متاح» وأحمّله بضغطة.
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
| Update prompt | `package_info_plus` build number `% 1000` (split-per-abi adds 1000×ABI) < `installApkBuild` (already in the streamed `settings/features`) → banner «تحديث متاح — الإصدار ١٫٢٫٠» → opens `installAndroidUrl` in the browser. Dismiss per version |
| Install banner | hidden (`!kIsWeb`) |

### 3.2 Local notifications
| Sub-feature | Detail |
|---|---|
| Permission explainer | the PR A page; Android 13+ `POST_NOTIFICATIONS` requested via `flutter_local_notifications` `requestNotificationsPermission()` only after the tap |
| Blocked state | Android: «الإعدادات ← التطبيقات ← كنيسة مكسيموس ودوماديوس ← الإشعارات ← سماح» + button that opens the app's notification settings (`AppSettings`-style intent via the plugin's `openNotificationSettings` / `android.settings.APP_NOTIFICATION_SETTINGS`) |
| Per-type toggles | only admin-offered `pushTypes` |
| Times | verse time (admin default 07:00, user may override within the page: «وقت آية اليوم»), mass reminder lead (admin default 60 min, user choice 15/30/60/120) |
| Quiet hours | user «ساعات الهدوء» from–to (default 22:00–07:00, can switch off): planned alarms inside the window move to its end (verse) or are skipped (reminders that would be after the event) |
| Test notification | «جرّب إشعارًا» → `show()` now with the chosen type's sample text |
| Inbox | «سجل الإشعارات»: the last 30 *delivered* items = planned items whose time has passed (the plan is stored) + FCM announcements received (PR C); stored in `shared_preferences`; tapping opens the link |
| Deep link | payload `link` → `router.go(safeNotificationLink(link))`; app started from a notification → `getNotificationAppLaunchDetails()` → initial location; deleted page → existing 404 with «الرجوع للرئيسية»; switched-off section → FeatureGate «غير متاح» |
| Unsubscribe all | cancels all pending alarms + clears prefs (PR C: also unsubscribes the FCM topic) |
| Re-sync | re-plan on: app start, resume (`AppLifecycleState.resumed`), prefs change, `settings/features` change (admin edits types / verse / dayEvents), date or time-zone change (`didChangeLocales` no; use resume + `DateTime.now().timeZoneOffset` compare), device reboot (plugin's `ScheduledNotificationBootReceiver` restores) |
| Planning horizon | next **14 days**, ≤ 60 pending (Android caps ~500/app; Samsung 500) — cancel-all then schedule (ids derived from a stable hash `type:date:key`) |
| Channels | one channel per type (`verse_daily`, `seasons`, `feasts`, `occasions`, `announcements`) with Arabic names, so users can mute a channel in system settings |
| Exactness | **inexact** `AndroidScheduleMode.inexactAllowWhileIdle` (± ~10 min in Doze). No `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` (special permission, policy risk). Documented caveat |
| Battery optimisation | if notifications arrive late on some brands (Xiaomi, Oppo, Realme, Huawei, Samsung "Sleeping apps"), the page shows «إذا تأخرت الإشعارات: الإعدادات ← البطارية ← التطبيق ← بدون قيود» with a button to `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` (list, not the direct request — no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission) |
| Content sources | `verse_daily`: `dailyVerseFor` (bundled `assets/verses/daily_verses.json`, admin fixed / season verses from `settings/features`); `seasons`: `seasonsProvider` (already cached) → start day at the type time, optional N days before; `feasts`: `copticFeastsOn` (computed) for each day + `/data/today.json` titles when cached; `occasions`: `occurrencesForDay` of liturgies / season programme services + `dayEvents` with times, `lead` minutes before. Texts from `notifyTypes` templates (PR C) or built-in defaults |

## ٤. الشاشات (Screens)

- `/notifications` on Android (PR A page + Android sections): status, per-type switches, «وقت آية اليوم» time
  picker, «التذكير قبل القداس» chips, «ساعات الهدوء» switch + two time pickers, «جرّب إشعارًا», «سجل الإشعارات»,
  battery note, «إيقاف كل الإشعارات».
- Update banner (top of Home, palette `notice` roles): «تحديث متاح» + «تحميل» + ✕.
- Notification look: small icon = monochrome seal (`res/drawable/ic_stat_seal.xml`, white vector), colour
  `#6E1C1C` (`android:color` in channel / `color:` in `AndroidNotificationDetails` — native resource, not `lib/ui`),
  title + body, tap → link.

## ٥. نموذج البيانات + القواعد (Data model + rules)

No new Firestore keys or rules in this PR (reads `installApkBuild`, `installAndroidUrl`, `pushTypes` from PR A and,
once PR C lands, `notifyTypes`). Built-in defaults live in `lib/domain/push.dart` (`NotifyTypeConfig.defaults`:
verse 07:00, seasons 08:00 on the start day, feasts 07:30, occasions lead 60 min).

Device storage (`shared_preferences`): `church_portal_push` (same JSON as web), `church_portal_lang`,
`church_portal_notify_plan` (list of `{id,type,at,title,body,link}` for the inbox), `church_portal_inbox` (FCM),
`church_portal_update_dismissed` (build number).

## ٦. التكلفة (Cost)

Firestore +0 (the planner reads the providers the app already streams; it does not start any listener that the
Home page would not). Network +0 except `/data/today.json` already fetched by the Home page. CI: Android build
~8–12 min per run on `ubuntu-latest` (free, public repo).

## ٧. الملفات (Files)

Create:
- `lib/domain/notify_plan.dart` — pure `List<PlannedNotification> planNotifications({required DateTime now, required PushPrefs prefs, required NotifyConfig config, required inputs…})` (Cairo time via `CairoTime`, quiet hours, horizon, ids).
- `lib/data/local_notifications.dart` — `LocalNotifier` wrapper around `FlutterLocalNotificationsPlugin` (init, channels, permission, `zonedSchedule`, cancelAll, launch details), conditional import so web never links it (`local_notifications_stub.dart`).
- `lib/state/notify_providers.dart` — `notifyPlannerProvider` (listens to prefs / features / seasons / now-day, debounced 2 s, re-plans).
- `lib/ui/widgets/update_banner.dart`.
- `lib/core/locale_storage_io.dart` (shared_preferences) — conditional import update in `locale_storage.dart`.
- `android/app/src/main/res/drawable/ic_stat_seal.xml`, `android/app/src/main/res/values-v31/styles.xml`.
- `android/key.properties.example` (documented, real file git-ignored); `android/RELEASE_NOTES.md` (Arabic notes shown on the GitHub Release, edited per release).
- `.github/workflows/android.yml` (§12).
- `test/notify_plan_test.dart`, `test/android_shell_test.dart`.
- `documentation/features/android-app.md` (rewrite), ADR-058.

Modify:
- `pubspec.yaml` (§8), `android/app/build.gradle.kts` (signing from env / `key.properties`, `isMinifyEnabled = true`, `isShrinkResources = true`, core-library desugaring), `android/app/src/main/AndroidManifest.xml` (permissions + plugin receivers, `android:label` Arabic name kept), `android/app/proguard-rules.pro` (plugin keep rules if R8 strips them).
- `lib/router.dart` (`kIsWeb` admin guard, initial location from a launch notification), `lib/ui/widgets/app_shell.dart` (PopScope, update banner, drawer «الإشعارات»), `lib/ui/pages/notifications_page.dart` (Android sections), `lib/ui/pages/assistant_page.dart` / nav (open web `/ask` on Android), `lib/main.dart` (init `LocalNotifier` after first frame — never block start-up).
- `.gitignore` (`android/key.properties`, `*.jks`, `*.keystore`).
- Docs: memory bank 03/06/08/10/11, `documentation/features/android-app.md`, `documentation/operations.md` (release steps), `documentation/en/operations.md`.

## ٨. الحزم (Packages — checked on pub.dev 6 Nov 2026)

| Package | Version | Why | Notes |
|---|---|---|---|
| `flutter_local_notifications` | `^23.0.0` | scheduled local notifications | needs Flutter ≥ 3.44 (repo builds on stable 3.47); depends on `timezone ^0.11.0` (repo already `^0.11.2`); requires **core library desugaring** (`isCoreLibraryDesugaringEnabled = true`, `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`) |
| `package_info_plus` | `^10.2.2` | APK build number for the update prompt | small |
| `shared_preferences` | `^2.5.6` | already a dependency | prefs, inbox, language |
| `share_plus` | optional (`^12`) | system share sheet | add only if the APK budget allows |
| `firebase_messaging` | — | **PR C** (announcements) | not in this PR |

## ٩. خطوات التنفيذ (Step-by-step)

1. `planNotifications` (pure) + exhaustive tests first. Egypt observes summer time again (EEST, since 2023): always
   use `CairoTime` / `tz` `Africa/Cairo`, never a fixed +2 offset; tests cover a summer and a winter date and the
   switch nights.
2. Android build config: desugaring, minify/shrink, signing from env (falls back to debug when no secret), verify
   `flutter build apk --release --split-per-abi` locally or in CI.
3. `kIsWeb` admin guard; Android language store; PopScope back handling; assistant opens web `/ask`.
4. `LocalNotifier` + channels + permission flow; wire `/notifications` Android sections.
5. Planner provider: re-plan triggers (start, resume, prefs, features, day change); boot receiver.
6. Inbox, test notification, quiet hours, battery note, unsubscribe all.
7. Update banner (`installApkBuild`).
8. `android.yml` workflow: APK artifacts on PRs, signed release on tag.
9. Docs + ADR-058; size report (APK per ABI) in the PR body.
10. Real-device pass (§11) on at least: Android 14/15 Samsung, Android 13 Xiaomi/Redmi, Android 10 or 11 low-end
    (armeabi-v7a), Android 8.1 (minSdk check: Flutter default `minSdk 21+`; plugin needs ≥ 21).

## ١٠. الاختبارات (Tests)

- `notify_plan_test.dart`: verse at 07:00 Cairo for 14 days; quiet hours move 06:30 → 07:00 and skip reminders
  inside; mass reminder 60 min before each Sunday liturgy and a weekday one-off `dayEvents` item; season start on
  its start day (+ N days before); feast list from `copticFeastsOn` around Nativity (29 Kiahk) and a movable feast
  (Pascha); offered-types filter; user type off → nothing; ≤ 60 items, earliest first; stable ids; links
  `safeNotificationLink`; templates with `{season}`, `{feast}`, `{verse}`, `{time}` substituted ar/en; past times
  skipped.
- Shell: `/admin` is not a route when `kIsWeb` is false (test via injectable `isWeb` param of the router builder);
  back-button mapping (`parentRouteOf`); update banner shown only when `installApkBuild` > local build;
  language persists through the IO store (fake).
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
| 10 | Publish build N+1 (`installApkBuild`) | «تحديث متاح» → download → install over the old one keeps data (same key!) |
| 11 | Deleted custom page link in the inbox | 404 «الرجوع للرئيسية» |
| 12 | Themes (Golden hour, Holy Week dark) | readable; status bar contrast |
| 13 | 320-px-class phone (e.g. small Android Go) + largest font | no overflow |
| 14 | Xiaomi with battery saver | note shown; after "no restrictions" notifications on time |

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
          flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
            --obfuscate --split-debug-info=build/symbols \
            --dart-define=SENTRY_ENVIRONMENT=${{ startsWith(github.ref, 'refs/tags/') && 'production' || 'preview' }} \
            --dart-define=GIT_SHA=$GITHUB_SHA --dart-define=APP_VERSION=$APP_VERSION
          ls -l build/app/outputs/flutter-apk/
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
          gh release create "$GITHUB_REF_NAME" church-portal-arm64.apk church-portal-arm32.apk \
            --title "تطبيق الكنيسة $GITHUB_REF_NAME" --notes-file "$GITHUB_WORKSPACE/android/RELEASE_NOTES.md" --latest
    permissions: { contents: write }
```
- `build.gradle.kts` reads `ANDROID_KEYSTORE_PATH` etc. from env (or `android/key.properties` locally); empty →
  debug signing (PR / preview builds).
- Stable URLs for `/admin`: `https://github.com/Kerollosmm/church-portal/releases/latest/download/church-portal-arm64.apk`
  and `…/church-portal-arm32.apk`.
- Sentry: upload Dart symbols (`sentry-dart-plugin`) optional later; obfuscation map kept as artifact.

## ١٣. التوثيق (Docs / ADR)

ADR-058: APK from GitHub Releases (Hosting egress), split-per-abi arm64 + arm32 (no x86), inexact local alarms,
14-day horizon, no exact-alarm permission, admin compiled out, assistant via the web, dark mode = site theme,
update prompt via `installApkBuild`, debug-signed until the keystore exists.

## ١٤. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| **Lost keystore** → no updates possible (users must uninstall) | two offline backups + password manager (LAUNCH §3) |
| Debug-signed early installs can't upgrade to release-signed | publish to users only release-signed builds; debug builds are for testers |
| OEM battery killers delay alarms | inexact + note + settings shortcut; FCM not used for daily types on Android |
| Play Protect warns about an unknown app | normal for sideloading; guide text; signing with the same key builds reputation |
| Google Android developer verification (4 countries since 30 Sep 2026, global 2027) | LAUNCH §8: register in the Android Developer Console and register the package with the release-signed APK before it applies in Egypt |
| APK size > 25 MB | budget in PR E: arm64 ≤ 20 MB; remove `share_plus` if needed; `--obfuscate`; R8 |
| Plan exceeds horizon if the app is not opened for 14 days | boot + resume re-plan; FCM announcements still arrive (PR C) |

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
6. **First release**: bump `version:` in `pubspec.yaml` (e.g. `1.1.0+2`) in a PR, merge, then GitHub → **Releases**
   → **Draft a new release** → tag `apk-v1.1.0` → **Publish** (or `git tag apk-v1.1.0 && git push origin
   apk-v1.1.0`). The workflow attaches the two APKs.
7. `/admin` → «التطبيق والإشعارات»: رابط APK = the arm64 "latest" URL above; رابط الهواتف القديمة = the arm32 URL;
   الإصدار `1.1.0`; رقم البناء `2`; الحجم (from the release page, MB).
