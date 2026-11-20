# Phase 4 PR3 (`ADR-076`): Unsaved Page Preview & Duplicate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let church-office admins preview unsaved custom-page edits (`«معاينة، مش محفوظة»`) with zero Firestore writes/uploads, and duplicate existing custom pages (`«تكرار»`) into safe hidden drafts with unique slugs and zero shared-media corruption.

**Architecture:** Keep public `CustomPageView` untouched in `lib/ui/pages/custom_page.dart` and add only an optional `onLinkTap` callback to `PageBlockView` so `main.dart.js` gzip growth stays minimal (~10–30 B), protecting CI's `+338 B` headroom and upcoming Phase 4 PR4. Assemble the preview article, sticky `«معاينة، مش محفوظة»` chrome, fullscreen `PagePreviewScreen` (`lib/ui/admin/page_preview.dart`), duplicate defaults helper (`lib/ui/admin/admin_validators.dart`), strings (`lib/ui/admin/admin_strings.dart`), and triggers (`DocEditor`, `CollectionListScreen`) inside the deferred `/admin` chunk.

**Tech Stack:** Flutter 3.50 / Dart 3, Riverpod 3.4, `material_ui`, deferred admin chunk (`admin_strings.dart`), pure Dart domain/validator unit tests + Flutter widget tests.

**Spec:** `AGENTS.md`, `docs/memory-bank/07-admin-dashboard.md`, `docs/memory-bank/10-decisions-and-history.md` (`ADR-075` / Phase 4 PR3 Roadmap: unsaved page preview `«معاينة، مش محفوظة»` + page duplication `«تكرار»`).

---

## Global Constraints
- **Branch isolation:** Branch `feat/p4-pr3-preview-duplicate` cleanly from `origin/main` (`0e148e4`). Never commit/push directly to `main`; never force-push; never stage pre-existing untracked `admin-simplification-plan.md`.
- **Zero Firestore schema / rules / seed changes:** Do not edit `firestore.rules`, `tool/gen_seed.py`, or `assets/seed/seed.json`. Never write to production Firestore.
- **Strict `main.dart.js` `gzip -9` budget:** CI head `0e148e4` is `1,398,662 B` (`gzip -9`) against `1,399,000 B` (`+338 B` CI headroom; Linux `--release --source-maps` without `--dart-define`s measured `1,396,822 B`, whereas Windows `d072f06` measured `1,376,782 B` due to toolchain/flag variance — plain `gzip -6` is larger and misleading, so always measure via `node tool/check_web_bundle.mjs build/web` which uses `gzip -9`). Record a fresh local `gzip -9` baseline on `0e148e4` in Task 0 before edits, keep all new strings/UI/logic inside deferred `lib/ui/admin/`, and enforce `delta <= +150 B` against that fresh baseline.
- **Deferred strings (Golden Rule 12):** Every new PR3 UI string lives in `lib/ui/admin/admin_strings.dart` (`[ar, en]`), never `lib/core/l10n.dart`.
- **Optional images (Golden Rule 9):** Pages without cover images render identically to before with zero empty gap.
- **Responsive & bilingual parity:** Every modified/new admin & preview surface must render with zero overflow at `320 px`, `400 px`, `1400 px`, and `200%` text scale in both Arabic RTL and English LTR, and respect `englishEnabled` on/off.
- **Windows PowerShell 5.1:** Set `$env:NO_PROXY='127.0.0.1,localhost'`; use `;` instead of `||`; use `Select-String` instead of `grep`.

---

## Review Focus (Edge Cases Pinned by Tests)
1. **Shared `media/{mediaId}` orphan deletion on Duplicate:** Deleting or replacing an image on Page A calls `media.delete(mediaId)`. Note that `MediaImage.ownedMediaId` only covers `inline`, so `buildDuplicatePageDefaults` must check `img.source == MediaSource.url` explicitly, copying external `url` images while dropping both `MediaSource.inline` and `MediaSource.storage` (`droppedOwnedImage: true`) with an informative SnackBar. (`PageBlock` has zero `mediaId` fields in `BlockTypes.fieldsOf`, so deep-copying `blocks` is safe.)
2. **Preview link safety & locale `Directionality`:** Tapping a `button` or `link` block (in-app `/mass-schedule` or external `https://...`) inside Preview must NEVER invoke `GoRouter.go` or `openUrl` and discard unsaved edits; show `previewLinkDisabled` SnackBar instead. Wrapping the preview header + article in explicit `Directionality` + `Localizations.override` ensures AR RTL ↔ EN LTR flips cleanly while keeping admin chrome (`AppBar`, banner, SnackBar) in the admin's language.
3. **Preview side-effect isolation, saved inline media & stale pending bytes:** Opening/closing Preview performs `0` Firestore saves and `0` image uploads, preserves `_dirty` and all form inputs, renders saved `inline` `mediaId` covers via `MediaRepository.load` and unsaved local picks via `_pending['image']?.bytes`, and never shows stale `_pending['image']` bytes after switching to a URL or clearing/removing the cover image.
4. **Slug collisions, boundary hyphens, pending-delete & double-duplication:** Duplicating a 60-char slug with a hyphen near the cut (`'a' * 54 + '-bbbbb'`) must trim trailing hyphens (`_fitSlug` → no `--copy`); duplicating twice (`choir-guide` → `choir-guide-copy` → `choir-guide-copy-2`, never `-copy-copy` or `"نسخة من نسخة من ..."`); and duplicating while a soft-deleted slug is pending undo (`_pendingDelete.isPending`) must keep that slug reserved.
5. **Narrow viewport (`320 px`), `48x48` tap targets & `englishEnabled: false` parity:** Zero `RenderFlex` overflow at `320 px` / `200%` text scale and full `48x48` touch targets (`test/accessibility_test.dart` clean — no `VisualDensity.compact` squeeze on `_sectionPageRow`); when `englishEnabled == false`, Preview hides the AR/EN switcher and renders Arabic RTL matching the public site.

