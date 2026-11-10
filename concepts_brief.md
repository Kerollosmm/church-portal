# Phase 2 PR E: Responsive Layout Polish, Deferred Bundle Guard & Size Audit (`ADR-061`)

* **Author:** Kerollos
* **Date:** 2026-11-09

## Overview

Phase 2 PR E (`fix/p2e-responsive-size`, `ADR-061`) is the final pull request in the Phase 2 notifications and mobile apps chain for the Asafra Church Portal, updating and executing [`PR-E-responsive-size-audit.md`](file:///c:/Users/Kerollos/church-portal/docs/plans/phase2/PR-E-responsive-size-audit.md). Parishioners read daily liturgical scriptures, browse service schedules, install the Android APK or iPhone Web App, and manage reminders on phones as narrow as 320 px wide—often with operating system font scaling turned up to 200% in Arabic (right-to-left) or English (left-to-right).

The original PR E plan (written on 2026-11-06 before PRs A–D and `ADR-062` were built) predates seven deferred web modules, the Katameros daily reader (`/readings/:date`), the battery health guide (`/notifications/battery`), the expanded web-push notifications page (`/notifications`), the in-app APK updater (`UpdateBanner` and `UpdateSheet`), and the single-back-arrow navigation changes in `ADR-062`. This brief aligns PR E with the actual post-PR-D codebase at zero additional Firestore read, write, or listener cost on the Firebase Spark plan.

Reviewer status across all seven parallel `flash` Goldfish lenses:
- `egm-design`: completed
- `egm-codebase-details`: completed
- `egm-zoom-out`: completed
- `egm-comprehension`: completed
- `egm-implementation-readiness`: completed
- `egm-structural`: completed
- `egm-inventive-catalyst`: completed

## Analysis

### 1. Branch Lineage Hazard: Never Reverse-Merge `dev` into the Stacked Chain (Blocker)
Six independent review lenses flagged a blocker in the proposed git setup ("merge `dev` at `ea7cbe9` into `feat/p2d-web-push`, then branch `fix/p2e-responsive-size`"):
- Per [`08-dev-workflow.md`](file:///c:/Users/Kerollos/church-portal/docs/memory-bank/08-dev-workflow.md), `dev` is a one-way preview integration branch that must never be merged into `main` or into branches destined for `main`.
- `dev` (`ea7cbe9`) contains unrelated commits outside the Phase 2 PR stack (`chore/hark-workflow-v2` `3923f3f`, `docs/hark-memory-export` `78782ce`, and unsquashed integration merges). Merging `dev` into `feat/p2d-web-push` (open PR `#56`, whose base is `feat/p2c-notification-manager` `#55`) pollutes PR `#56`'s diff with dozens of out-of-scope files, triggers automated review bot churn, and causes merge conflicts when squash-merging bottom-up into `main` ([`HANDOFF.md`](file:///c:/Users/Kerollos/church-portal/docs/plans/phase2/HANDOFF.md#L138-L158)).
- **Clean resolution**: `origin/fix/mobile-chrome-perf` (`ADR-062`) is only two isolated commits (`d410ad9` and `58d8239`) branched off `feat/p2b-android-local-notifications`. Never merge `dev` into feature branches. Either:
  1. Propagate `origin/fix/mobile-chrome-perf` (`58d8239`) upward cleanly (`feat/p2c-notification-manager` -> `feat/p2d-web-push` -> branch `fix/p2e-responsive-size`), or
  2. Branch `fix/p2e-responsive-size` directly from `feat/p2d-web-push` (`5439216`) and merge `origin/fix/mobile-chrome-perf` (`58d8239`) into `fix/p2e-responsive-size` (then merge `fix/p2e-responsive-size` forward into `dev` only for preview channel testing, while merging the PR stack bottom-up directly into `main`).

### 2. Contradiction: Compounding 4.0x Font Scale & Fixed Header Height on `/readings/:date` (Blocker)
- **Technical contradiction**: Elderly parishioners need both operating-system accessibility text scaling (up to `2.0x`) and the in-app Katameros scripture size control (`0.85x`–`2.0x`), yet combining them inside [`readings_page.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/pages/readings_page.dart#L501-L504) breaks layout containment at 320 px.
- **Concrete defects found**:
  1. `_buildKatamerosTab` (line 501) puts the 3-row `_buildHeader` inside `SliverAppBar(toolbarHeight: 148)`. At `1.3x`–`2.0x` OS text scale on 320 px, the header grows to 180–220 dp and throws a vertical `RenderFlex` overflow inside Flutter's `NavigationToolbar`, while `_buildControlsRow` (lines 425–489) overflows horizontally across 288 dp usable width.
  2. Scripture body styles (lines 610, 679, 695, 710, 724, 737) multiply `fontSize` by `readingTextScaleProvider` (`0.85`–`2.0`) while Flutter's ambient `MediaQuery.textScalerOf(context)` multiplies `fontSize` a second time—producing up to **4.0x (`58 pt`)** text.
- **Inventive patterns applied (`Extraction` + `Dynamics`)**:
  - Extract `_buildHeader` out of the fixed `148 dp` `SliverAppBar.title` into an intrinsic-height `SliverToBoxAdapter` (or dynamic header delegate), and switch `_buildControlsRow` to `Wrap` below 360 px.
  - Scope UI chrome controls to `ambientScaler.clamp(maxScaleFactor: 1.5)` and compute scripture body scaling once as `TextScaler.linear((osScale * readerScale).clamp(0.85, 2.5))` instead of double-multiplying `fontSize`.
  - *Secondary trade-off*: Wrapping the scripture body in an explicit `MediaQuery` subtree creates an intentional size difference between capped toolbar controls (`<= 1.5x`) and body verses (`<= 2.5x`).

### 3. Contradiction: Parish Seal Prominence vs. 320 px Subpage Title Visibility in `AppShell` (Blocker)
- **Concrete defects found in [`app_shell.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/app_shell.dart#L237-L283)**:
  1. Arithmetic gap bug: `SealTab` ends at `tabStart + tabW` (`70.0` on Home, `118.0` on subpages with Back), whereas the title text starts at `titleSpacing + tabSpace` (`72.0` on Home, `120.0` on subpages)—leaving only **2.0 dp** nominal clearance before Arabic/Latin glyph overhang collides with the seal tab.
  2. Silent title disappearance: `if (c.maxWidth < tabSpace + 70) return SizedBox(width: c.maxWidth.clamp(0, tabSpace));` collapses the church title into an empty box whenever `c.maxWidth < 142 dp`. On a 320 px subpage (Back `48 dp` + actions `~102 dp` = `170 dp` remaining; `170 < 72 + 70` once actions or padding grow), the title vanishes or truncates to a few letters.
- **Inventive patterns applied (`Dynamics` + `Segmentation`)**:
  - Compute `tabSpace` directly from geometry: `(tabStart + tabW + 6.0) - (leadingWidth + titleSpacing)`.
  - Below `360 px` width: reduce `appShort` title font size from `17` to `15` (`maxLines: 2`, `height: 1.15`), narrow `tabW` slightly (for example `54`–`56 dp` instead of `64 dp` on ultra-narrow viewports) or move the `EN/ع` bar button to the end drawer when `showBack && width < 360` (matching the existing `collapseHighlights` precedent at line 199) so the church title keeps >= 130 dp of readable width and never collapses to an empty box.
  - Verify geometry deterministically in widget tests by loading actual font files via `FontLoader` and asserting `!titleRect.overlaps(sealRect)` with >= 6 dp horizontal gap and `titleRect.width >= 80`, avoiding OS-dependent PNG golden diffs.
  - *Secondary trade-off*: If the `EN/ع` button moves to the drawer on `< 360 px` subpages, switching language on a 320 px subpage takes two taps instead of one (it remains one tap on Home and on `>= 360 px` screens).

### 4. Bottom Sheets, Soft Keyboards, and Landscape Chrome Compression (Major)
Codebase inspection uncovered concrete responsive defects across Phase 2 banners and sheets:
- **Landscape viewport saturation (`height < 420`, e.g. `740 x 360`)**:
  - [`install_banner.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/install_banner.dart#L106-L155) has no `height < 420` check, covering > 55% of landscape phone height; its action row (lines 331–345) also uses an unwrapped `Row` that overflows at 320 px x 200% text scale.
  - Even after hiding `InstallBanner` at `height < 420`, stacking `TopUtilityBar` (`~32 dp`) + `AppBar` (`64 dp`) + `UpdateBanner` (`~48 dp`) + `LiveStreamBanner` (`~40 dp`) in [`app_shell.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/app_shell.dart#L349-L405) consumes 184 dp (> 51% of a 360 dp landscape viewport). Collapsing `TopUtilityBar` alongside `InstallBanner` when `height < 420` reclaims vertical reading space.
- **Bottom sheet clipping and keyboard collision**:
  - [`apk_install_guide.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/apk_install_guide.dart#L409-L415): `_showInstallSteps` (browser/iOS install guide) omits `isScrollControlled: true`, capping the sheet at 56% of screen height and clipping steps. Meanwhile `_ApkInstallGuideSheet` (lines 174–188) nests an inner `SingleChildScrollView` inside a fixed `SizedBox(height: 380)` `PageView` inside an outer `SingleChildScrollView`, causing scroll contention and overflow on short viewports.
  - [`update_banner.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/update_banner.dart#L356-L358) (`UpdateSheet`, plus unwrapped dual buttons in `permissionNeeded` at lines 540–560) and [`reminder_sheet.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/reminder_sheet.dart#L173) (opened from [`remind_me.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/remind_me.dart), not `remind_me_button.dart`) omit `MediaQuery.viewInsetsOf(context).bottom` padding.
- **Silent deferred-chunk load errors**:
  - [`install_banner.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/install_banner.dart#L234-L241) and [`app_shell.dart`](file:///c:/Users/Kerollos/church-portal/lib/ui/widgets/app_shell.dart#L163) swallow `loadLibrary()` exceptions with `catch (_)`. If a new deploy invalidates `.part.js` chunk hashes while a visitor has an older tab open, tapping the install guide fails silently with zero Sentry trace. Routing `loadLibrary()` failures through `ErrorReporting.capture(..., section: 'deferred_chunk')` (honoring `ADR-034` privacy rules) surfaces chunk-skew errors immediately.

### 5. Contradiction: Minified Web Release Bundle vs. Exact Deferred-Chunk Leak Detection (Major)
- **Technical contradiction**: `dart2js` minifies symbol names and emits numbered `main.dart.js_*.part.js` files in release builds, making naive string greps brittle, yet relying solely on `MAIN_JS_GZ_MAX` (`1,400,000 B`) misses smaller eager-import leaks (`15`–`25 KB`) and gives no actionable filename when a budget check fails.
- **Inventive pattern applied (`Intermediary` leveraging existing `--source-maps`)**:
  - [`ci.yml`](file:///c:/Users/Kerollos/church-portal/.github/workflows/ci.yml#L46) **already builds web with `--source-maps`**, generating `build/web/main.dart.js.map` at zero additional build time.
  - A small Node script (`tool/check_web_bundle.mjs`, tested via `node --test`) parses `build/web/main.dart.js.map`'s `sources` array in < 100 ms to assert:
    1. `gzip -9` byte size of `build/web/main.dart.js` is within `MAIN_JS_GZ_MAX` (defaulting to the Phase 2 ceiling `1,396,031 B` = `1,334,591 B` baseline + `60 KB`, overridable per step).
    2. `*.part.js` chunks exist on disk.
    3. Zero source URIs ending in the 8 deferred module files (`admin_page.dart`, `assistant_page.dart`, `notifications_page.dart`, `readings_page.dart`, `notification_health_page.dart`, `apk_install_guide.dart`, `web_push_repository.dart`, `reminder_sheet.dart`) appear inside `main.dart.js.map`—printing the exact leaked Dart file path if violated.
  - *Secondary trade-off*: Requires `--source-maps` on the CI build step (already enabled in `ci.yml` line 46) and maintaining the 8-item deferred entry list in `tool/check_web_bundle.mjs`.

### 6. Contradiction: Exhaustive Breakpoint/Theme Coverage vs. 30-Minute CI Timeout (Major)
- **Technical contradiction**: Sweeping 11 widths x 3 text scales x 2 locales x 7 occasion palettes x ~18 routes/modals (~8,300 widget settle passes) exceeds the 30-minute timeout in [`ci.yml`](file:///c:/Users/Kerollos/church-portal/.github/workflows/ci.yml#L15).
- **Inventive pattern applied (`Segmentation` + `Preliminary Action`)**:
  - Keep all blocking responsive tests inside the existing `flutter test` step (extending [`accessibility_test.dart`](file:///c:/Users/Kerollos/church-portal/test/accessibility_test.dart) rather than spawning separate CI jobs that re-compile test binaries), testing the **extremal boundary hull**:
    - `320 x 640 @ 2.0x` (AR RTL and EN LTR) across all legacy + Phase 2 routes (`/`, `/notifications`, `/notifications/battery`, `/readings/2026-11-09`, etc.) and Phase 2 modal sheets (`UpdateSheet`, `ReminderSheet`, `ApkInstallGuide`, browser install steps, simulated `viewInsets.bottom = 280`).
    - `740 x 360 @ 1.0x` landscape height guard (`InstallBanner` renders zero height).
    - `390 x 844 @ 1.0x` & `1.3x` for admin `AppAndNotificationsScreen` (`notifications_admin.dart`).
    - `1024 x 768` and `1440 x 900` desktop breakpoint checks.
    - Pure-Dart contrast math across all **7 occasion palettes** (`goldenHour`, `holyWeek`, `resurrection`, `nativity`, `epiphany`, `fasting`, `marian`) executing in milliseconds.
  - Keep exhaustive 11-width sweeps and Lighthouse / PageSpeed runs (`treosh/lighthouse-ci-action` with `continue-on-error: true` against the existing `pr-<n>` URL in [`deploy.yml`](file:///c:/Users/Kerollos/church-portal/.github/workflows/deploy.yml#L263-L266), consuming **zero** extra Firebase Hosting preview channels out of the 10-channel Spark quota) strictly informational/non-blocking.
  - *Secondary trade-off*: Non-extremal intermediate combinations (such as `820 px @ 1.3x` on a secondary theme) run in tagged local sweeps rather than blocking every PR push.

### 7. Ideal Final Result (IFR)
Every legacy and Phase 2 screen, banner, and bottom sheet renders without overflow, clipping, or broken Arabic diacritics from 320 px at 200% text scale up to 1920 px, while deterministic source-map and extremal-viewport gates catch regressions in under 90 seconds of CI time at +0 Firestore cost.

## Goals vs. Non-Goals

* **In-Scope Goals:**
  - Rewrite [`PR-E-responsive-size-audit.md`](file:///c:/Users/Kerollos/church-portal/docs/plans/phase2/PR-E-responsive-size-audit.md) and [`STATUS.md`](file:///c:/Users/Kerollos/church-portal/docs/plans/phase2/STATUS.md) to reflect post-PR-D + `ADR-062` reality, removing all font-subsetting directives.
  - Fix `AppShell` 320 px title/seal-tab/back-arrow spacing and prevent silent title disappearance on narrow subpages.
  - Fix `ReadingsPage` (`/readings/:date`) fixed `148 dp` `SliverAppBar` overflow, narrow controls wrapping, and 4.0x compounded text-scale explosion.
  - Enforce `height < 420` landscape hiding on `InstallBanner` (and narrow-width CTA wrapping) plus landscape chrome restraint.
  - Fix bottom-sheet `isScrollControlled`, `viewInsets.bottom` keyboard padding, and narrow button wrapping across `ApkInstallGuide` (`_ApkInstallGuideSheet` + `_showInstallSteps`), `UpdateSheet`, and `ReminderSheet` (`remind_me.dart` + `reminder_sheet.dart`).
  - Report deferred `loadLibrary()` chunk failures via `ErrorReporting.capture` instead of silent `catch (_)`.
  - Add hard-blocking `tool/check_web_bundle.mjs` (`MAIN_JS_GZ_MAX` + `main.dart.js.map` deferred-chunk leak check) to `ci.yml` and extremal Phase 2 viewport/sheet/landscape assertions to `test/accessibility_test.dart`.
  - Add non-blocking Lighthouse / PageSpeed preview check on the existing `pr-<n>` URL in `deploy.yml` (`continue-on-error: true`, zero extra Hosting channels).
  - Synchronous docs in the same PR: `docs/memory-bank/` (`03`, `06`, `08`, `10` with `ADR-061`, `11`), Arabic `documentation/`, and `documentation/en/`.

* **Out-of-Scope Non-Goals:**
  - Subsetting or modifying `assets/fonts/*.ttf` (`pyftsubset` / `tool/subset_fonts.sh` dropped).
  - Committing cross-platform PNG golden screenshots to git.
  - Any Firestore schema, security rules, seed data, Cloud Functions, or Cloudflare Worker changes (+0 Firestore reads/writes/listeners).
  - Changing the Home hero artwork, motion, or introducing non-palette / violet colors.

## Alternatives Weighed

- **Subset `assets/fonts/*.ttf` with `pyftsubset` (`tool/subset_fonts.sh`)**: Rejected by author and all 7 review lenses. Dynamic Katameros readings (`/readings/:date`) use full biblical Arabic tashkeel and Coptic loanwords, and PR C allows arbitrary admin push text; static glyph subsetting risks corrupting OpenType `GSUB`/`GPOS` mark positioning while saving only ~240 KB gzip on cached web assets and ~0.5 MB on APKs that already sit ~5 MB below the 20 MB cap in [`android.yml`](file:///c:/Users/Kerollos/church-portal/.github/workflows/android.yml#L41-L45).
- **Merge `dev` (`ea7cbe9`) directly into `feat/p2d-web-push` before branching PR E**: Rejected during Goldfish review (`egm-design`, `egm-codebase-details`, `egm-zoom-out`, `egm-comprehension`, `egm-implementation-readiness`, `egm-structural`). Violates [`08-dev-workflow.md`](file:///c:/Users/Kerollos/church-portal/docs/memory-bank/08-dev-workflow.md) and pollutes PR `#56` with `dev`-only commits (`chore/hark-workflow-v2`, `docs/hark-memory-export`, unsquashed merges).
- **Grep minified `build/web/main.dart.js` for Dart class names to detect deferred leaks**: Rejected (`egm-inventive-catalyst`, `egm-zoom-out`). `dart2js` minifies identifiers in `--release` mode; inspecting `build/web/main.dart.js.map` `sources` (already emitted by `ci.yml` `--source-maps`) is fast and minification-proof.
- **Run full Cartesian matrix (11 widths x 3 scales x 2 locales x 7 themes x 18 surfaces) on every CI push**: Rejected (`egm-design`, `egm-inventive-catalyst`, `egm-zoom-out`). Over 8,000 widget pumps risks exceeding `ci.yml`'s 30-minute timeout; extremal boundary testing inside `flutter test` catches overflow geometry in < 90 seconds.
- **Commit raster PNG goldens in `test/goldens/`**: Rejected (`egm-zoom-out`, `egm-structural`). Cross-OS font rasterization differences make PNG goldens flaky across Windows/macOS/Linux and skipped on CI; deterministic `tester.getRect` bounding-box assertions with `FontLoader` run on every CI commit.

## Key Decisions & Staging for Next Steps (Locked by Author on 2026-11-09)

1. **Git Lineage & Branching (Locked)**: Branch `fix/p2e-responsive-size` directly from `feat/p2d-web-push` (`5439216`) and merge `origin/fix/mobile-chrome-perf` (`58d8239`, `ADR-062`) directly into `fix/p2e-responsive-size`. Never reverse-merge `dev`. Keep bottom-up stack intact (`#55` PR C -> `#56` PR D -> PR E -> `dev` preview only / `main`).
2. **`AppShell` `< 360 px` Space Recovery (Locked)**: Narrow `SealTab` to `54 dp` below `360 px`, drop `appShort` title font to `15 pt` (`maxLines: 2`, `height: 1.15`), and move the `EN/ع` button into the end drawer (`_AppDrawer`) when `showBack && width < 360` so subpage titles keep `>= 130 dp` readable width without collapsing. Enforce geometry via `FontLoader` in `test/accessibility_test.dart`.
3. **Landscape `< 420 px` Restraint (Locked)**: Hide both `InstallBanner` and `TopUtilityBar` when `MediaQuery.sizeOf(context).height < 420`.
4. **Font Subsetting & Bundle Guard (Locked)**: Drop `pyftsubset` completely. Add `tool/check_web_bundle.mjs` inspecting `build/web/main.dart.js.map` `sources` for zero leaks of the 8 deferred modules and enforcing `gzip -9` byte size `<= MAIN_JS_GZ_MAX` (`1,396,031 B`).
5. **Readings, Bottom Sheets & Chunk Telemetry (Locked)**: Convert `/readings/:date` header to intrinsic height (`SliverToBoxAdapter`) with clamped `TextScaler` (UI chrome `<= 1.5x`, body verses `<= 2.5x`); enforce `isScrollControlled`, `viewInsets.bottom` padding, and narrow button wrapping across `ApkInstallGuide`, `UpdateSheet`, and `ReminderSheet`; route deferred `loadLibrary()` failures to `ErrorReporting.capture(..., section: 'deferred_chunk')`.
