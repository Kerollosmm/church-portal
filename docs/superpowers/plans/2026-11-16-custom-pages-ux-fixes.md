# Custom Pages UX & Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 5 approved custom-page UX fixes and bugs (`_FeaturedPages` placement + `Reveal` async fix, preserved `categoryId`, `CustomPageCard` cover image, 700px reading column + typography, and single-open collapsible editor blocks) on `feat/p3j-remaining` without breaking the ~3 KB web bundle headroom.

**Architecture:** Public presentation fixes stay minimal in `main.dart.js` using existing `CardCover` and `SectionTitle` primitives without touching `firestore.rules`. Editor collapse state is scoped to `blocks` inside deferred `DocEditor` while keeping `_Row` controllers and validators intact for off-screen rows.

**Tech Stack:** Flutter (Dart), Riverpod, GoRouter, `flutter_test`, Node web bundle gate (`tool/check_web_bundle.mjs`).

**Spec:** `docs/superpowers/specs/2026-11-16-custom-pages-ux-fixes-design.md`

## Global Constraints
- Hero `FittedCover` and blocks in `CustomPageView` are capped at `maxWidth: 700`.
- Home featured section title uses `featuredPagesTitle`: `'صفحات مميزة'` / `'Featured pages'`.
- `firestore.rules` and `settings/features` remain untouched.
- `node tool/check_web_bundle.mjs build/web` passes under `DEFAULT_MAX_GZIP_BYTES`.

## Review Focus
- `Reveal` wraps an async `_FeaturedPages` that starts at height 0 while `customPagesProvider` is loading, then grows to non-zero height without user scroll: must transition to `opacity: 1`.
- Saving a custom page as `'link'`/`'nav'` after picking a section keeps `categoryId`, and even if that category is later deleted or still exists, `sectionPages()` must never list it.
- Opening `donationPageTemplate` must still expose `field-account` immediately (row 1 `donation` auto-expanded) so the existing `<= 5 steps` creation flow works unchanged.
- `CustomPageCard` with `image == null` or `Sections.media` disabled must render identically to before.
- Error summary tap targeting a validation error inside a collapsed `blocks` row must auto-expand that row before scrolling/focusing.

---

### Task 1: Home `_FeaturedPages` Placement, `Reveal` Async Fix & Card Cover (`main.dart.js`)

**Files:**
- Modify: `lib/core/l10n.dart` (add `'featuredPagesTitle': ['صفحات مميزة', 'Featured pages']`)
- Modify: `lib/ui/widgets/golden.dart` (`ViewportVisibility` / `Reveal` re-check on size/build changes)
- Modify: `lib/ui/pages/home_page.dart` (`_FeaturedPages` position before discovery blocks + `SectionTitle`)
- Modify: `lib/ui/pages/category_page.dart` (`CustomPageCard` with `CardCover`)
- Modify: `lib/ui/pages/custom_page.dart` (`maxWidth: 700` hero + blocks, heading size `26`, top spacing `12`, block bottom `16`)
- Test: `test/custom_content_test.dart`, `test/golden_hour_test.dart`

- [ ] **Step 1:** Add failing widget tests in `test/custom_content_test.dart`:
  - `HomePage` shows `SectionTitle` `'Featured pages'` / `'صفحات مميزة'` above `home-featuredPages` before `home-patrons` / discovery blocks; when `customPagesProvider` emits asynchronously after initial pump (even at wide 1200x800 desktop where motion/Reveal is active), featured cards reveal (`Opacity == 1`).
  - `CustomPageCard` renders `CardCover` (`cardCover`) when `page.image != null` and `Sections.media` is on, hides cover when `Sections.media` is off, and keeps identical layout when `page.image == null`.
  - `CustomPageView` constrains hero `FittedCover` and blocks column to `<= 700` width on a 1280px viewport, renders heading with `fontSize >= 24`, and adds clear spacing around headings.
- [ ] **Step 2:** Implement `l10n.dart`, `golden.dart`, `home_page.dart`, `category_page.dart`, and `custom_page.dart`.
- [ ] **Step 3:** Run targeted tests (`NO_PROXY=127.0.0.1,localhost flutter test --no-pub test/custom_content_test.dart test/golden_hour_test.dart`).

### Task 2: Preserve `categoryId` & Collapsible Single-Open Blocks in `DocEditor`

**Files:**
- Modify: `lib/ui/admin/admin_schema.dart` (add `bool collapsibleRows = false` on `FieldDef`, set `true` on `pages.blocks`)
- Modify: `lib/ui/admin/admin_strings.dart` (if any collapsed summary empty label is needed, keep inside deferred admin chunk)
- Modify: `lib/ui/admin/doc_editor.dart` (`collect()` preserves `categoryId`; `_objectList` supports single-open collapsible rows with error-focus auto-expand and smart initial index)
- Test: `test/custom_content_test.dart`

- [ ] **Step 1:** Add failing tests in `test/custom_content_test.dart`:
  - Pure domain test: a `CustomPage` with a stored `categoryId` (both matching an existing category and a non-existent/deleted category id) and `placement: PagePlacements.link` / `PagePlacements.nav` never appears in `sectionPages(...)`.
  - `DocEditor` widget test: select `placement = section`, choose `categoryId = 'k1'`, switch to `link`, save -> saved payload preserves `'categoryId': 'k1'`; reopen editor with saved data and switch back to `section` -> `'k1'` is still selected.
  - `DocEditor` collapsible `blocks` test: with multiple blocks, only one block's inputs are expanded at once; tapping a collapsed block opens it and collapses the previous one; tapping Add expands the new block; reordering keeps active block expanded; tapping an error summary link for a collapsed invalid block auto-expands that block. Also verify `P1-15` donation template still finds `field-account` immediately.
- [ ] **Step 2:** Implement changes in `admin_schema.dart`, `admin_strings.dart`, and `doc_editor.dart`.
- [ ] **Step 3:** Run `flutter analyze --no-pub` and `NO_PROXY=127.0.0.1,localhost flutter test --no-pub test/custom_content_test.dart test/admin_pickers_test.dart test/admin_test.dart`.

### Task 3: Docs Sync & Verification Gate

**Files:**
- Modify: `docs/memory-bank/`, `documentation/features/custom-pages.md`, `documentation/features/home-and-hero.md` (and any affected admin docs), `docs/plans/phase3/STATUS.md`, `.work/feat/p3j-remaining/status.md`

- [ ] **Step 1:** Run `docs-keeper` to update memory bank & Arabic documentation to match the implemented UX & bugfixes.
- [ ] **Step 2:** Run full local verification: `flutter analyze --no-pub`, `NO_PROXY=127.0.0.1,localhost flutter test --no-pub`, `python tool/gen_seed.py`, `flutter build web --release`, `node tool/check_web_bundle.mjs build/web`.
- [ ] **Step 3:** Push to `feat/p3j-remaining`, verify GitHub Actions (`CI` + `Deploy to Firebase` preview channel), confirm updated preview URL HTTP 200 & new bundle markers, and deliver preview link to user.