---

## File Map

| File | Responsibility | Bundle Chunk |
|---|---|---|
| `lib/ui/admin/admin_strings.dart` | Add 8 PR3 `[ar, en]` string keys (`previewPage`, `previewUnsavedBanner`, `previewHiddenBadge`, `previewUntitled`, `previewEmptyContent`, `previewLinkDisabled`, `duplicate`, `duplicateDroppedImage`) | Deferred admin (`0 B` main) |
| `lib/ui/admin/admin_validators.dart` | Import `PagePlacements`; add pure `DuplicatePageResult` & `buildDuplicatePageDefaults(source, takenSlugs: ...)` | Deferred admin (`0 B` main) |
| `lib/ui/pages/custom_page.dart` | Add optional `onLinkTap` hook to `PageBlockView` only (leave `CustomPageView` untouched) | Main (`~+10–30 B` `gzip -9`) |
| `lib/ui/admin/page_preview.dart` *(new)* | Fullscreen `PagePreviewScreen` + preview article layout, `HeroStage(image: ..., motion: false, tint: false, rays: 1)`, explicit `Directionality` + `Localizations.override`, `«معاينة، مش محفوظة»` banner, optional AR/EN toggle, pending & inline cover rendering, safe link SnackBar | Deferred admin (`0 B` main) |
| `lib/ui/admin/doc_editor.dart` | Preview triggers (`editor-preview-top`, `editor-preview`) for `pages` only; open `PagePreviewScreen` from live `collect()` + `_pending['image']` | Deferred admin (`0 B` main) |
| `lib/ui/admin/collection_list.dart` | `_duplicatePage(...)`, `titleOverride` on `_openEditor`/`_pushEditor`, `duplicate-${id}` button on `pages` list, `duplicateSectionPage-${id}` button on `_sectionPageRow` | Deferred admin (`0 B` main) |
| `test/custom_content_test.dart` | Unit + widget + responsive TDD regression tests for Tasks 1–4 | Test only |
| `docs/memory-bank/07-admin-dashboard.md`, `docs/memory-bank/10-decisions-and-history.md`, `documentation/features/custom-pages.md`, `documentation/en/features.md`, `.work/feat-p4-pr3-preview-duplicate/status.md` | Synchronous documentation & `ADR-076` | Docs only |

---

## Tasks

### Task 0: Branch Setup, Fresh Local Bundle Baseline & Intake

**Files:**
- Create (git-ignored): `.work/feat-p4-pr3-preview-duplicate/status.md`

- [ ] **Step 1: Fetch `origin/main` and create branch `feat/p4-pr3-preview-duplicate`**
  Run:
  ```powershell
  git fetch origin main; git checkout -b feat/p4-pr3-preview-duplicate origin/main; git status -sb
  ```
  Expected: On branch `feat/p4-pr3-preview-duplicate` at `0e148e4`, clean except pre-existing untracked `admin-simplification-plan.md`.
- [ ] **Step 2: Record fresh local `gzip -9` bundle baseline on `0e148e4`**
  Run:
  ```powershell
  flutter build web --release --source-maps; node tool/check_web_bundle.mjs build/web
  ```
  Record the exact `Gzip (-9) Size` printed for `main.dart.js` in `.work/feat-p4-pr3-preview-duplicate/status.md` as `BASE_GZIP_BYTES`. All subsequent delta checks compare against `BASE_GZIP_BYTES` (`<= BASE_GZIP_BYTES + 150`).
- [ ] **Step 3: Create `.work/feat-p4-pr3-preview-duplicate/status.md`**
  Include goal restatement, `BASE_GZIP_BYTES`, files in scope, checkable acceptance criteria (`320 / 400 / 1400 px`, RTL/LTR, `englishEnabled` on/off, bundle ceiling), and risks.

---

### Task 1: Pure Duplicate-Page Helper & Deferred Admin Strings (TDD)

**Files:**
- Modify: `lib/ui/admin/admin_strings.dart:279-284`
- Modify: `lib/ui/admin/admin_validators.dart:1-50` (import `PagePlacements` from `custom_content.dart`)
- Test: `test/custom_content_test.dart` (new `group('Phase 4 PR3: Preview & Duplicate', ...)` at end of file)

