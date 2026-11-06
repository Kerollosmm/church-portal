# PR E — مراجعة التجاوب مع كل الشاشات + حجم التطبيق (Responsive & size audit)

| | |
|---|---|
| Branch → base | `fix/p2e-responsive-size` → `feat/p2d-web-push` (stacked chain, HANDOFF §1; **do not merge** until the whole chain is approved) |
| ADR | **ADR-061** |
| Depends on | none to start (the 320 px app-bar fix can land earlier, even inside PR A); final pass after PR D |
| Owner console work | none |

## ١. الهدف (Goal)

Every public page, the new install banner / notifications page / update banner, and `/admin` look right and never
overflow from **320 px phones to 1920 px desktops**, at 100–200 % text, Arabic and English, every occasion theme;
the web bundle and the APK stay small, with budgets enforced in CI.

## ٢. قصص المستخدم (User stories)

- على هاتف صغير (٣٢٠ بكسل) أقرأ اسم الكنيسة في الشريط العلوي دون أن يلمس الختم.
- على التابلت أرى الأعمدة مستغلة بشكل جيد، وعلى الكمبيوتر لا تمتد السطور بعرض الشاشة كلها.
- التطبيق صغير الحجم فيتحمّل بسرعة على باقة محدودة.

## ٣. الخصائص الفرعية (Sub-features)

| Sub-feature | Detail |
|---|---|
| Known bug: ~8 px app-bar overlap at 320 px | live check 4 Nov 2026: «كنيسة مكسيموس ودوماديوس» touches the seal tab at 320 px (real font, not the test font). Fix in `AppShell`: below 360 px the short title uses `size: 15`, `maxLines: 2`, and `tabSpace` is computed from the real tab width + 4 px gap; regression test measures `tester.getRect(title).left/right` vs the seal tab rect (RTL and LTR) with the bundled Plex/Lalezar fonts loaded via `FontLoader` (not the Ahem test font) |
| Width sweep | 320, 360, 390, 412, 600, 768, 820, 1024, 1280, 1440, 1920 × text 1.0 / 1.3 / 2.0 × ar / en × themes (goldenHour, holyWeek, resurrection, nativity, marian) — every public route + `/notifications` + banner + admin screens; extends `test/accessibility_test.dart` (currently 320 px × 200 %) |
| Real-font goldens | a small set (Home, Mass schedule, Notifications, banner) at 320 / 390 / 1024 px rendered with the real fonts (`loadAppFonts()` helper) for visual review; goldens stored under `test/goldens/` and **not** run on CI by default (font raster differences) — `--tags goldens` |
| Tablet layout | `ResponsiveGrid` breakpoints checked at 600–1024; max content width 1200 px on desktop; hero unchanged |
| Landscape phones | 740 × 360: app bar + top utility bar ≤ 40 % of height; banner hidden in landscape when height < 420 |
| Safe areas | notch / home indicator: banner and update banner use `SafeArea` / `MediaQuery.viewPadding` (iPhone PWA standalone, Android gesture nav) |
| Web bundle budget | baseline `main.dart.js` on `main` @ `7e4705b`: **4,898,252 B (1,334,591 B gzip -9)**. Budget: Phase 2 total ≤ +60 KB gzip; CI step fails above `MAIN_JS_GZ_MAX` (repo variable, default 1,400,000) |
| APK budget | arm64 ≤ 20 MB, arm32 ≤ 18 MB (report in PR B); `--split-per-abi`, R8 + resource shrinking, `--obfuscate --split-debug-info`, tree-shaken icons; no x86 |
| Asset audit | `assets/video/*.mp4` (358 KB) and art webp are already small; fonts are full (522 KB) → subset IBM Plex Sans Arabic / Lalezar / Aref Ruqaa to Arabic + Latin + digits with `pyftsubset` (target −50 %), keep licences; verify Arabic shaping in goldens |
| PageSpeed guard | Lighthouse CI (mobile) on the preview channel URL in `deploy.yml` (job `lighthouse`, `treosh/lighthouse-ci-action@v12`), **warn** below 61 performance, report in the PR; not blocking (network variance) |

## ٤. الشاشات (Screens)

No new screens. Visual fixes only; hero look unchanged (owner rule).

## ٥. البيانات + القواعد (Data / rules)

None. Cost +0.

## ٦. الملفات (Files)

- `lib/ui/widgets/app_shell.dart` (title / tab spacing), any page that fails the sweep.
- `test/accessibility_test.dart` (wider sweep), `test/helpers/real_fonts.dart` (FontLoader), `test/responsive_goldens_test.dart` (tagged), `dart_test.yaml` (tag `goldens` skipped by default).
- `tool/subset_fonts.sh` (pyftsubset), `assets/fonts/*` (subset files), `pubspec.yaml` if names change.
- `.github/workflows/ci.yml` (bundle-size step), `.github/workflows/deploy.yml` (optional Lighthouse job).
- Docs: `documentation/features/accessibility.md`, `performance-pagespeed.md`, memory bank 08/10/11, ADR-061.

## ٧. الحزم (Packages)

None in the app. CI: `treosh/lighthouse-ci-action@v12` (optional), `fonttools` (pip, local/CI tool only).

## ٨. خطوات التنفيذ (Step-by-step)

1. Reproduce the 320 px overlap with real fonts in a widget test → fix → test green.
2. Extend the sweep matrix; fix each failure at its root cause (no blanket `FittedBox`).
3. Font subsetting + Arabic shaping check (goldens, manual on a phone).
4. Bundle-size CI step:
   ```bash
   GZ=$(gzip -9c build/web/main.dart.js | wc -c); echo "main.dart.js gzip: $GZ"
   [ "$GZ" -le "${MAIN_JS_GZ_MAX:-1400000}" ] || { echo "::error::main.dart.js too big"; exit 1; }
   ```
5. Optional Lighthouse job on previews.
6. Docs + ADR-061; screenshots at 320 / 390 / 768 / 1024 / 1440 px in the PR body.

## ٩. الاختبارات (Tests)

- Sweep: no `FlutterError` overflow on any route × width × text scale × locale × theme.
- App bar: title rect does not intersect the seal-tab rect at 320 / 340 / 359 px (ar, en, Back arrow shown/hidden).
- Banner + update banner: within the viewport, above safe area, at 320 × 200 %.
- Bundle-size step fails when over budget (unit-tested via a fake file in a shell test).

## ١٠. اختبار يدوي (Manual QA)

Chrome DevTools device mode at 320 (Galaxy Fold folded ≈ 280–344), iPhone SE (375), iPhone 15 (393), Pixel 8
(412), iPad Mini (768), iPad Pro (1024), laptop 1366, desktop 1920; real phones: one small Android, one iPhone;
Arabic + English; Holy Week dark theme; largest system font on Android and iOS (Dynamic Type in the PWA).

## ١١. CI

`ci.yml` bundle-size step after the web build; optional Lighthouse on previews.

## ١٢. التوثيق (Docs / ADR)

ADR-061: breakpoints, sweep matrix, real-font regression for the app bar, size budgets (web + APK), font subsetting.

## ١٣. المخاطر (Risks)

| Risk | Mitigation |
|---|---|
| Font subset drops a needed glyph (Coptic month names, ligatures) | build the subset from all strings in `lib/`, seed and verses + full Arabic block; goldens |
| Golden flakiness | not on CI by default |
| Lighthouse variance | warn only |

## ١٤. ما يفعله المالك (Owner steps)

Visual approval of the screenshots / preview on his own phones. Optional: set repo variable `MAIN_JS_GZ_MAX`.
