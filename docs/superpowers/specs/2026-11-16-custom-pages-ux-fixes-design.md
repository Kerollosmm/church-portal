# Custom Pages UX & Bugfix Design (Pre-Merge PR #83)

**Date:** 2026-11-16  
**Branch:** `feat/p3j-remaining` (stacked PR #83)  
**Scope:** Targeted bugfixes and UX polish for custom pages before merging Phase 3 (`#74`–`#83`). Built-in section attachment and new page block types are deferred to a separate Phase 4 PR to avoid `firestore.rules` churn and preserve the ~3 KB `main.dart.js` gzip headroom.

## Intent & Approved Decisions
1. **Home Featured Pages + `Reveal` Async Bug (`lib/ui/pages/home_page.dart`, `lib/ui/widgets/golden.dart`, `lib/core/l10n.dart`)**
   - Render `_FeaturedPages` prominently near the top of the discovery flow (right before the first `milestones` / `directory` / `map` block, falling back before the end if all are off) with `SectionTitle(context.tr('featuredPagesTitle'))` (**«صفحات مميزة»** / **"Featured pages"**).
   - No `HomeBlocks` / `settings/features` / `firestore.rules` schema change.
   - Fix `ViewportVisibility` / `Reveal` in `golden.dart` so dynamically hydrated or resized children (such as `_FeaturedPages` or `AsyncSection` starting at height 0 while loading) re-evaluate visibility on layout/build updates and transition to `opacity: 1` without requiring another scroll event.
2. **Preserve `categoryId` Across Placement Changes (`lib/ui/admin/doc_editor.dart`, `test/custom_content_test.dart`)**
   - In `DocEditor.collect()`, when `placement` is `'link'` or `'nav'`, preserve `_values['categoryId'] ?? ''` instead of clearing `categoryId` to `''`.
   - `firestore.rules` (`validPagePlacement`) already accepts `categoryId` strings `[A-Za-z0-9_-]{0,128}` when `placement != 'section'`, and `sectionPages()` filters strictly on `p.effectivePlacement == PagePlacements.section`.
   - Add an explicit unit/widget test verifying that a stored `categoryId` with `placement != 'section'` never causes the page to render inside any section (whether the referenced category exists or was deleted).
3. **Cover Image on Section & Home Page Cards (`lib/ui/pages/category_page.dart`)**
   - Inside `CustomPageCard`, render `CardCover(collection: 'pages', itemStyle: '', image: p.image, label: title)` above the card body padding inside `Column(crossAxisAlignment: CrossAxisAlignment.stretch)`.
   - Cards without an image render zero cover (`SizedBox.shrink()`) and look identical to before (Golden Rule 9), and `Sections.media` toggle governs visibility automatically.
4. **Article Reading Width, Heading Scale & Spacing (`lib/ui/pages/custom_page.dart`)**
   - Inside `CustomPageView`, constrain both the `hero` (`FittedCover`) and the body blocks (`PageBlockView` items) inside a centered `ConstrainedBox(constraints: BoxConstraints(maxWidth: 700))`.
   - Scale `BlockTypes.heading` up (`fontSize: 26`, clear weight & height) and add extra top spacing (`top: 12` before non-first heading blocks, `bottom: 16` after blocks) for comfortable prose reading.
5. **Single-Open Collapsible Page Blocks in Editor (`lib/ui/admin/doc_editor.dart`, `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/admin_strings.dart`)**
   - Add `collapsibleRows: true` (set on `pages.blocks`) so `_objectList` renders collapsed single-line summary cards (type badge, preview snippet, expand toggle, move ↑/↓, delete) and mounts heavy form inputs for **at most one expanded block at a time**.
   - Adding a block opens it and collapses the others; tapping a collapsed block opens it and collapses the active one; reordering tracks the active block; error-summary focus expands the target row automatically. On initial open of a new/template page, auto-open the first block needing attention (e.g., empty `donation` block in `donationPageTemplate`, else block `0`).
   - Lives inside deferred `/admin`, keeping `main.dart.js` impact minimal (target ≤ +500 B gzip across items 1–4).

## Constraints & Non-Goals
- No changes to `firestore.rules`, `tool/gen_seed.py`, or `settings/features`.
- No built-in section picker entries and no new `BlockTypes` in this pass (deferred to Phase 4).
- All edits must preserve `main.dart.js` under `DEFAULT_MAX_GZIP_BYTES` (`node tool/check_web_bundle.mjs`), `flutter analyze --no-pub`, `flutter test --no-pub`, and synced docs (`docs/plans/phase3/STATUS.md`, `docs/memory-bank/`, Arabic `documentation/`).