**Interfaces:**
- Produces in `lib/ui/admin/admin_validators.dart`:
  ```dart
  typedef DuplicatePageResult = ({Map<String, Object?> defaults, bool droppedOwnedImage});

  DuplicatePageResult buildDuplicatePageDefaults(
    Map<String, dynamic> source, {
    required Set<String> takenSlugs,
  });
  ```
- Produces in `lib/ui/admin/admin_strings.dart`:
  - `'previewPage'`: `['معاينة', 'Preview']`
  - `'previewUnsavedBanner'`: `['معاينة، مش محفوظة', 'Preview — not saved']`
  - `'previewHiddenBadge'`: `['مخفية عن الزوار', 'Hidden from visitors']`
  - `'previewUntitled'`: `['صفحة بدون عنوان', 'Untitled page']`
  - `'previewEmptyContent'`: `['مفيش فقرات في الصفحة دي لسه', 'No content blocks in this page yet']`
  - `'previewLinkDisabled'`: `['الرابط في المعاينة معطّل: {url}', 'Link is disabled in preview: {url}']`
  - `'duplicate'`: `['تكرار', 'Duplicate']`
  - `'duplicateDroppedImage'`: `['اتنسخت الصفحة من غير صورة الغلاف المرفوعة، ارفع صورة جديدة لو عايز.', 'Duplicated without the uploaded hero image — you can upload a new one.']`

- [ ] **Step 1: Write failing unit tests in `test/custom_content_test.dart`**
  Add `group('Phase 4 PR3: Preview & Duplicate', () { ... })` with 3 unit tests for `buildDuplicatePageDefaults`:
  1. `'copies content, prefixes titles without double prefix, resets visible/featured to false, preserves placement/categoryId/order, strips metadata'`:
     - Source with `titleAr: 'دليل الكورال'`, `titleEn: 'Choir Guide'`, `subtitleAr: 'مقدمة'`, `subtitleEn: 'Intro'`, `slug: 'choir-guide'`, `blocks: [encodedHeading, encodedDonation]`, `placement: 'section'`, `categoryId: 'builtin_activities'`, `featured: true`, `visible: true`, `order: 20`, `updatedAt: DateTime.utc(2026, 11, 19)`, `updatedBy: 'a@b.c'`, `deletedAt: DateTime.utc(2026, 11, 19)`.
     - Assert `defaults['titleAr'] == 'نسخة من دليل الكورال'`, `defaults['titleEn'] == 'Copy of Choir Guide'`, `defaults['subtitleAr'] == 'مقدمة'`, `defaults['subtitleEn'] == 'Intro'`, `defaults['slug'] == 'choir-guide-copy'`, `defaults['blocks']` equals source list (mutating returned list does not mutate source), `defaults['placement'] == 'section'`, `defaults['categoryId'] == 'builtin_activities'`, `defaults['showInNav'] == false`, `defaults['featured'] == false`, `defaults['visible'] == false`, `defaults['order'] == 20`, and `defaults` omits `updatedAt`, `updatedBy`, `deletedAt`.
     - Verify duplicating an already-prefixed page (`titleAr: 'نسخة من دليل الكورال'`, `titleEn: 'Copy of Choir Guide'`) does NOT double-prefix (`titleAr == 'نسخة من دليل الكورال'`, `titleEn == 'Copy of Choir Guide'`).
     - Verify legacy doc without `placement` but `showInNav: true` sets `placement: 'nav'` and `showInNav: true`.
     - Verify 200-char `titleAr`/`titleEn` clamps to `<= 200` chars; empty `titleEn` stays `''`.
  2. `'generates unique valid slugs across collisions, -copy-copy avoidance, 60-char boundary hyphens, and blank/invalid source slugs'`:
     - Source slug `'choir-guide'` with `takenSlugs: {'choir-guide', 'choir-guide-copy'}` → `'choir-guide-copy-2'`.
     - Source slug `'choir-guide-copy'` with `takenSlugs: {'choir-guide', 'choir-guide-copy'}` → strips trailing `-copy(-\d+)?` before suffixing so it produces `'choir-guide-copy-2'` (never `'choir-guide-copy-copy'`).
     - Source slug of 60 `'a'` chars with `takenSlugs: {slug60}` → `isValidSlug(slug) == true`, `slug.length <= 60`, ends with `'-copy'`, not in `takenSlugs`.
     - Boundary-hyphen 60-char slug `'${'a' * 54}-bbbbb'` (60 chars) → `isValidSlug(slug) == true`, `slug == '${'a' * 54}-copy'`, never `'...--copy'`.
     - Source with blank/invalid slug `'INVALID SLUG!'` and `titleAr: 'حجز رحلة'` → falls back to `slugFromTitle('نسخة من حجز رحلة', taken: takenSlugs)`, valid and unique.
  3. `'copies external url cover image safely and drops owned inline/storage or invalid cover images'`:
     - External URL `{source: 'url', url: 'https://example.com/a.jpg', alt: 'Cover'}` → copied as distinct map, `droppedOwnedImage == false`.
     - Inline `{source: 'inline', mediaId: 'abc123', alt: 'Cover'}` → `defaults['image'] == null`, `droppedOwnedImage == true`.
     - Storage `{source: 'storage', url: 'https://example.com/a.jpg', mediaId: 'abc123'}` → `defaults['image'] == null`, `droppedOwnedImage == true`.
     - Invalid URL `{source: 'url', url: 'javascript:alert(1)'}` → `defaults['image'] == null`, `droppedOwnedImage == false`.

