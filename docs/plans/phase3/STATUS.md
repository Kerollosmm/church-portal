# حالة التنفيذ (Phase 3 status — tick as you go)

> Single checklist for the admin-panel simplification plan. Update it in the branch you are working on.
> Overview: [README.md](README.md) · how to build: [SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md).

## الوضع الحالي (Current state)

- **Baseline:** the report's last review, 13 November 2026 (Africa/Cairo), against the code after PR #70.
- **Counts:** 5 fixes on live data · 23 open tasks in the code · 13 done or removed · 1 deferred by decision.
- **Code:** Stage 1 (PR 3A `feat/p3a-safe-actions`, PR 3B `feat/p3b-written-state`, PR 3C `feat/p3c-admin-status-session`, PR 3D `feat/p3d-custom-pages`), Stage 2 (PR 3E `feat/p3e-menu-home`, PR 3F `feat/p3f-forms`, PR 3G `feat/p3g-english-switch`, PR 3H `feat/p3h-inbox`, PR 3I `feat/p3i-sitemap-assistant`; item 28 deferred), and Stage 3 PR 3J (`feat/p3j-remaining`: P3-30, P3-31; item 32 left out, item 34 deferred) implemented.
- **PR #83 Preview QA fixes:** Hardened against live preview review findings (`b2da189`, `fcb55c7`, `534dedd`, `9e0602c`): normalized nullable page `categoryId` in `validPagePlacement`; added `deletedAt` soft-delete undo & lazy purge for `contact_messages`; added persistent `editor-save-error` inline banner in `DocEditor`; added web `popstate` capture guard for Browser Back in `UnsavedGuard`; surfaced notice `priority` directly outside collapsed advanced options; prevented false `updatedElsewhere` banner during save rollbacks in `FeaturesEditor` & `ChurchInfoScreen`; added unconfirmed item section breakdown in `OverviewScreen`; updated sample switch to «غير مؤكد (تجريبي)»; added owner self-row active badge in `AdminsScreen`; improved notifications chip contrast & cleared past-time errors on earliest send; prevented Google Maps iframe scroll trapping with `MapInteractionGuard`; reset contact category dropdown & completed autofill context on successful submit; and added redirects for `/activities`, `/priests`, `/notices`, and `/donations`.
- **PR #83 Custom Pages pass & Polish improvements:** Polished custom pages UX and admin quality on `feat/p3j-remaining`: moved featured pages to discovery zone before milestones/directory/map with «صفحات مميزة» section title (centered in `ConstrainedBox(maxWidth: 560)` when single; `ResponsiveGrid` when multiple), `SizeChangedLayoutNotification` async hydration reveal, and `_RevealState.viewportLead` tuned to `20` (preventing blank viewport gaps); rendered `CardCover` on `CustomPageCard`; constrained `CustomPageView` to 700px centered reading width with 26px headings; added `FieldDef.collapsibleRows` single-open block cards with snippet previews and auto-expand; and preserved `categoryId` across non-section placement saves in `DocEditor.collect()`. Recorded 4+1 polish improvements: (1) `featuredPages` sorting by `order` ascending, `updatedAt` descending, and duplicate slug deduplication, plus admin hint «هتظهر في «صفحات مميزة» في الرئيسية مهما كان مكانها»; (2) unified empty custom categories logic between visitor navigation (`publicNonEmptyCategories`) and Admin `CollectionListScreen` (`categories`) via `isCategoryNonEmpty`, badging them with «فاضي، مش ظاهر للزوار» (`emptyHiddenFromVisitors`), displaying linked section pages with «صفحة» tag, and showing «مفيش عناصر في القسم ده لسه» only when both entries and section pages are empty; (3) formatted collapsed block snippet previews via `blockSnippetSummary` (`'· '` prefix, 40-char truncation, URL-only image suppression) with dialect-aligned «(فاضي)» (`emptyBlockSnippet`); (4) localized admin login email label with `context.tr('emailLabel')` («البريد الإلكتروني»); and (+1) 1,526 passing tests and release web bundle size at `1,375,961 B` gzip (`+23,039 B` headroom under the `1,399,000 B` ceiling).
- **PR #83 Follow-up fixes & test coverage:** (1) Pure `formatAdminError(Object)` in `admin_validators.dart` wired into `DocEditor.save()`, `CollectionListScreen`, `MessagesScreen`, `AdminsScreen`, and `SeasonPresetScreen` to surface structured `FirebaseException.code` (e.g. `[permission-denied]`) + message instead of swallowing or hiding them behind generic exceptions; (2) verified creating a custom category from scratch (`order: null`, `nameEn: ''`, `introAr: ''`, `introEn: ''`, `icon: 'star'`, `showInNav: true`, `visible: true`, `slug`, `updatedAt`, `updatedBy`) in Firestore rules emulator (`tool/rules_test/rules.test.mjs`, 183 suites passed) and Flutter widget tests (`test/admin_test.dart` with `englishEnabled: false` & `true`), plus Checklist 13 & 14 E2E verification (`test/custom_content_test.dart`: empty section hidden from visitor menu + `/section/<slug>` `EmptyState` + admin `'فاضي، مش ظاهر للزوار'` chip, then toggling when a `placement == 'section'` page is linked/unlinked); (3) Undo SnackBar 10s auto-dismiss in `collection_list.dart` with `persist: false`, `_undoSnackBarController`, and 10s `_undoSnackBarTimer` (cleaned up on new delete, undo tap, and `dispose`) so both SnackBar and «تراجع» disappear completely after 10s; (4) empty heading block (`BlockTypes.heading`) validation in `admin_validators.dart` / `admin_strings.dart` (`validateHeadingBlock`, `validateDocument` checking `blockHeadingRequired` / «عنوان الفقرة (عربي) مطلوب.»), wired to `DocEditor` error summary with auto-expand and focus on `textAr`; (5) verified `CustomPageCard` `CardCover`/`FittedCover` renders cleanly at `320px` Home and `/section/<slug>` with zero overflow, confirming no legacy image field fallback added and fonts left untouched per owner directive. All **1,534** tests passing (`flutter test --no-pub`), 0 analyze issues, 183 emulator suites, web bundle gzip **`1,375,798 B`** (`+23,202 B` headroom under `1,399,000 B`).
- **Next action:** Review and verify the stacked PR chain (PR 3A–3J), run servant trial sessions (`G1`–`G3`, item 33), and complete owner/office item 35 before merging.
- **Target:** 2–3 weeks in total across the stages (owner, 13 November).

