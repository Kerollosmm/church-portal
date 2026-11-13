# المرحلة 2 — الوضوح وتقليل الخطوات (Stage 2 — clarity and fewer steps)

**Objective:** group the menu, give every screen a title, merge the priests, hide the technical parts, build the
new home, open the important fields, finish the inbox and the English switch, and update the sitemap and the
assistant's topics.

| | |
|---|---|
| **Items** | 18–29 of the unified list (all priority 2) |
| **Owner** | Implementer (smaller model, one packet at a time) · Reviewer · Owner for the gates |
| **Start gate** | G1 passed · C6 answered: menu and rules both (README §١٠ D2) |
| **End gate (G2)** | all packets merged and live · the six-task trial repeated and recorded |
| **Target** | about 1 week of the owner's 2–3 week total (README §١٠ D5): 6 small + 7 medium packets, item 28 deferred |
| **PRs (proposed)** | 3E (18 + 18R, 19, 21, 23) → 3F (20, 22, 24, 26) → 3G (27) → 3H (25) → 3I (29) |

Any change of names in this stage changes, in the same PR, the tests that depend on element keys.

---

## PR 3E — القائمة والرئيسية (Menu and home)

### Packet P2-18 — Menu from 25 entries to 7 groups
Report item: #18 · خطة التبسيط · not started · est. M
Current: `adminDestinations` is still a flat list; seasons / season settings / season preparation are separate.