- [ ] **Step 2: Run tests to verify they FAIL**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart --plain-name "Phase 4 PR3"
  ```
  Expected: FAIL (`Method not found: 'buildDuplicatePageDefaults'`).

- [ ] **Step 3: Implement `buildDuplicatePageDefaults` in `lib/ui/admin/admin_validators.dart` and add keys to `lib/ui/admin/admin_strings.dart`**
  - Add `PagePlacements` and `MediaSource` imports to `admin_validators.dart`.
  - Explicitly inspect `source['image']` via `MediaImage.fromMap`: only copy when `img.source == MediaSource.url` (`img.toMap()`); if `raw is Map && (raw['source'] == MediaSource.inline || raw['source'] == MediaSource.storage)` return `image: null` with `droppedOwnedImage: true`; otherwise `image: null, droppedOwnedImage: false`. (Do not rely on `img.ownedMediaId`, which only covers `inline`.)
  - For slug suffixing when `isValidSlug(orig)` is true: strip any trailing `-copy(-\d+)?$` (`final stem = orig.replaceFirst(RegExp(r'-copy(?:-\d+)?$'), '');` falling back to `orig` if empty), try `'${_fitSlug(stem, slugMaxLength - 5)}-copy'`, then for `n = 2..` try `'${_fitSlug(stem, slugMaxLength - suffix.length)}$suffix'` where `suffix = '-copy-$n'`.
  - `_prefixedTitle(String raw, String prefix, int maxLen)`: trim; return `''` if empty; if `trimmed.startsWith(prefix)`, clamp `trimmed` to `maxLen`; else prepend `prefix` and clamp to `maxLen`.
  - Allow-list `pages` fields (`titleAr`, `titleEn`, `subtitleAr`, `subtitleEn`, `image`, `blocks`, `placement`, `categoryId`, `showInNav`, `featured`, `visible`, `slug`, `order`), forcing `visible: false` and `featured: false`, and deep-copying `blocks` as `List<String>`.

- [ ] **Step 4: Run tests to verify PASS**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart --plain-name "Phase 4 PR3"
  ```
  Expected: PASS (`3/3`).

- [ ] **Step 5: Commit**
  ```powershell
  git add lib/ui/admin/admin_strings.dart lib/ui/admin/admin_validators.dart test/custom_content_test.dart
  git commit -m "feat(admin): add duplicate page defaults helper and PR3 admin strings"
  ```

---

### Task 2: Add Optional `onLinkTap` Hook to `PageBlockView` in `lib/ui/pages/custom_page.dart` (TDD)

**Files:**
- Modify: `lib/ui/pages/custom_page.dart:84-137` (`PageBlockView` only; keep `CustomPageView` untouched)
- Test: `test/custom_content_test.dart`

**Interfaces:**
- Produces in `lib/ui/pages/custom_page.dart`:
  ```dart
  class PageBlockView extends StatelessWidget {
    final PageBlock block;
    final void Function(String url)? onLinkTap;
    const PageBlockView({super.key, required this.block, this.onLinkTap});
  }
  ```

- [ ] **Step 1: Write failing widget test in `test/custom_content_test.dart`**
  Inside `group('Phase 4 PR3: Preview & Duplicate', ...)`:
  - `'PageBlockView delegates button and link taps to onLinkTap when provided without navigating'`:
    - Pump `Column` with `PageBlockView` for a `BlockTypes.button` (`/mass-schedule`) and a `BlockTypes.link` (`https://example.com`), both passing `onLinkTap: tapped.add`.
    - Tap both button and link → assert `tapped == ['/mass-schedule', 'https://example.com']` without requiring `GoRouter`.

- [ ] **Step 2: Run test to verify FAIL**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart --plain-name "PageBlockView delegates"
  ```
  Expected: FAIL (`No named parameter with the name 'onLinkTap'`).

- [ ] **Step 3: Add `final void Function(String url)? onLinkTap;` to `PageBlockView` in `lib/ui/pages/custom_page.dart`**
  Keep `CustomPageView` completely unchanged. Inside `PageBlockView.build`, replace direct `openLink(context, b.url)` calls in `BlockTypes.button` and `BlockTypes.link` with `(onLinkTap ?? (u) => openLink(context, u))(b.url)`.

- [ ] **Step 4: Run `test/custom_content_test.dart` & check `main.dart.js` `gzip -9` delta**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart
  ```
  Expected: PASS (0 failures).

- [ ] **Step 5: Commit**
  ```powershell
  git add lib/ui/pages/custom_page.dart test/custom_content_test.dart
  git commit -m "feat(pages): add optional onLinkTap hook to PageBlockView for preview"
  ```

---

### Task 3: Unsaved Page Preview (`PagePreviewScreen` + `DocEditor` Integration, TDD)

**Files:**
- Create: `lib/ui/admin/page_preview.dart`
- Modify: `lib/ui/admin/doc_editor.dart:1-30, 2393-2495`
- Test: `test/custom_content_test.dart`

