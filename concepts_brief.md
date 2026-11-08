# APK Scroll Performance & Katameros Focus Reader

* **Author:** Kerollos
* **Date:** 2026-11-08

## Overview

Parishioners reading the daily Katameros lectionary and Verse of the Day on the Android APK face three connected issues:
1. **APK scroll and frame lag:** `ReadingsPage` (`lib/ui/pages/readings_page.dart`) eagerly builds every liturgical section and reading card inside a single `SingleChildScrollView` + `Column`, while `WarmBackdrop` (`lib/ui/widgets/golden.dart`) and `HeroVideo` (`lib/ui/widgets/hero_video_io.dart`) lack repaint isolation in key places.
2. **Cluttered reading environment without adaptive scroll:** `/readings/:date` stacks `AppShell`'s global chrome (`TopUtilityBar`, `AppBar`, `SealTab`, `UpdateBanner`, `LiveStreamBanner`, `InstallBanner`) on top of `ReadingsPage`'s own duplicate title bar, date bar, and tab bar. None of these bars hide when scrolling down to read.
3. **Day-navigation arrows vs. font resizing up to `2.0x`:** Currently, the `A−` / `A+` buttons sit in the middle of the date-switcher row (`readings_page.dart`, lines 220–275) where the date and day-navigation arrows belong, while font scaling is capped at `1.45x` and resets on exit. The date bar should use clear RTL-aware arrow icons to navigate through days, while font resizing is provided as a dedicated reader control supporting up to `2.0x` scale with device persistence.

## Analysis

All seven Goldfish review lenses (`egm-design`, `egm-codebase-details`, `egm-zoom-out`, `egm-comprehension`, `egm-implementation-readiness`, `egm-structural`, and `egm-inventive-catalyst`) audited the codebase and identified the technical constraints required to deliver these three improvements cleanly:

### 1. Distraction-Free Reading Environment without 60 Hz Shell Rebuilds
* **The Contradiction:** A focused reading environment requires hiding both the outer `AppShell` bars/banners (`TopUtilityBar`, `AppBar`, `SealTab`, `UpdateBanner`, `LiveStreamBanner`, `InstallBanner`) and the inner reading controls when the user scrolls down. However, streaming raw scroll pixel offsets into `AppShell` on every frame causes 60–120 Hz whole-shell rebuilds, detaches the absolute-positioned `SealTab` (`PositionedDirectional`), and risks leaving `AppShell` collapsed if the user navigates to another route.
* **Resolution:**
  1. **Remove duplicate static chrome:** Consolidate `ReadingsPage`'s duplicate top title bar ("قراءات اليوم" + second Back button) with the unified reader header so 56 dp of redundant chrome is eliminated immediately.
  2. **Damped boolean focus state for `AppShell`:** Use a route-scoped boolean provider (`readerFocusModeProvider`, active only when `location.startsWith('/readings/')` and automatically reset to `false` on route exit or dispose). Toggle it only when continuous scroll delta exceeds a $\ge 40\text{ dp}$ hysteresis threshold downward (enter focus mode) or upward (exit focus mode). `AppShell` animates its top bar, `SealTab`, and banners out/in via a single GPU-composited `AnimatedSlide` / `AnimatedSize` transition on direction change—zero widget rebuilds during ongoing scroll frames.
  3. **Native Sliver collapse for inner bars:** Place the date navigation bar and Katameros/Verse tab bar inside a `SliverAppBar(floating: true, snap: true)` inside `ReadingsPage`'s `CustomScrollView` so inner bars collapse and snap back via native sliver physics.

### 2. Dedicated Day-Navigation Arrows & `2.0x` Font Scaling
* **Day Navigation via Arrow Icons:**
  * Replace the current mixed bar (`< A− A+ >`) with a clean day-navigation bar containing RTL-aware previous-day and next-day arrow buttons (`Icons.arrow_back_rounded` / `Icons.arrow_forward_rounded`, minimum 48x48 dp touch targets) flanking the current Gregorian and Coptic date display (`$_currentIso • $coptic`), so tapping the arrows clearly navigates backward and forward through days.
* **Font Resizing up to `2.0x`:**
  * Move font resizing out of the center of the day-navigation arrows into a dedicated font-size control (e.g., an `Icons.format_size_rounded` button/pill in the reader header that opens a compact font-size slider/stepper from `0.85x` to `2.0x` with a percentage readout and one-tap `100%` reset, or a dedicated reader-controls row).
  * **Overflow protection at `2.0x` on 320 px screens:** Refactor `_buildReadingCard`'s header (title + scripture reference pill in `readings_page.dart`, lines 481–513) from a rigid `Row` to a `Wrap` (or column layout when scale $> 1.3\text{x}$ or width $< 360\text{ px}$) so scaling to `2.0x` never triggers `RenderFlex` overflow on 320 px viewports.
  * **Zero-flash persistence:** Pre-warm the saved font scale (`church_portal_reading_font_scale`, clamped to `[0.85, 2.0]`) at startup alongside `initLanguageStore()` and `initInstallStore()` in `main.dart`, and debounce writes to `shared_preferences` by 400 ms.