- **Files:** modify `lib/ui/admin/admin_page.dart`, `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Interface (proposed):** `AdminDest` gains `final AdminGroup group;` with
  `enum AdminGroup { home, schedule, announcements, church, services, pages, messages, ownerSettings }`.
  `adminDestinations(role)` keeps returning every destination; the rail and drawer render them under group
  headers. `ownerSettings` is rendered for owners only.
- **Grouping and names:** exactly the table in README §٥. «المواسم» holds seasons, season settings and season
  preparation; similar names are unified.
- **Tests:** the groups appear in the README order with the README labels · an editor sees seven groups and no
  «الإعدادات (للمالك)» · an owner sees it · every former destination is still reachable.
- **Acceptance:** the side menu shows 7 groups; nothing that existed is lost.

### Packet P2-18R — Owner-only writes in the Firestore rules (owner decision D2)
Owner decision of 13 November 2026 (README §١٠ D2) · ships in the same PR as P2-18 · est. M

Where the three screens write today (checked in the code on 13 November):

| Screen | Document | What the rules allow today |
|---|---|---|
| أنواع الرسائل | `settings/contact` (whole document) | any admin |
| المساعد | `settings/assistant` (whole document) | any admin |
| إعدادات المواسم | `settings/features`, keys `venues`, `audiences`, `seasonVerses` only | any admin |

- **Files:** modify `firestore.rules` (`match /settings/{docId}`); test `tool/rules_test/rules.test.mjs`; update
  `docs/memory-bank/05-firebase.md` and the Arabic manual in the same PR.
- **Rule (proposed):** `settings/contact` and `settings/assistant` create / update require `isOwner()`.
  `settings/features` stays writable by any admin, **except** that a write which changes `venues`, `audiences` or
  `seasonVerses` requires `isOwner()`.
- **Why key-level for seasons:** `settings/features` is shared. «اليوم والبث» and «التطبيق والإشعارات» write to
  the same document, and editors must keep editing the stream and the section switches. Locking the whole
  document would break task T1/T2 for editors.
- **Reads:** unchanged. `settings/*` stays publicly readable except `notifications`: the contact form needs the
  message types, the assistant needs its settings, and the mass / meeting / season forms need venues and
  audiences.
- **Budget:** the rules evaluate at most 1,000 expressions per request and `validFeatures` already works near
  that limit; reuse its existing `changed` set for the three-key check rather than recomputing it.
- **Tests (rules):** an active non-owner admin cannot write `settings/contact` or `settings/assistant` · the same
  admin can still save «اليوم والبث» (a `settings/features` write that leaves the three keys untouched) · the same
  admin is refused when the write changes `venues` · the owner can do all of them · anonymous reads of
  `settings/contact`, `settings/assistant` and `settings/features` still succeed.
- **Acceptance:** a non-owner editor neither sees the three screens nor can change their data by any route.

### Packet P2-19 — Title and help line on every screen
Report item: #19 · خطة التبسيط · not started · est. S
Current: one field in the code can cover the 14 lists; not added yet.

- **Files:** modify `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/collection_list.dart`,
  `lib/ui/admin/admin_screens.dart`; test `test/admin_test.dart`.
- **Interface (proposed):** `CollectionDef.help` and `DocDef.help` — an l10n key for one line shown under the
  screen title. Example text: «هنا مواعيد القداسات الأسبوعية. التعديل بيظهر على الموقع على طول».
- **Tests:** every `adminCollections` entry and every settings document has a non-empty help line in Arabic ·
  the line renders under the title at 320 px without overflow.
- **Acceptance:** every screen explains itself in one line; there is no tour and no «؟» button.

### Packet P2-21 — «متقدم» for the owner; no duplicated switches
Report item: #21 · خطة التبسيط · not started · est. M
Current: the Sentry test button is still in «الأقسام والصفحة الرئيسية»; the assistant is repeated in three
places; time labels still show HH:mm.

- **Files:** modify `lib/ui/admin/features_editor.dart`, `lib/ui/admin/admin_page.dart`,
  `lib/ui/admin/assistant_admin.dart`, `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Behaviour:** App Check, Sentry, APK, the queues and the season keys move to «متقدم» inside «الإعدادات
  (للمالك)». Each switch exists in one place only. No label in front of the ordinary editor contains Firebase,
  UID, App Check or HH:mm.
- **Tests:** an editor's screens contain none of those words · the assistant switch is found in exactly one
  place · the Sentry test button is under «متقدم» only.
- **Acceptance (S3):** not one English or technical word in front of the ordinary editor.

### Packet P2-23 — New home: «محتاج انتباهك» + the six task buttons
Report item: #23 · خطة التبسيط · not started · est. M
Current: «نظرة عامة» is still 16 cards of equal size, with «غير مؤكد: N» unexplained.

- **Files:** create `lib/domain/attention.dart`; modify `lib/ui/admin/admin_screens.dart`
  (`OverviewScreen`); test `test/domain_test.dart`, `test/admin_test.dart`.
- **Interface (proposed):**
  `List<AttentionItem> attentionItems({required int newMessages, required List<Alert> alerts, required int unconfirmed, required bool streamOn, required String streamUrl, required bool englishOn, required int missingEnglish, required DateTime now})`
  — returns, in this order: new messages · notices about to end · unconfirmed data · stream on with no link ·
  (when the English version is on) items missing their English.
- **Task buttons:** «عدّل المواعيد» · «+ إعلان» · the inbox on «محتاجة رد» · edit a service · add a priest ·
  «صفحة تبرعات» — the six tasks T1–T6 of README §٣.
- **Tests:** each condition alone produces its one entry · none of them produces an empty "all clear" state ·
  stream on with an empty link is listed · each task button opens the right screen.
- **Acceptance (T1, T2):** editing a mass time takes 3 steps from the home; a new announcement takes 4.

---

## PR 3F — النماذج (Forms)

### Packet P2-20 — Merge serving and departed priests
Report item: #20 · خطة التبسيط · not started · est. M
Current: two screens over the same fields; the risk of entering the same person twice remains.

- **Files:** modify `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/collection_list.dart`,
  `lib/ui/admin/admin_page.dart`; test `test/admin_test.dart`.
- **Behaviour:** one «الآباء» screen with a «يخدم / متنيح» filter. Order values keep their separate ranges so the
  two lists never collide.
- **Tests:** the filter shows only serving, only departed · a new item under «متنيح» is saved as departed ·
  reordering one group never changes the other's order values.
- **Acceptance:** one place to find any father.

### Packet P2-22 — «افتح في الموقع» is clearly external; trash away from the eye
Report item: #22 · خطة التبسيط · partial · est. S
Current: tooltips exist (`openItemOnSite` / delete / hide); in the trial the icon was taken for "edit".

- **Files:** modify `lib/ui/admin/collection_list.dart`; test `test/admin_test.dart`.
- **Behaviour:** pressing the row opens editing. The open-on-site control uses an external-link icon. The trash
  icon is separated from the eye icon and carries a visible name.
- **Tests:** tapping a row opens the editor · the trash and eye controls are not adjacent · the existing keys
  (`openItem-<id>`) still find the control.
- **Acceptance:** nobody opens the public page while trying to edit.

### Packet P2-24 — Phone and photo at the top of the form
Report item: #24 · خطة التبسيط · not started · est. S
Current: both still sit inside an `ExpansionTile` that is closed by default, in services, priests and others.

- **Files:** modify `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/doc_editor.dart`; test `test/admin_test.dart`.
- **Interface (proposed):** `FieldDef.advanced` (bool). Name, photo, phone and time are basic and open; English,
  order and links are `advanced` and render under «خيارات متقدمة».
- **Tests:** on a service the phone field is visible without opening any card · on a priest the photo, name and
  rank are the first fields · a field under «خيارات متقدمة» still validates and saves while closed.
- **Acceptance (T4, T5):** editing a service's phone takes 3 steps; adding a priest with a photo takes 5.

### Packet P2-26 — Picker for the priests' dates; time labels without HH:mm
Report item: #26 · خطة التبسيط · partial · est. S
Current: the 12-hour picker exists for `time`, `date` and `dateTime` (ADR-049); the priests' dates (`looseDate`)
are still text; labels still say «(HH:mm)».

- **Files:** modify `lib/ui/admin/doc_editor.dart`, `lib/core/l10n.dart`; test `test/admin_pickers_test.dart`.
- **Behaviour:** `looseDate` fields get a picker with Arabic month names and still accept typing. Labels lose
  «(HH:mm)». Stored values are unchanged.
- **Tests:** picking a date fills a valid loose date · typing a year alone is still accepted · no label contains
  `HH:mm` · stored time stays 24-hour.
- **Acceptance:** dates use a picker and 12-hour time everywhere.

---

## PR 3G — ملخص الأخطاء والنسخة الإنجليزية (Error summary and the English version)

### Packet P2-27a — Error summary above the form
Report item: #27 (first half) · خطة التبسيط · not started · est. S
Current: errors show under the field only.

- **Files:** modify `lib/ui/admin/doc_editor.dart`, `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Behaviour:** on a failed save a summary appears at the top, «فيه حقلين محتاجين تصحيح», listing each field;
  pressing an entry scrolls to and focuses that field (opening its card if closed).
- **Tests:** two invalid fields produce a summary of two · pressing an entry focuses the field · the summary
  clears when the errors are fixed.

### Packet P2-27b — «النسخة الإنجليزية» switch
Report item: #27 (second half) · خطة التبسيط · decided, not built · est. M · no server

- **Files:** modify `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/doc_editor.dart`,
  `lib/ui/admin/admin_validators.dart`, `lib/domain/features.dart`, `firestore.rules`, `tool/rules_test/`,
  `tool/gen_seed.py`, `lib/ui/widgets/app_shell.dart` (the public language toggle); test `test/admin_test.dart`, `test/features_test.dart`.
- **Data contract:** one boolean on `settings/features` **(proposed key `englishEnabled`, missing = on)**, written
  by owners only, kept out of the legacy allow-list.
- **Interface:** the `lang: en` mark on `FieldDef` (decided). `DocEditor` skips marked fields while the feature is
  off: not shown, not required, not validated, not in the error summary.
- **Rules:** fields ending in `En` stay optional. Saving a document while English is off must not delete its
  stored English values.
- **Public site:** the EN button disappears while off.
- **Tests:** off → no `lang: en` field is rendered and a form with only Arabic saves · off → the stored English of
  an edited document is untouched · on → the fields return with their values · an editor cannot write the key
  (rules) · off → the public EN button is absent · on → items missing English are counted for «محتاج انتباهك».
- **Acceptance:** forms are about half as long with English off, and nothing is lost when it comes back.

---

## PR 3H — صندوق الرسائل (Inbox)

### Packet P2-25 — Inbox opens on «محتاجة رد», with WhatsApp and «تمّت»
Report item: #25 · خطة التبسيط · partial · est. S
Current: call and e-mail buttons exist; the default filter is still «جديدة»; no WhatsApp.

- **Files:** modify `lib/ui/admin/admin_screens.dart` (`MessagesScreen`), `lib/core/l10n.dart`; test
  `test/admin_test.dart`.
- **Behaviour:** the inbox opens filtered on «محتاجة رد». Each message has call, WhatsApp and «تمّت» in the same
  step. The WhatsApp button appears only when the message has a phone number.
- **Tests:** the default filter is «محتاجة رد» · a message with a phone shows WhatsApp, one without does not ·
  «تمّت» marks it handled and it leaves the default view.
- **Acceptance (T3):** replying to a visitor takes 2 steps.

---

## PR 3I — خريطة الموقع والمساعد (Sitemap and assistant)

### Packet P2-28 — Sitemap updates when a page or section is added
Report item: #28 · الصفحات المخصصة · not started · est. M
Current: PR #30 put custom pages and sections in the sitemap; it updates with each deploy only.

- **Step 1 (done, 13 November):** the design note is
  [DESIGN-NOTE-item-28-sitemap.md](DESIGN-NOTE-item-28-sitemap.md).
- **Outcome:** the Worker route is more than a small addition, so by the owner's rule (README §١٠ D3) the item is
  **deferred** and the sitemap stays generated at deploy time by `tool/build_sitemap.sh` /
  `tool/gen_sitemap.dart`. No code in this stage.
- **If reopened:** the note lists a smaller route that reuses the existing generator; it needs the owner's
  approval first.

### Packet P2-29 — The assistant names visible sections and pages as topics
Report item: #29 · الصفحات المخصصة · not started · est. S
Current: the content is fed to the assistant (PR #19), but the topics list is fixed and general.

- **Files:** modify `lib/domain/assistant_context.dart`; test `test/assistant_context_test.dart`.
- **Behaviour:** the topics list includes the names of the visible custom sections and pages; hidden ones never
  appear. The assistant's model and limits are unchanged.
- **Tests:** a visible section's name is in the topics · a hidden page's name is not · with no custom content the
  list equals today's.
- **Acceptance:** a visitor can ask about a custom page by its name.

---

## بوابة نهاية المرحلة (End gate G2)

- [ ] PRs 3E–3I merged and live; `flutter analyze` clean; all tests and rules tests green.
- [ ] Memory bank and Arabic documentation updated in each PR.
- [ ] Step counts measured against README §٣: T1 = 3, T2 = 4, T3 = 2, T4 = 3, T5 = 5, T6 = 5.
- [ ] S2 holds (every daily task 5 steps or fewer) and S3 holds (no English or technical word for the editor).
- [ ] Trial session repeated; stops recorded in [STATUS.md](STATUS.md).

## مخاطر تستحق المراجعة (Review focus)

1. English switched off, then a document saved: its stored English must survive.
2. Menu regrouping: deep links and tests that find screens by key keep working.
3. Priests merged: order ranges of serving and departed never collide.
4. «محتاج انتباهك» must not add Firestore reads beyond what the overview already listens to.
5. A message with a malformed phone number: the WhatsApp button must not open a broken link.