**Interfaces:**
- Consumes: `PageBlockView` (Task 2), `FittedCover` (`lib/ui/widgets/styled_image.dart`), `HeroStage`, `TextScrim`, `PosterHeading`, `TitleRibbon`, `ArtAssets` (`lib/ui/widgets/golden.dart`), `MediaRepository` (`lib/data/media_repository.dart`), `mediaRepositoryProvider` (`lib/state/providers.dart`), `admin_strings.dart` keys (Task 1).
- Produces in `lib/ui/admin/page_preview.dart`:
  ```dart
  class PagePreviewScreen extends StatefulWidget {
    final CustomPage page;
    final Uint8List? pendingHeroBytes;
    final String pendingHeroAlt;
    final MediaRepository? media;
    final bool englishEnabled;
    const PagePreviewScreen({
      super.key,
      required this.page,
      this.pendingHeroBytes,
      this.pendingHeroAlt = '',
      this.media,
      this.englishEnabled = true,
    });
  }
  ```
- Widget keys (tested & stable):
  - `DocEditor`: `Key('editor-preview-top')` (AppBar), `Key('editor-preview')` (bottom action area)
  - `PagePreviewScreen`: `Key('preview-unsaved-banner')`, `Key('preview-lang-toggle')`, `Key('preview-hidden-badge')`, `Key('preview-empty-content')`, `Key('pagePreviewPendingHero')`, `Key('pageHero')`

- [ ] **Step 1: Write failing widget tests in `test/custom_content_test.dart`**
  Inside `group('Phase 4 PR3: Preview & Duplicate', ...)`:
  1. `'DocEditor shows Preview action only for pages, previews unsaved edits & pending hero bytes, clears pending bytes when switching to url or removing cover, blocks links safely, and preserves dirty state'`:
     - Pump `DocEditor` for `categories` → assert `Key('editor-preview')` and `Key('editor-preview-top')` find nothing.
     - Pump `DocEditor` for `pages` (`data: existingPage` with valid saved cover or none, `onSave` recording calls, fake `pickImage` returning valid 1x1 PNG bytes, fake `prepareImage` returning `EncodedImage` with those bytes, fake `MediaRepository` recording upload calls):
       - Edit `field-titleAr` to `'عنوان تجريبي غير محفوظ'`, add a `button` block with `textAr: 'جدول القداسات'` and `url: '/mass-schedule'`, pick a local cover image (stages `_pending['image']`).
       - Tap `Key('editor-preview')` → `pumpAndSettle()`.
       - Assert `Key('preview-unsaved-banner')` shows `'معاينة، مش محفوظة'` (`Locale('ar')`; test `'Preview — not saved'` in `Locale('en')` too).
       - Assert `'عنوان تجريبي غير محفوظ'` and `Key('pagePreviewPendingHero')` are visible.
       - Tap `'جدول القداسات'` inside preview → assert SnackBar containing `'/mass-schedule'` appears and stays in admin language even if preview language was toggled; preview stays open.
       - Close preview → assert `DocEditor` still has `'عنوان تجريبي غير محفوظ'`, `ValueKey('unsaved-bar')` still shown (`dirty == true`), `saves.isEmpty`, and `mediaUploads.isEmpty`.
       - Next, switch cover image via URL dialog (`https://example.com/new.jpg`) → open Preview → assert `Key('pagePreviewPendingHero')` is absent and `Key('pageHero')` is shown; close Preview, tap remove-image button → open Preview → assert neither `Key('pagePreviewPendingHero')` nor `Key('pageHero')` is rendered.
  2. `'PagePreviewScreen loads saved inline mediaId hero images via MediaRepository, respects englishEnabled toggle + Directionality, hidden badge, empty note, and fits 320/400/1400 px at 200% text scale'`:
     - Pass a `CustomPage` with `image: MediaImage(source: MediaSource.inline, mediaId: 'hero1', alt: 'Alt')`, `visible: false`, no blocks, and a fake `MediaRepository` whose `load('hero1')` returns 1x1 PNG bytes: assert `MediaRepository.load('hero1')` is called and `Key('pageHero')` renders cleanly without throwing.
     - With `englishEnabled: true` and bilingual page (`titleAr` + `titleEn`, `visible: false`, no blocks): assert `Key('preview-hidden-badge')` and `Key('preview-empty-content')` show, and tapping `Key('preview-lang-toggle')` flips `Directionality.of(...)` inside the preview body between `TextDirection.rtl` (`titleAr`) and `TextDirection.ltr` (`titleEn`) while leaving `preview-unsaved-banner` in admin's language.
     - With `englishEnabled: false`: assert `Key('preview-lang-toggle')` is absent and preview body renders `titleAr` with `TextDirection.rtl` even when admin UI locale is `Locale('en')`.
     - Pump both `DocEditor(pages)` and `PagePreviewScreen` at `Size(320, 800)` (with `TextScaler.linear(2.0)`), `Size(400, 900)`, and `Size(1400, 900)` in AR & EN → assert `tester.takeException() == null`.