### 3. Lazy Sliver Virtualization & Targeted Repaint Isolation
* **Flattened `SliverList.builder`:** Convert the Katameros tab in `ReadingsPage` from `SingleChildScrollView` + `Column` to a `CustomScrollView` with a flattened list of sliver items (commemoration banner, section headers, individual reading cards, attribution footer) backed by `SliverList.builder`, deterministic `ValueKey`s, and `cacheExtent: 500`.
* **Scroll Offset Hygiene:** Reset the Katameros scroll offset to `0.0` when navigating to a previous or next day (`_shiftDay`), and keep the single-card Daily Verse tab in its own independent scroll viewport so switching tabs does not jump or desynchronize.
* **Targeted `RepaintBoundary` Placement:**
  * Wrap `WarmBackdrop` (`lib/ui/widgets/golden.dart`, line 66) in a `RepaintBoundary` so the full-screen cloud texture + `ColorFilter` is raster-cached once and never repainted during body scrolling.
  * Wrap the `VideoPlayer` inside `HeroVideo` (`lib/ui/widgets/hero_video_io.dart`, line 100) in a `RepaintBoundary` so 60 fps video frame decoding on the Home page does not dirty ancestor layers.
  * Leave `HeroStage`'s existing `RepaintBoundary` wrappers (`golden.dart`, lines 600, 633, 635) untouched to avoid redundant full-screen GPU texture allocations on low-RAM Android devices.

## Goals vs. Non-Goals

* **In-Scope Goals:**
  * Lazy sliver virtualization (`CustomScrollView` + `SliverList.builder`) for Katameros readings in `lib/ui/pages/readings_page.dart`.
  * Distraction-free adaptive scrolling on `/readings/:date` that hides outer `AppShell` chrome/banners (via a damped, route-scoped boolean focus state) and collapses inner reading bars (`SliverAppBar(floating: true, snap: true)`) on downward scroll, restoring them on upward scroll.
  * Clean day-navigation bar using RTL-aware arrow icons (`prevDayButton` / `nextDayButton`) with the date in between, replacing the misplaced `A−` / `A+` buttons.
  * Dedicated font-size resize feature supporting `0.85x` to `2.0x` normally, persisted in `shared_preferences` (`church_portal_reading_font_scale`, pre-warmed at startup), with `Wrap`-based reading card headers verified at 320 px width.
  * Targeted `RepaintBoundary` isolation on `WarmBackdrop` and `HeroVideo`.

* **Out-of-Scope Non-Goals:**
  * Firestore schema, `firestore.rules`, or `/admin` dashboard field changes (`+0` rules expressions).
  * Changes to `tool/fetch_readings.js` or background notification scheduling (`notify_plan.dart`).
  * Production Sentry performance tracing (kept off per ADR-034 / PDPL).

## Alternatives Weighed

* **Keeping `A−` / `A+` in the center of the date switcher row or replacing font buttons with arrows:** Rejected by author: the arrow icons in the bar are meant to navigate through days (previous/next day), while font resizing should be a proper resize control supporting up to `2.0x`.
* **Capping font scale at `1.5x`–`1.65x`:** Rejected by author: reading text must scale up to `2.0x` normally, solved by making reading card headers wrap cleanly at 320 px.
* **Collapsing only inner headers while leaving `AppShell` bars and banners pinned during reading:** Rejected by author: the reader needs a clean, distraction-free reading environment on scroll, achieved safely via a damped boolean focus state (`readerFocusModeProvider`) rather than per-pixel `AppShell` rebuilds.
* **Streaming raw `ScrollController` offsets into `AppShell` at 60 Hz:** Rejected by Goldfish review (`egm-design`, `egm-structural`, `egm-zoom-out`, `egm-implementation-readiness`, `egm-inventive-catalyst`) because it triggers full-shell rebuilds on every frame and detaches `SealTab`.

## Key Decisions & Staging for Next Steps

1. **Adaptive Focus Mode:** `/readings/:date` uses a single unified `CustomScrollView` with `SliverAppBar(floating: true, snap: true)` for inner controls and a damped ($\ge 40\text{ dp}$ hysteresis), route-scoped `readerFocusModeProvider` that slides `AppShell` top chrome (`TopUtilityBar`, `AppBar`, `SealTab`) and banners (`UpdateBanner`, `LiveStreamBanner`, `InstallBanner`) out of view when scrolling down and restores them when scrolling up or leaving the route.
2. **Day Navigation & Font Resize UI:** The date bar displays `[← Previous Day] [Gregorian • Coptic Date] [Next Day →]` using directional arrow icons; font resizing (`0.85x–2.0x`, default `1.0x`, persisted in `church_portal_reading_font_scale`) is accessed via a dedicated font-size control in the reader header with responsive `Wrap` headers on reading cards.
3. **APK Performance Gate:** Flatten Katameros sections into lazy slivers (`SliverList.builder`, `cacheExtent: 500`) and isolate `WarmBackdrop` and `HeroVideo` with `RepaintBoundary` widgets.