## قرارات مفتوحة للمالك (Open points for the owner — README §١٥)

All answered by the owner on 13 November 2026 (README §١٠, D1–D5).

- [x] C4 — 30 minutes without use, reset by pointer and keyboard input, 60-second warning, «افتكرني» kept
- [x] C6 — both: hidden in the menu and non-owner writes blocked in the rules (packet P2-18R)
- [x] C7 — design note written: [DESIGN-NOTE-item-28-sitemap.md](DESIGN-NOTE-item-28-sitemap.md); outcome: item 28 deferred
- [x] Item 32 — left out for now

## المرحلة 0 — النهارده ([STAGE-0-live-data.md](STAGE-0-live-data.md))

- [x] 1 — offensive trial notification deleted from «سجل ما أُرسل»; delivery to devices confirmed or ruled out
- [x] 2 — stream switched off, or link set in «اليوم والبث» — public data on 13 November: stream off; owner confirms
- [x] 3 — visible sample data reviewed (47 masses, 4 priests, 4 places unconfirmed on 12 November; 41, 1, 4 on 13 November)
- [x] 4 — donations page for the new building (office) — public data on 13 November: the page exists; office confirms the details
- [x] 5 — `nameEn` stays "Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black" — the owner keeps the live name as the canonical English name (13 November); the shorter name is not used
- [x] **G0** — the owner stated on 13 November 2026 that items 1–5 are resolved (owner's statement; items 1, 3 and 4 cannot be checked without signing in)

## المرحلة 1 — الأمان والصفحات المخصصة ([STAGE-1-safety-and-custom-pages.md](STAGE-1-safety-and-custom-pages.md))

- [x] 6 — confirmation before sending to everyone / «دلوقتي» (P1-06) · PR 3A (`feat/p3a-safe-actions`)
- [x] 7 — «متابعة التعديل» prominent; browser Back, tab close and announcement «إلغاء» warn (P1-07) · PR 3A (`feat/p3a-safe-actions`)
- [x] 8 — 10-second undo after delete; confirmations name the item (P1-08) · PR 3A (`feat/p3a-safe-actions`) — upgraded to Firestore `deletedAt` soft delete + 10s undo + lazy purge on admin open
- [x] 9 — state word next to every switch and on every row (P1-09) · PR 3B (`feat/p3b-written-state`)
- [x] 10 — preview before «يحل محل قداسات اليوم المعتادة» (P1-10) · PR 3B (`feat/p3b-written-state`)
- [x] 11 — fixed bottom save bar (P1-11) · PR 3A (`feat/p3a-safe-actions`)
- [x] 12 — «نشط / موقوف» on every admin, optional end date (P1-12) · PR 3C (`feat/p3c-admin-status-session`)
- [x] 13 — automatic sign-out after 30 minutes with a 60-second warning, «افتكرني» on a personal device (P1-13) · PR 3C (`feat/p3c-admin-status-session`)
- [x] 14 — automatic slug from the Arabic title (P1-14) · PR 3D (`feat/p3d-custom-pages`)
- [x] 15 — ready «صفحة تبرعات» template (P1-15) · PR 3D (`feat/p3d-custom-pages`)
- [x] 16 — one screen for sections and their items (P1-16) · PR 3D (`feat/p3d-custom-pages`)
- [x] 17 — clearer empty state and hints (P1-17) · PR 3D (`feat/p3d-custom-pages`)
- [x] 18a — custom page placement («مكانها فين») and featured on home («مميزة») (P1-18) · PR 3D (`feat/p3d-custom-pages`)
- [ ] Trial session after Stage 1 — date, servant, time taken, stops:
- [ ] **G1**

## المرحلة 2 — الوضوح وتقليل الخطوات ([STAGE-2-clarity-and-fewer-steps.md](STAGE-2-clarity-and-fewer-steps.md))

- [x] 18 — menu from 25 entries to 7 groups (P2-18) · owner-only writes in the rules (P2-18R) · PR 3E (`feat/p3e-menu-home`)
- [x] 19 — title and help line on every screen (P2-19) · PR 3E (`feat/p3e-menu-home`)
- [x] 20 — serving and departed priests merged with a filter (P2-20) · PR 3F (`feat/p3f-forms`)
- [x] 21 — «متقدم» for the owner; no duplicated switches (P2-21) · PR 3E (`feat/p3e-menu-home`)
- [x] 22 — «افتح في الموقع» clearly external; trash away from the eye (P2-22) · PR 3F (`feat/p3f-forms`)
- [x] 23 — new home: «محتاج انتباهك» + the six task buttons (P2-23) · PR 3E (`feat/p3e-menu-home`)
- [x] 24 — phone and photo at the top of the form (P2-24) · PR 3F (`feat/p3f-forms`)
- [x] 25 — inbox opens on «محتاجة رد», with WhatsApp and «تمّت» (P2-25) · PR 3H (`feat/p3h-inbox`)
- [x] 26 — picker for the priests' dates; labels without HH:mm (P2-26) · PR 3F (`feat/p3f-forms`)
- [x] 27 — error summary above the form (P2-27a) · «النسخة الإنجليزية» switch (P2-27b) · PR 3G (`feat/p3g-english-switch`)
- [x] 28 — sitemap updates when a page or section is added (P2-28): design note done, **deferred** — sitemap stays generated at deploy time
- [x] 29 — the assistant names visible sections and pages as topics (P2-29) · PR 3I (`feat/p3i-sitemap-assistant`)
- [ ] Trial session after Stage 2 — date, servant, time taken, stops:
- [ ] **G2**

## المرحلة 3 — الباقي ([STAGE-3-remaining.md](STAGE-3-remaining.md))

- [x] 30 — church info split; clearer coordinates; notice priority explained (P3-30) · PR 3J (`feat/p3j-remaining`)
- [x] 31 — message types: clearer save, confirm before removal, «إعادة كجديدة» harder to hit (P3-31) · PR 3J (`feat/p3j-remaining`)
- [x] 32 — one menu order for built-in and custom sections; item detail pages (optional): **left out** by the owner, 13 November (no work)
- [ ] 33 — trial session with a real servant; panel at 320px; retest of the page jump / lost letters
- [ ] 34 — e-mail invitation of admins: **deferred** (no work)
- [ ] 35 — at least two owner accounts; photo of Abouna Domadius copied locally if it depends on YouTube (office)
- [ ] **G3 — ready for normal use (S1–S5)**

## اتعمل أو اتشال، فمش هنرجع ليه (Done or removed — not reopened)

| Item | State | Note |
|---|---|---|
| The word «العبادات» instead of «العيادات» in a help text | done | not in the current code; every text says «العيادات» |
| Year of a historical milestone without validation | done | now a number field with a minimum of 1 and a maximum of 2200 |
| Dates and time with a picker (ordinary fields) | partly done | ADR-049 / PR #42: 12-hour picker for `date`, `time` and `dateTime`; the rest is item 26 |
| Confirmation when applying a season, and the long-replacement warning | partly done | confirmation and warning in PR #48; the detailed preview for a single mass is item 10 |
| Delete confirmation in lists and when deleting a section | done | confirmed in the trial and the code; what remains is the name + undo (item 8) |
| Custom pages and sections in the sitemap | done | PR #30 / ADR-038, with each deploy; the immediate update is item 28 |
| Tour, «؟» button, full change log | removed from the plan | decision of 12 November; the help line and «آخر تعديل» are enough |
| Invitation of admins by e-mail | deferred | decision of 12 November; if needed: Cloudflare Worker; item 34 describes the current state |