- [ ] **Step 2: Run tests to verify FAIL**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart --plain-name "Preview action only|PagePreviewScreen loads"
  ```
  Expected: FAIL (`page_preview.dart` missing / `editor-preview` not found).

- [ ] **Step 3: Implement `lib/ui/admin/page_preview.dart` and hook into `lib/ui/admin/doc_editor.dart`**
  - In `lib/ui/admin/page_preview.dart`:
    - Determine `_previewLocale`: when `!widget.englishEnabled`, force `const Locale('ar')`; otherwise initialize from `Localizations.localeOf(context)` in `didChangeDependencies` and toggle `'ar'` ↔ `'en'` via `Key('preview-lang-toggle')` in the AppBar.
    - Keep `Scaffold`, `AppBar`, `Key('preview-unsaved-banner')` (`Wrap` containing status label + optional `Key('preview-hidden-badge')`), and `_showPreviewLinkNotice(String url)` SnackBar **outside** the locale/direction override so admin chrome stays in the admin's UI language.
    - Wrap the preview body inside:
      ```dart
      Directionality(
        textDirection: _previewLocale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Localizations.override(
          context: context,
          locale: _previewLocale,
          child: ...,
        ),
      )
      ```
    - Conditionally wrap with `ProviderScope(overrides: [mediaRepositoryProvider.overrideWithValue(widget.media)])` **only when `widget.media != null`** so `FittedCover` resolves inline `media/{id}` images cleanly without extra overhead when `null`.
    - Render golden-hour header matching public `PageHeader` (`lib/ui/widgets/common.dart:114-152`) directly with `HeroStage(image: phone ? ArtAssets.heroWideSmall : ArtAssets.heroWide, alignment: const Alignment(0, -0.35), motion: false, tint: false, rays: 1)` + `TextScrim` + `PosterHeading` + `TitleRibbon` (so `repositoryProvider` / `featuresProvider` is never touched; fallback title `context.tr('previewUntitled')` when both `titleAr` & `titleEn` are blank).
    - Render centered `ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700))` containing:
      - `pendingHeroWidget` when `widget.pendingHeroBytes != null` (`Image.memory(..., key: const Key('pagePreviewPendingHero'), fit: BoxFit.contain)` inside `AspectRatio(aspectRatio: 16 / 7)` + `ConstrainedBox(maxHeight: 420)`), else `FittedCover(key: const Key('pageHero'), image: hero, label: title, aspectRatio: 16 / 7, maxHeight: 420, enlargeOnTap: false)` when `page.image != null`.
      - Visible non-empty `PageBlockView(block: b, onLinkTap: _showPreviewLinkNotice)` blocks, or `Key('preview-empty-content')` when both hero and visible blocks are absent.
  - In `lib/ui/admin/doc_editor.dart`:
    - Add `_canPreviewPage` getter: `widget.def?.name == 'pages' && widget.popOnSave`.
    - Add `_openPagePreview()`: calls `collect()`, extracts `CustomPage.fromMap(widget.docId ?? 'preview', collected)`, passes `_pending['image']?.bytes` and `_text['image']?.text.trim() ?? ''` along with `widget.media` and `widget.englishEnabled`, pushes `MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PagePreviewScreen(...))`.
    - Wire `Key('editor-preview-top')` into `AppBar.actions` (responsive icon vs `TextButton.icon` at `< 480 px`) and `Key('editor-preview')` (`OutlinedButton.icon`) beside `Key('editor-save')` inside a `Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end)` so `editor-save` remains prominent and never overflows at `320 px` / `200%` scale.

- [ ] **Step 4: Run `test/custom_content_test.dart` and `test/admin_test.dart` to verify PASS**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart test/admin_test.dart
  ```
  Expected: PASS (0 failures).

- [ ] **Step 5: Commit**
  ```powershell
  git add lib/ui/admin/page_preview.dart lib/ui/admin/doc_editor.dart test/custom_content_test.dart
  git commit -m "feat(admin): add unsaved custom page preview screen and editor triggers"
  ```

---

### Task 4: Duplicate Page Action in `CollectionListScreen` (`pages` & `categories` Screens, TDD)

**Files:**
- Modify: `lib/ui/admin/collection_list.dart:889-919, 1085-1108, 1345-1505`
- Test: `test/custom_content_test.dart`

**Interfaces:**
- Consumes: `buildDuplicatePageDefaults` (Task 1), `collectTakenSlugs` (existing in `collection_list.dart`), `admin_strings.dart` keys `'duplicate'` and `'duplicateDroppedImage'` (Task 1).
- Produces:
  - `_duplicatePage(BuildContext context, AdminDoc source, {required CollectionDef pagesDef})` in `_CollectionListScreenState`.
  - Optional `String? titleOverride` on `_openEditor` and `_pushEditor`.
  - Widget keys: `ValueKey('duplicate-${d.id}')` on `pages` list tiles; `ValueKey('duplicateSectionPage-${p.id}')` on `_sectionPageRow`.

