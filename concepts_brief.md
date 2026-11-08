# Unified Mobile Experience, Performance Hardening & Navigation Chrome De-Duplication

* **Author:** Kerollos
* **Date:** 2026-11-08

## Overview

The mobile Android experience for the parish portal currently exhibits three visible quality and performance defects:
1. **Home Screen APK Frame Drops & GPU Jank:** In `lib/ui/widgets/golden.dart`, `HeroStage` runs an unconstrained 60-second continuous `AnimationController` (`_clock.repeat()`). While the Web platform offloads haze and ray shimmer to hardware-accelerated CSS DOM layers (`HeroAmbientLayer`, ADR-037), on the mobile Android APK (`!kIsWeb`), Flutter drives Ken Burns continuous scaling, `_HazeDrift` cloud repaints, and an expensive `LightRaysPainter` with `MaskFilter.blur` on every frame at 60/120 Hz. This exhausts mobile CPU/GPU budgets and induces visible opening lag and scroll stutter on the Home screen.
2. **Jarring White Flash at App Launch:** The Android native launch drawable (`launch_background.xml` in `android/app/src/main/res/drawable/` and `drawable-v21/`) is hardcoded to `@android:color/white` and `?android:colorBackground` (`#FFFFFF`). On cold start, Android displays a stark white window for 1–2 seconds while Flutter and Firebase bootstrap before painting the church's warm cream wash (`#FBF3E4`), causing an abrupt, unbranded white flicker.
3. **Stacked Navigation Chrome & Double Back Arrows:**
   * In `ItemDetailPage` (`lib/ui/pages/item_detail_page.dart`), `AppShell` already provides an `AppBar` with a leading `arrow_back_rounded` icon on mobile (`showBack = !wide && location != '/'`). Inside the content body, `ItemDetailPage` redundantly renders `_BackLink(parent: parent)`, creating two vertically stacked back arrows within 120 pixels on mobile viewports.
   * In `NotificationHealthPage` (`lib/ui/pages/notification_health_page.dart`, `/notifications/battery`), the page is routed inside `ShellRoute` (so `AppShell`'s `AppBar` is already present), but the page introduces a nested `Scaffold` with a custom `Container` top bar and a second back button and title, creating stacked app bars and duplicate back navigation.
   * In `AppShell` (`lib/ui/widgets/app_shell.dart`), `parentRouteOf('/notifications/battery')` currently defaults to `'/'` instead of returning `/notifications`.

## Analysis

The 7-lens Goldfish review (`egm-design`, `egm-codebase-details`, `egm-zoom-out`, `egm-comprehension`, `egm-implementation-readiness`, `egm-structural`, and `egm-inventive-catalyst`) evaluated the problem space and established the following technical resolutions:

### 1. Platform-Gated Ambient Animation Throttling (`!kIsWeb` only)
* **The Contradiction:** Ethereal golden-hour aesthetics require shimmering light rays and moving haze, but low-end Android mobile GPUs experience dropped frames and thermal throttling under continuous canvas repaints.
* **Resolution (TRIZ Principle 2 - Separation & Principle 19 - Periodic/Static Action):**
  * Detect the mobile runtime via `bool get _isMobileApk => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;`.
  * On mobile APK, stop the continuous `_clock.repeat()` loop for ambient motion. Render the hero painting statically without Ken Burns scaling, omit `_HazeDrift`, and render `LightRaysPainter` statically using `HeroAmbientSpec.stillShimmer` without `AnimatedBuilder`.
  * The Web platform (`kIsWeb`) remains 100% untouched, continuing to run full CSS-animated DOM layers (`HeroAmbientLayer`).
  * This drops idle GPU canvas repaints to zero on Android, eliminating frame drops during Home screen scrolling and opening.

### 2. Native Android Splash Screen Color Continuity
* **The Contradiction:** Flutter and Firebase bootstrap operations require 500ms–1500ms before first paint, but displaying a blank white OS window creates a jarring visual flash.
* **Resolution (TRIZ Principle 10 - Prior Action):**
  * Define `<color name="splash_cream">#FBF3E4</color>` in `android/app/src/main/res/values/colors.xml`.
  * Update `launch_background.xml` (both `drawable/` and `drawable-v21/`) to replace `@android:color/white` and `?android:colorBackground` with `@color/splash_cream`.
  * Update `LaunchTheme` and `NormalTheme` in `android/app/src/main/res/values/styles.xml` to use `@color/splash_cream` for `android:windowBackground`.
  * The native OS window displays the exact liturgical cream wash with the centered parish seal from frame zero, eliminating startup flicker.

### 3. Unified Navigation Chrome & Sub-Screen De-Duplication
* **The Contradiction:** Deep detail pages need a clear mechanism to return to parent listings, but duplicating back buttons inside the body clutters mobile screens and confuses screen readers.
* **Resolution (TRIZ Principle 5 - Merging & Principle 6 - Universality):**
  * **Enforce Single Scaffold Invariant (`INV-NAV-01`):** `AppShell` is the sole `Scaffold` provider for all public routes. Remove the nested `Scaffold` and custom top bar from `NotificationHealthPage`, converting it to standard `PageBody` + `PageHeader`.
  * **Enforce Single Back Arrow Invariant (`INV-NAV-02`):** `AppShell.leading` is the sole back arrow on mobile (`!wide`). In `ItemDetailPage`, render `_BackLink` only on desktop (`if (wide) _BackLink(...)`), eliminating the duplicate arrow on mobile viewports while preserving desktop breadcrumbs.
  * **Route Hierarchy Mapping:** Update `parentRouteOf` in `AppShell` so `/notifications/battery` navigates up to `/notifications`.

## Goals vs. Non-Goals

* **In-Scope Goals:**
  * Disable continuous ambient canvas animation tickers in `HeroStage` exclusively on mobile APK (`!kIsWeb && defaultTargetPlatform == TargetPlatform.android`), achieving smooth 60–120 FPS Home screen scrolling.
  * Brand the native Android launch screen with `#FBF3E4` (`@color/splash_cream`) and centered parish seal across `launch_background.xml` and `styles.xml`.
  * Remove `_BackLink` on mobile viewports in `ItemDetailPage` (`lib/ui/pages/item_detail_page.dart`).
  * Remove the nested `Scaffold` and duplicate top bar in `NotificationHealthPage` (`lib/ui/pages/notification_health_page.dart`), adopting `PageBody` + `PageHeader`.
  * Update `parentRouteOf` in `AppShell` (`lib/ui/widgets/app_shell.dart`) to route `/notifications/battery` to `/notifications`.

* **Out-of-Scope Non-Goals:**
  * Modifying Web animations (Web retains full CSS DOM animations).
  * Changing Firestore schemas, `firestore.rules`, or `/admin` fields (`+0` rules expressions).
  * Altering bottom sheet navigation or dialog flows.

## Alternatives Weighed

* **Removing the main AppBar from Home on mobile:** Rejected by author: the main AppBar must remain intact across the app to preserve the drawer menu access, language switch, and parish seal tab.
* **Removing all back buttons from both AppBar and body:** Rejected by review: leaves standalone PWA deep links stranded with no parent navigation, forcing users through Home or the drawer.
* **Keeping continuous Ken Burns scale on mobile APK with lower frame rate:** Rejected by review: any active ticker triggers continuous canvas repaints on Flutter, preventing the raster thread from sleeping during idle or scroll.
* **Using a Flutter splash package (`flutter_native_splash`):** Rejected by review: unnecessary third-party dependency; the native Android drawable and styles configuration can be updated directly via standard Android XML resources in minutes without code bloat.

## Key Decisions & Staging for Next Steps

1. **Architecture & Scope Sealing:**
   * `INV-NAV-01`: Only `AppShell` manages `Scaffold` chrome for routed public pages.
   * `INV-NAV-02`: Exactly one back arrow on mobile viewports, located in `AppShell.leading`.
   * `INV-PERF-01`: Zero continuous ambient tickers on mobile Android APK (`!kIsWeb`).
   * `INV-SPLASH-01`: Native Android launch window background locked to `#FBF3E4`.
2. **Next Steps:**
   * Review brief with author.
   * Transition to implementation via standard Hark Workflow cycle on feature branch.
