# PR E — مراجعة التجاوب مع كل الشاشات + حراسة الحزم المؤجلة وتدقيق الحجم (Responsive & size audit)

| | |
|---|---|
| Branch → base | `fix/p2e-responsive-size` → `feat/p2d-web-push` (plus merged `origin/fix/mobile-chrome-perf` `ADR-062`; never reverse-merge `dev`) |
| ADR | **ADR-061** |
| Depends on | PRs A (#51), B (#52), C (#55), D (#56), and `fix/mobile-chrome-perf` (`ADR-062`) |
| Firestore cost | +0 reads · +0 writes · +0 listeners |
| Owner console work | none |

> **Revised 9 Nov 2026 (Owner Architecture Lock & PRs A–D + ADR-062 Alignment — Supersedes Nov 6 draft assumptions):**
> 1. **Clean Git Lineage & Bottom-Up Merge Order (`ADR-061` / `HANDOFF.md`)**:
>    - Branch `fix/p2e-responsive-size` directly from `feat/p2d-web-push` (`5439216`) with `origin/fix/mobile-chrome-perf` (`58d8239`, `ADR-062`) cleanly merged via `--no-ff`.
>    - `dev` (`ea7cbe9`) contains out-of-scope commits and must **never** be reverse-merged into this branch or the stacked chain. Merges proceed strictly bottom-up (`#55` -> `#56` -> PR E -> `dev` preview / `main`).
> 2. **Font Subsetting Dropped Completely (Diacritics & OpenType Preservation)**:
>    - Font subsetting (`pyftsubset` / `tool/subset_fonts.sh`) is **dropped completely** to preserve OpenType `GSUB`/`GPOS` shaping tables and full Arabic diacritics (tashkeel) essential for liturgical Katameros readings (`/readings/:date`) and free-form admin notifications.
>    - Split release APKs (~15 MB) already sit safely below the 20 MB/18 MB caps enforced in `.github/workflows/android.yml`.
> 3. **`AppShell` < 360 px Space Recovery & Landscape < 420 px Restraint**:
>    - On ultra-narrow viewports (`width < 360 px`): `SealTab` width is reduced to `54 dp` (from `64 dp`), short title typography is tuned to `size: 15` (`maxLines: 2`, `height: 1.15`), and when `showBack && width < 360`, the language toggle (`EN/ع`) moves from the top bar into the drawer (`_AppDrawer`), ensuring `>= 130 dp` readable title width without colliding with the seal tab or vanishing.
>    - Geometry verified deterministically via `FontLoader` rect geometry in `test/accessibility_test.dart` (`!titleRect.overlaps(sealRect)` with `>= 6 dp` gap), completely avoiding brittle OS-dependent PNG goldens.
>    - Landscape restraint: when `height < 420 px` (e.g. 740×360 px landscape), both `InstallBanner` and `TopUtilityBar` are automatically concealed.
> 4. **Phase 2 Surface Matrix & Modal Bottom Sheet Padding**:
>    - `/readings/:date`: Replace fixed `148 dp` `toolbarHeight` with dynamic `SliverToBoxAdapter` header; clamp UI chrome `TextScaler` to `<= 1.5x`, and scripture body text scaling to `<= 2.5x` (`(osScale * readerScale).clamp(0.85, 2.5)`).
>    - `/notifications`, `/notifications/battery`, `UpdateBanner` + `UpdateSheet`, `InstallBanner`, `ApkInstallGuide` (`isScrollControlled: true`), `RemindMeButton` (`lib/ui/widgets/remind_me.dart`) + `ReminderSheet` (`lib/ui/widgets/reminder_sheet.dart`), and `AppAndNotificationsScreen` (`lib/ui/admin/notifications_admin.dart`).
>    - All modal bottom sheets enforce `MediaQuery.viewInsetsOf(context).bottom` soft-keyboard padding and `LayoutBuilder` action wrapping.
>    - Deferred chunk load failures report to `ErrorReporting.capture(e, st, section: 'deferred_chunk', source: ...)`.
> 5. **Hard-Blocking CI Gates vs. Non-Blocking Lighthouse Audit**:
>    - `tool/check_web_bundle.mjs` verifies `main.dart.js.map` `sources` for zero leaked symbols from all 8 deferred modules (`notifications_page`, `notification_health_page`, `readings_page`, `assistant_page`, `admin_page`, `apk_install_guide`, `reminder_sheet`, `web_push_repository`), and checks `gzip -9 <= MAIN_JS_GZ_MAX` (`1,396,031 B`).
>    - Lighthouse mobile audit runs with `continue-on-error: true` against the existing `pr-<n>` preview channel in `deploy.yml` (using 0 extra Hosting channels).

---

## ١. الهدف (Goal)

Every public page, Phase 2 surface (`/readings/:date`, `/notifications`, `/notifications/battery`, `InstallBanner`, `UpdateBanner` + `UpdateSheet`, `ApkInstallGuide`, `RemindMeButton` + `ReminderSheet`, and `/admin`), and layout mode looks right and never overflows from **320 px phones to 1920 px desktops** (including landscape 740×360 px), at 100–200% text scale, Arabic and English, across all 7 occasion themes; the web bundle and split APKs remain strictly within their size budgets, enforced by hard-blocking CI gates.

## ٢. قصص المستخدم (User stories)

- على هاتف صغير جدًا (٣٢٠ بكسل) أو عند تكبير الخط إلى ٢٠٠٪، أقرأ اسم الكنيسة بوضوح كامل في الشريط العلوي دون أن يختفي أو يتداخل مع ختم الكنيسة، وتظهر نصوص القراءات والتنبيهات بلا أي طفح أفقي أو رأسي.
- عند تدوير الهاتف للوضع الأفقي (Landscape بارتفاع أقل من ٤٢٠ بكسل)، يختفي شريط التثبيت والشريط الطقسي العلوي تلقائيًا لإفساح المجال للمحتوى التعبدي.
- عند فتح لوحات الخيارات المنبثقة (مثل نافذة خطوات التثبيت أو نافذة التذكيرات)، تتجاوب اللوحة مع لوحة المفاتيح الرقمية وتبقى الأزرار قابلة للنقر.
- التطبيق خفيف وسريع التحميل على شبكات الهاتف وباقات الإنترنت المحدودة، وتظل الأجزاء الإضافية محملة كحزم مؤجلة عند الحاجة فقط دون أي تسريب في الحزمة الرئيسية.

## ٣. الخصائص الفرعية (Sub-features)

| Sub-feature | Detail |
|---|---|
| `AppShell` Space Recovery (< 360 px) | Fix title collapse and overlap at 320 px: `SealTab` width `54 dp` (from `64 dp`), title typography `size: 15` (`maxLines: 2`, `height: 1.15`), and language toggle moved to `_AppDrawer` on subpages with Back (`showBack && width < 360`), guaranteeing `>= 130 dp` title width. Verified via `FontLoader` geometry in `test/accessibility_test.dart` (`!titleRect.overlaps(sealRect)` with `>= 6 dp` gap). |
| Landscape Restraint (Height < 420 px) | On short viewports (such as 740×360 px landscape), hide both `InstallBanner` and `TopUtilityBar` to maximize viewport reading area. |
| Katameros Reader Scaling (`/readings/:date`) | Replace fixed `148 dp` `toolbarHeight` with dynamic `SliverToBoxAdapter` header. Scope header controls to `TextScaler.linear(scale.clamp(1.0, 1.5))` and body verses to `TextScaler.linear((osScale * readerScale).clamp(0.85, 2.5))` to prevent runaway 4.0x text scaling. |
| Modal Bottom Sheets Keyboard Padding | All modal bottom sheets (`ReminderSheet`, `ApkInstallGuide`, `UpdateSheet`) enforce `MediaQuery.viewInsetsOf(context).bottom` padding, responsive button stacking via `LayoutBuilder`, and `isScrollControlled: true` on multi-step content. |
| Deferred Load Failure Resilience | Wrap deferred `loadLibrary()` invocations in `ErrorReporting.capture(e, st, section: 'deferred_chunk', source: ...)` across `app_shell.dart`, `install_banner.dart`, `remind_me.dart`, `notifications_page.dart`, and `router.dart`. |
| Bundle Guard & Budget Enforcement | `tool/check_web_bundle.mjs` verifies `main.dart.js.map` contains zero leaked symbols from all 8 deferred modules, and enforces `gzip -9 <= MAIN_JS_GZ_MAX` (`1,396,031 B`). |
| Non-Blocking Lighthouse Audit | Lighthouse audit in `deploy.yml` runs against preview channel with `continue-on-error: true` (0 extra Hosting channels). |

## ٤. الشاشات وأسطح Phase 2 (Surfaces Matrix)

1. **`AppShell` (`lib/ui/widgets/app_shell.dart`):** Top app bar, seal tab, title spacing, drawer language item, landscape height gating.
2. **`HomePage` (`lib/ui/pages/home_page.dart`):** Hero, announcement banner, next mass, quick contacts, directory cards, map.
3. **`ReadingsPage` (`lib/ui/pages/readings_page.dart`):** Katameros reader header reflow, date selector, font scale controls, body text scaling.
4. **`NotificationsPage` (`lib/ui/pages/notifications_page.dart`):** Preferences toggles, web push setup card, quiet hours, inbox list, OEM banner.
5. **`NotificationHealthPage` (`lib/ui/pages/notification_health_page.dart`):** OEM diagnostic tiles, step cards, action buttons.
6. **`InstallBanner` (`lib/ui/widgets/install_banner.dart`):** Bottom/docked banner, landscape restraint, responsive button column reflow.
7. **`ApkInstallGuide` (`lib/ui/widgets/apk_install_guide.dart`):** 5-step modal, scroll controlled, keyboard insets padding.
8. **`UpdateBanner` & `UpdateSheet` (`lib/ui/widgets/update_banner.dart`, `update_sheet.dart`):** Update bar, progress bar, release notes modal.
9. **`RemindMeButton` & `ReminderSheet` (`lib/ui/widgets/remind_me.dart`, `lib/ui/widgets/reminder_sheet.dart`):** Weekly reminder modal, clamped leads, calendar buttons.
10. **`AppAndNotificationsScreen` (`lib/ui/admin/notifications_admin.dart`):** Admin notifications manager, scheduled rows list, template editor.

## ٥. تكلفة البيانات والقواعد (Data / rules cost)

- **Firestore reads:** +0
- **Firestore writes:** +0
- **Firestore listeners:** +0
- **Firestore security rules expressions:** +0

## ٦. الملفات المعدلة (Files to Touch)

### Code:
- `lib/ui/widgets/app_shell.dart`
- `lib/ui/widgets/install_banner.dart`
- `lib/ui/widgets/remind_me.dart`
- `lib/ui/widgets/reminder_sheet.dart`
- `lib/ui/widgets/apk_install_guide.dart`
- `lib/ui/widgets/deferred_loader.dart`
- `lib/ui/widgets/update_banner.dart`
- `lib/ui/widgets/update_sheet.dart`
- `lib/ui/pages/readings_page.dart`
- `lib/ui/pages/notifications_page.dart`
- `lib/ui/pages/notification_health_page.dart`
- `lib/ui/admin/notifications_admin.dart`
- `lib/router.dart`

### Tooling & CI:
- `tool/check_web_bundle.mjs`
- `.github/workflows/ci.yml`
- `.github/workflows/deploy.yml`

### Tests:
- `test/accessibility_test.dart`
- `test/deferred_loader_test.dart`
- `test/install_banner_test.dart`
- `test/android_shell_test.dart`

### Documentation:
- `docs/plans/phase2/PR-E-responsive-size-audit.md`
- `docs/plans/phase2/STATUS.md`
- `docs/memory-bank/03-architecture.md`
- `docs/memory-bank/06-features.md`
- `docs/memory-bank/08-dev-workflow.md`
- `docs/memory-bank/10-decisions-and-history.md`
- `documentation/features/accessibility.md`
- `documentation/features/performance-pagespeed.md`
- `documentation/operations.md`
- `documentation/en/operations.md`

## ٧. الحزم (Packages)

No new dependencies added to `pubspec.yaml`. Tooling uses existing Node.js built-ins (`fs`, `zlib`, `child_process`).

## ٨. خطوات التنفيذ (Step-by-step Execution)

1. **Slice 1A (Navigation Chrome, Space Recovery & Resilience):**
   - Implement `AppShell` < 360 px space recovery (`SealTab` 54 dp, `appShort` 15 pt 2-line height 1.15, language toggle in drawer on narrow subpages).
   - Implement landscape < 420 px restraint in `AppShell` and `InstallBanner`.
   - Wrap `InstallBanner` buttons in `LayoutBuilder` for narrow reflow.
   - Wire `ErrorReporting.capture(..., section: 'deferred_chunk')` on `loadLibrary()` in `app_shell.dart`, `install_banner.dart`, `remind_me.dart`, `deferred_loader.dart`, `router.dart`, and `notifications_page.dart`.
2. **Slice 1B (Phase 2 Surfaces Responsive Reflow & Modals):**
   - Refactor `readings_page.dart` header to `SliverToBoxAdapter` with clamped text scalers.
   - Add `MediaQuery.viewInsetsOf(context).bottom` soft-keyboard padding and `isScrollControlled: true` across all bottom sheets.
   - Reflow `notifications_admin.dart` for 320 px / 390 px viewports.
3. **Slice 1C (Bundle Verification & Documentation):**
   - Update `tool/check_web_bundle.mjs` with 8-module AST/sourcemap verification and `gzip -9 <= 1,396,031 B` threshold.
   - Extend `test/accessibility_test.dart` with FontLoader geometry assertions and extremal viewport sweeps.
   - Update documentation across `docs/` and `documentation/`.

## ٩. الاختبارات (Tests)

- Geometry assertion in `test/accessibility_test.dart`: `titleRect.overlaps(sealRect) == false` with `>= 6 dp` horizontal clearance at 320 px (ar, en, with/without Back).
- Extremal viewport sweep: 320 px (2.0x scale), 390 px, 740×360 px (landscape), 1024 px, 1400 px with 0 `FlutterError` exceptions.
- Deferred chunk load error handling tested with thrown exceptions captured by Sentry fake.
- Bundle check tool tested against actual production web build output.

## ١٠. الاختبار اليدوي (Manual QA)

- Chrome DevTools device mode: 320 px (Galaxy Fold), 375 px (iPhone SE), 390 px (iPhone 13/14), 740×360 px (landscape), 768 px (iPad Mini), 1024 px (iPad Pro), 1400 px (Desktop).
- Arabic (RTL) and English (LTR) inspection on Holy Week and Golden Hour themes.
- Modal bottom sheet verification with virtual keyboard invoked.

## ١١. CI

- `ci.yml`: `check_web_bundle` step runs immediately following `flutter build web --release`.
- `deploy.yml`: Non-blocking Lighthouse audit against `pr-<n>` preview channel (`continue-on-error: true`).

## ١٢. التوثيق (Docs / ADR)

- `ADR-061` recorded in `docs/memory-bank/10-decisions-and-history.md`.
- `documentation/features/accessibility.md` and `performance-pagespeed.md` updated with breakpoint rules, font decisions, and bundle budgets.

## ١٣. المخاطر والحلول (Risks & Mitigations)

| Risk | Mitigation |
|---|---|
| Font subsetting corrupting Arabic shaping or Katameros tashkeel | Subsetting dropped completely; APKs already well under budget (~15 MB). |
| Flaky PNG golden tests in CI | Replaced with deterministic `FontLoader` geometry rect calculations. |
| Inadvertent code leaks into `main.dart.js` | Automated sourcemap scanner in `tool/check_web_bundle.mjs` fails build on any leaked symbol. |
| Accidental reverse-merge of `dev` | Strict git lineage locked to `feat/p2d-web-push` + `origin/fix/mobile-chrome-perf` (`ADR-062`). |

## ١٤. ما يفعله المالك (Owner steps)

None. Everything is automated and validated via CI and local tests.