- [ ] **Step 1: Write failing widget tests in `test/custom_content_test.dart`**
  Inside `group('Phase 4 PR3: Preview & Duplicate', ...)`:
  1. `'CollectionListScreen(pages) duplicates a page into a hidden unsaved draft with unique slug, preserves saveable new-doc state, handles pending-delete slugs & uploaded vs url images safely'`:
     - Seed `pages` with:
       - `p1`: `titleAr: 'صفحة تبرعات'`, `slug: 'donations-2026'`, `visible: true`, `featured: true`, `placement: 'section'`, `categoryId: BuiltInSections.about`, `image: {'source': 'inline', 'mediaId': 'm1'}`, `blocks: [encodedParagraph]`.
       - `p2-pending`: `slug: 'donations-2026-copy'` (then delete `p2-pending` in UI via soft-delete so `_pendingDelete.isPending('p2-pending')` is true with an active undo timer!).
     - Tap `ValueKey('duplicate-p1')` → `pumpAndSettle()`.
     - Assert `b.saves.isEmpty`, SnackBar shows `duplicateDroppedImage`, `DocEditor` opens immediately with `titleAr == 'نسخة من صفحة تبرعات'`, `slug == 'donations-2026-copy-2'` (avoiding pending-delete `p2-pending`!), `visible == false`, `featured == false`, AND `Key('editor-save')` succeeds even if the admin makes zero further edits!
     - Tap `Key('editor-save')` → `pumpAndSettle()` → assert `b.saves.length == 1`, `b.saves.single.$1 == 'pages'`, `b.saves.single.$2 == null` (new doc, original `p1` untouched), `b.saves.single.$3['slug'] == 'donations-2026-copy-2'`, `b.saves.single.$3['image'] == null`, `b.saves.single.$3['visible'] == false`, `b.saves.single.$3['featured'] == false`, `b.saves.single.$3['categoryId'] == BuiltInSections.about`.
     - Verify cancelling a duplicate leaves `b.saves` unchanged (0 writes), and duplicating a page with an external `url` cover image preserves the URL image with no `duplicateDroppedImage` SnackBar.
  2. `'CollectionListScreen(categories) duplicates a section page from built-in and custom section tiles using live takenSlugs and passes 320/400/1400 px & 48x48 tap-target accessibility'`:
     - Seed `categories` with 1 custom category `c1`, `pages` with `p-builtin` (`categoryId: BuiltInSections.activities`, `slug: 'choir-guide'`) and `p-custom` (`categoryId: 'c1'`, `slug: 'choir-guide-copy'`).
     - Tap `ValueKey('duplicateSectionPage-p-builtin')` → `pumpAndSettle()` → assert `DocEditor` opens with `slug == 'choir-guide-copy-2'` (avoiding BOTH `p-builtin` and `p-custom`!) and `categoryId == BuiltInSections.activities`.
     - Save → assert new doc created in `'pages'` with `id == null`.
     - Verify `CollectionListScreen(pages)` and `CollectionListScreen(categories)` render with zero overflow at `320 px` (`TextScaler.linear(2.0)`), `400 px`, and `1400 px` in AR and EN, preserving standard `48x48` icon tap targets.

- [ ] **Step 2: Run tests to verify FAIL**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart --plain-name "duplicates a page|duplicates a section page"
  ```
  Expected: FAIL (`duplicate-p1` / `duplicateSectionPage-p-builtin` not found).

- [ ] **Step 3: Implement `_duplicatePage` and duplicate triggers in `lib/ui/admin/collection_list.dart`**
  - Add `String? titleOverride` parameter to `_openEditor` and `_pushEditor` (when non-null, use for `editorTitle`).
  - Add `_duplicatePage(BuildContext context, AdminDoc source, {required CollectionDef pagesDef})`:
    - Resolve live pages: `final allPages = def.name == 'pages' ? _lastDocs : (_lastPages ?? await _read('pages'));`
    - Guard `if (!context.mounted) return;`
    - Compute `taken = collectTakenSlugs(allPages, excludeId: null, isPendingDelete: _pendingDelete.isPending);` (note: in `collection_list.dart:86`, `collectTakenSlugs` INCLUDES pending-delete docs cleanly via `!isSoftDeleted(x.data) || isPendingDelete(x.id)`).
    - Call `final dup = buildDuplicatePageDefaults(source.data, takenSlugs: taken);`
    - Capture `final messenger = ScaffoldMessenger.of(context);` and `final droppedMsg = context.tr('duplicateDroppedImage');` before `_openEditor`, call `await _openEditor(context, null, targetDef: pagesDef, extraDefaults: dup.defaults, titleOverride: '${context.tr('duplicate')} — ${context.pick(pagesDef.labelAr, pagesDef.labelEn)}');` (which synchronously pushes `DocEditor`), then if `dup.droppedOwnedImage && context.mounted`, call `messenger.showSnackBar(SnackBar(content: Text(droppedMsg)))` so the SnackBar displays cleanly over the pushed `DocEditor` without route-transition race.
  - In `_tile` bottom action `Wrap` (around `L1090-L1104`): when `def.name == 'pages'`, add `TextButton.icon(key: ValueKey('duplicate-${d.id}'), onPressed: () => _duplicatePage(context, d, pagesDef: def), icon: const Icon(Icons.copy_outlined, size: 18), label: Text(context.tr('duplicate')))` alongside `openItem` and `_namedDeleteButton`.
  - In `_sectionPageRow` (`L889-L919`): use `Expanded` cleanly inside `ListTile` (already handled by `ListTile.title` + `trailing`), and put both standard `48x48` `IconButton`s (NO `VisualDensity.compact`, preserving WCAG 2.5.8 / `accessibility_test.dart` tap target minimums!) inside `trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(key: ValueKey('duplicateSectionPage-${p.id}'), ...), IconButton(key: ValueKey('visibilitySectionPage-${p.id}'), ...)])`.

- [ ] **Step 4: Run `test/custom_content_test.dart`, `test/admin_test.dart`, and `test/accessibility_test.dart` to verify PASS**
  ```powershell
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/custom_content_test.dart test/admin_test.dart test/accessibility_test.dart
  ```
  Expected: PASS (0 failures).

- [ ] **Step 5: Commit**
  ```powershell
  git add lib/ui/admin/collection_list.dart test/custom_content_test.dart
  git commit -m "feat(admin): add duplicate action on custom pages list and section page rows"
  ```

---

### Task 5: Docs Sync (`ADR-076`), Full Local Verification Gate, Bundle Audit, PR & Review Loop

**Files:**
- Modify: `docs/memory-bank/07-admin-dashboard.md`
- Modify: `docs/memory-bank/10-decisions-and-history.md` (add `ADR-076` + PR history table row)
- Modify: `documentation/features/custom-pages.md` (Arabic manual with exact labels `«معاينة»`, `«معاينة، مش محفوظة»`, `«تكرار»`, `«مخفية»`)
- Modify: `documentation/en/features.md`
- Update (git-ignored): `.work/feat-p4-pr3-preview-duplicate/status.md`

- [ ] **Step 1: Sync docs & add `ADR-076`**
  Update all 4 tracked documentation files + git-ignored `status.md`. Confirm zero invented church content and exact admin labels from `admin_strings.dart`.

- [ ] **Step 2: Run full local verification gate**
  ```powershell
  flutter analyze
  $env:NO_PROXY='127.0.0.1,localhost'; flutter test
  node --test web/*.test.mjs tool/*.test.mjs
  python tool/gen_seed.py; git diff --exit-code -- assets/seed/seed.json tool/known_seed_ids.json tool/retired_seed_ids.json
  flutter build web --release --source-maps; node tool/check_web_bundle.mjs build/web
  ```
  Expected:
  - `flutter analyze`: 0 issues.
  - `flutter test`: all tests pass (0 failed).
  - `node --test`: all suites pass.
  - `gen_seed.py`: clean diff (exit 0).
  - `check_web_bundle.mjs`: PASS (`gzip -9`), all 8 deferred modules isolated with 0 leaks, 4 OpenType fonts intact, and `main.dart.js` `gzip -9` delta `<= +150 B` over `BASE_GZIP_BYTES` recorded in Task 0.

- [ ] **Step 3: Commit docs, push branch, open PR, run `/pr-review-loop`**
  - Verify `git status -sb` (ensure `admin-simplification-plan.md` is unstaged/untracked).
  - Push `feat/p4-pr3-preview-duplicate` to `origin`.
  - Open PR against `main` using `/pr` body conventions (Summary, Evidence, Merge Danger).
  - Run `/pr-review-loop` (`@coderabbitai review`, `@sentry review`), fix any real findings with TDD tests, verify CI green on head SHA (confirming CI `main.dart.js` `gzip -9 <= 1,399,000 B` and Firebase Preview URL), and stop before merge for owner sign-off.

---

## Re-plan If
- Local `main.dart.js` `gzip -9` delta exceeds `+150 B` over `BASE_GZIP_BYTES` (risking CI's `+338 B` headroom under `1,399,000 B`): stop and inspect why `page_preview.dart` or `custom_page.dart` pulled bytes into main (e.g., verify no public file imported `page_preview.dart`).
- Any existing `DocEditor` test breaks because bottom button layout changes (`Key('editor-save')` must stay directly findable and tappable without scrolling regressions).
- `_sectionPageRow` with two standard `48x48` trailing icons overflows horizontally at `320 px` / `200%` scale: move the duplicate action into the bottom action `Wrap` or a `PopupMenuButton` on narrow widths while preserving `ValueKey('duplicateSectionPage-${p.id}')`.

---

## Owner Amendments & Follow-up Next PR (Post-PR3)
1. **Colloquial Arabic notice (`duplicateDroppedImage`):** `'اتنسخت الصفحة من غير صورة الغلاف المرفوعة، ارفع صورة جديدة لو عايز.'`
2. **Defaults-only zero-write invariant on Duplicate:** «تكرار» opens `DocEditor` with `data: null` and `extraDefaults` only — zero Firestore writes (`saves`/`updates`/`deletes`) occur on open or during edits until the admin explicitly presses `editor-save` (covered by dedicated regression test in `test/custom_content_test.dart`).
3. **Next PR immediately after PR3 merges (before any new block types):**
   - **Web bundle size optimization:** reclaim ~`+20 KB` `gzip -9` headroom on `main.dart.js` under the `1,399,000 B` ceiling.
   - **Firestore multi-tab persistence fix:** resolve multi-tab IndexedDB persistence behavior in `Firestore` initialization before shipping any new custom-page block types.
