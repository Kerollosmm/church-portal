# Admin UI Phase 1 (Quick Wins) Implementation Plan — rev. 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `/admin` dashboard usable for a non-technical church volunteer for daily tasks — grouped nav, clearer lists/forms, unified fathers screen, written switch/row states, and an inbox that opens on needs-reply with WhatsApp — without Phase 2/3 features.

**Architecture:** Fix shared admin layers so one change improves all screens: nav shell (`admin_page.dart`), list rows (`collection_list.dart`), field placement (`admin_schema.dart`), switches (new shared `state_switch.dart` used by `doc_editor.dart` and the settings screens), inbox (`admin_screens.dart`), strings (`l10n.dart`), one small pure helper file in `lib/domain/`. Public feature keys (`Sections.departedPriests`, etc.) stay unchanged; the fathers merge is admin-only. No Firestore field is added, renamed or removed, so the 4-places rule (model / schema / rules / seed) is not triggered.

**Tech Stack:** Flutter (Dart), Material UI via `package:material_ui/material_ui.dart`, AdminBackend fakes in widget tests, `flutter test` / `flutter analyze` / `scripts/verify.sh`.

**Spec source:** Owner report `admin-simplification-plan.md` (12 Nov 2026) — Phase 1 only — plus the owner's decisions of 13 Nov 2026 (section "Owner decisions" below).

## Revision log (rev. 2, 13 Nov 2026)

| # | Change vs rev. 1 | Why |
|---|---|---|
| F1 | Task 3 no longer adds a second note widget; it reuses the existing `Key('admin-collectionNote')` text in `_toolbar` (`collection_list.dart` L168–173). | rev. 1 would render every note twice. |
| F2 | The shared `_contactPhoneField` / `_plainContactsGroup` are **not** changed. Collection-specific basic phone fields are used instead. | rev. 1 pushed a phone into saints / milestones / priests. |
| F3 | Basic-field order is now locked per collection: image → Arabic name → rank or phone → the rest. | rev. 1 put the priest photo under 9 fields. |
| F4 | Sidebar: Overview and Messages are direct tiles; Settings group (seasonSettings, assistant, contactCats, admins) is owner-only. | Owner decision 1; matches report §4. |
| F5 | Every row shows a written status; delete is separated from the eye toggle and has a «حذف» label; narrow rows wrap actions. Every boolean switch shows its state in words. | Owner decisions 3 and 4; report §5.2, §3.4. |
| F6 | Adding from the unified fathers list while the «متنيح» chip is on starts the doc with `status: departed` and the next free departed `order`. | rev. 1 left `_pushEditor` passing empty `newDefaults`. |

## Owner decisions (13 Nov 2026)

1. **Sidebar:** Overview («الرئيسية») and Messages («الرسائل») are direct one-tap tiles; Messages shows the needs-reply count. `contactCats`, `seasonSettings`, `assistant` (and `admins`) live in the owner-only group «الإعدادات (للمالك)».
2. **Basic fields:** do not touch `_contactPhoneField` / `_plainContactsGroup`; no phone on saints / milestones. Phone goes to `FieldGroup.basic` only on services (`facilities`), `activities`, `clinics` (and priests only if a priest-specific phone exists — it does not today, see Open question Q3). Image goes to basic on `priests`, `saints`, `facilities`, `activities`. Order inside basic: image, Arabic name, then rank (priests) or phone (services / clinics), then English fields and descriptions.
3. **Rows:** written badge on every row (`ظاهر` / `مخفي`, `منتهي` for expired, `بيانات تجريبية` for sample rows); delete separated from the eye and labelled «حذف»; at 320–400 px actions wrap under the title and badges.
4. **Switches:** written state on all boolean switches in `DocEditor` and the settings screens: `ظاهر` / `مخفي` for visibility switches (`visible`, `showContacts`, `detailsEnabled`, other `show*`), `مفعّل` / `موقوف` for activation / behaviour switches (`active`, `enabled`, `replacesRegular`, `replacesDay`, …).

## Open questions (must be answered before Task 5 / Task 3 merge)

- **Q1 — Is "owner-only" UI-only or enforced?** `firestore.rules` L563–570 lets any admin (`isAdmin()`) write `settings/contact`, `settings/assistant` and `settings/features`. Hiding the screens stops honest editors, not a determined one. Options: (a) UI gate only in Phase 1 and record the gap; (b) also add `isOwner()` for `docId == 'contact'` and `docId == 'assistant'` (about 2 expressions, cheap). `seasonSettings` writes the same `settings/features` doc as the editor-facing «اليوم والبث» screen, so it cannot be rule-gated without field-level rules on that doc (rules budget, golden rule 3). Default in this plan: **(a)**, with the gap written in the memory bank.
- **Q2 — Vocabulary for `sample`.** The owner chose «بيانات تجريبية» for the row badge. The editor field label is «غير مؤكد (في انتظار تأكيد الكنيسة)», the filter chip is «غير المؤكد», and public pages show a "pending confirmation" notice. The data is real-but-unconfirmed, not test data. Default in this plan: badge uses the owner's «بيانات تجريبية»; the filter chip `filter_unconfirmed` is renamed to «البيانات التجريبية» so list and filter match; the editor field label stays as is. Confirm or pick one word for all three.
- **Q3 — Priest phone.** Priests only have the shared `contactPhone` from `_plainContactsGroup`. Promoting it needs a priest-only contacts list. Default: leave priests' phone in «التواصل»; no change.
- **Q4 — Clinics image.** Not in the owner's image list, so the clinic image stays in «الصور». Confirm.

## Global Constraints

- Never invent church content; no seed changes.
- Business logic stays pure Dart in `lib/domain/` with unit tests; time via `CairoTime`.
- Strings go in `lib/core/l10n.dart` as `[ar, en]`; UI uses `context.tr` / `context.pick`.
- Keep `flutter analyze` clean and tests green; do not force-push; never commit secrets. Work on `feat/admin-phase-1-quick-wins`.
- Same PR updates `docs/memory-bank/07-admin-dashboard.md`, Arabic `documentation/features/admin-dashboard.md`, `documentation/features/contact-form-and-inbox.md`, `documentation/features/about-priests-saints.md`, and an ADR (`scripts/new_adr.sh`) for the owner-only settings group and the fathers merge.
- Responsive acceptance at 320 / 400 / 1400 px, Arabic RTL and English LTR, owner and editor roles.
- Out of scope: English feature toggle, admin `active`, session timeout, 10 s undo delete, send-to-all confirm, sticky save bar, browser-back dirty guard, auto-slug, "Needs attention" home, six task shortcuts, email invites.
- Destination **ids** (`overview`, `priests`, `messages`, …) keep working for `_screen()` and overview `onOpen`. Existing test keys stay: `nav-<id>`, `openItem-<id>`, `filter-new`, `admin-collectionNote`, `field-<key>`, and tooltips `Delete` / `Open detail page on site`.

---

## File structure (locked)

| File | Action | Responsibility |
|---|---|---|
| `lib/domain/admin_status.dart` | Create | Pure helpers: `isExpired(data, now)`, `nextOrder(docs, base)`, `priestStatusOf(data)` |
| `test/admin_status_test.dart` | Create | Unit tests for the helpers |
| `lib/ui/admin/state_switch.dart` | Create | `SwitchKind`, `switchKindFor(key)`, `StateSwitchTile` |
| `lib/core/l10n.dart` | Modify | needs-reply, nav groups, row states, switch states, screen hints |
| `lib/ui/admin/admin_page.dart` | Modify | `AdminNavGroup`, direct tiles, grouped ExpansionTiles, owner gate in `_screen()`, Messages badge |
| `lib/ui/admin/admin_schema.dart` | Modify | Basic image/phone per collection, field order, `noteAr`/`noteEn` everywhere, priests CollectionDef unfiltered, optional `FieldDef.switchKind` |
| `lib/ui/admin/collection_list.dart` | Modify | Priest status chips, chip-aware reorder and new-doc defaults, row badges, separated actions, narrow layout |
| `lib/ui/admin/doc_editor.dart` | Modify | Boolean fields (L674 and L1297) use `StateSwitchTile` |
| `lib/ui/admin/admin_screens.dart` | Modify | Inbox label + WhatsApp, Overview single fathers card, fixed-screen hints |
| `lib/ui/admin/features_editor.dart`, `assistant_admin.dart`, `contact_admin.dart`, `notifications_admin.dart`, `occasion_editor.dart` | Modify | Replace `SwitchListTile` with `StateSwitchTile`; bare `Switch` at `features_editor.dart` L717 gets a state text next to it |
| `test/admin_test.dart`, `test/accessibility_test.dart`, `test/live_loading_test.dart`, `test/custom_content_test.dart` | Modify | New cases + update affected ones (listed per task) |
| docs listed above | Modify | Same-PR docs |

---

### Task 0: Pure helpers in `lib/domain/admin_status.dart`

**Interfaces (produced):**

```dart
/// True when data['endsAt'] is a DateTime before [now] (alerts, seasons).
bool isExpired(Map<String, dynamic> data, DateTime now);

/// 'serving' | 'departed' (missing / blank = 'serving', like Priest.fromMap).
String priestStatusOf(Map<String, dynamic> data);

/// Next free `order` for a new item: max existing order among [docs] + 10,
/// never below [base] + 10 (base 0 = serving, 1000 = departed).
int nextOrder(Iterable<Map<String, dynamic>> docs, {int base = 0});
```

- [ ] **Step 1: failing tests** in `test/admin_status_test.dart`: expired true/false/missing/`endsAt` not a DateTime; `priestStatusOf` for missing, `''`, `'serving'`, `'departed'`; `nextOrder([], base: 1000) == 1010`, `nextOrder([{order:1020},{order:1010}], base:1000) == 1030`, ignores non-int orders, `nextOrder([], base: 0) == 10`.
- [ ] **Step 2:** implement; `now` is passed in by callers as `CairoTime.now()` (no clock inside the helper).
- [ ] **Step 3:** `flutter test test/admin_status_test.dart` → PASS. Commit `feat(domain): admin row status and order helpers`.

---

### Task 1: Inbox — needs-reply label + WhatsApp

**Files:** `lib/core/l10n.dart`, `lib/ui/admin/admin_screens.dart`, `test/accessibility_test.dart`.

- [ ] **Step 1: failing test** (near the MessagesScreen tests): Arabic `_adminApp`, one open message with phone → expect `find.text('محتاجة رد')` (exact chip label, not `textContaining`), `ValueKey('whatsapp-m1')`, `ValueKey('filter-new')`. Check which locale `_adminApp` uses and assert that locale's string.
- [ ] **Step 2:** `l10n.dart`: `'msg_new': ['محتاجة رد', 'Needs reply']`. Reuse the existing `'whatsapp'` key (L132) — do not add it again. Also align the Overview stat label `newMessages` to the same wording («رسائل محتاجة رد») so the home card and the inbox chip say the same thing.
- [ ] **Step 3:** in `_message` (`admin_screens.dart` ~L538), after the call chip:

```dart
if (phone.isNotEmpty)
  ActionChip(
    key: ValueKey('whatsapp-${d.id}'),
    avatar: const Icon(Icons.chat_rounded, size: 16),
    label: Text(context.tr('whatsapp')),
    onPressed: () => openWhatsApp(phone),
  ),
```

  Confirm `openWhatsApp` exists in `lib/core/launch.dart` with that signature and normalises Egyptian `01…` numbers to `20…`; if it does not normalise, use the same normaliser the public pages use. Anonymous messages have no phone, so no chip.
- [ ] **Step 4:** tests PASS. Commit `feat(admin): inbox needs-reply label and WhatsApp chip`.

---

### Task 2: Schema — basic image/phone with locked order + notes everywhere

**Files:** `lib/ui/admin/admin_schema.dart`, `test/admin_test.dart`.

**Do not change** `_contactPhoneField`, `_plainContactsGroup`, `_meetingMediaGroup`, or the `alerts` / `seasons` / `entries` / `pages` / `milestones` / `meetings` / `clinics` image fields.

- [ ] **Step 1: failing tests**

```dart
FieldDef fd(String c, String k) => collectionById(c)!.fields.firstWhere((f) => f.key == k);
List<String> basicKeys(String c) =>
    [for (final f in collectionById(c)!.fields) if (f.group == FieldGroup.basic) f.key];

test('basic image/phone placement and order (owner decision 2)', () {
  expect(basicKeys('priests').take(3), ['image', 'name', 'rank']);
  expect(basicKeys('saints').take(2), ['image', 'nameAr']);
  expect(basicKeys('facilities').take(3), ['image', 'nameAr', 'phone']);
  expect(basicKeys('activities').take(3), ['image', 'titleAr', 'contactPhone']);
  expect(basicKeys('clinics').take(3), ['doctorName', 'specialtyAr', 'bookingPhone']);
  // No phone leaks.
  for (final c in ['saints', 'milestones', 'priests']) {
    expect(fd(c, 'contactPhone').group, FieldGroup.contacts, reason: c);
  }
  expect(fd('meetings', 'contactPhone').group, FieldGroup.contacts);
  expect(fd('milestones', 'image').group, FieldGroup.media);
  expect(fd('clinics', 'image').group, FieldGroup.media);
  // Exactly one `image` per collection.
  for (final c in adminCollections) {
    expect(c.fields.where((f) => f.key == 'image').length, lessThanOrEqualTo(1), reason: c.id);
  }
});

test('every collection has a help note', () {
  for (final c in adminCollections) {
    expect(c.noteAr, isNotEmpty, reason: c.id);
    expect(c.noteEn, isNotEmpty, reason: c.id);
  }
});
```

- [ ] **Step 2:** new constants:

```dart
const _coverImageBasic = FieldDef('image', 'الصورة (اختياري)', 'Image (optional)', FieldType.image);
const _mediaGroupNoCover = [_imageStyleField, _showDetailImagesField, _galleryField];
const _contactPhoneBasic = FieldDef('contactPhone', 'تليفون التواصل', 'Contact phone', FieldType.phone);
```

- [ ] **Step 3: reorder fields** (only list order and group change; keys, types, labels, validation stay):
  - `_priestFields`: `_coverImageBasic, name, rank, status, nameEn, ordinationDate, hegumenDate, departedDate, bioAr, bioEn, order, visible, sample, ..._detailsGroup, ..._mediaGroupNoCover, ..._plainContactsGroup`.
  - `saints`: `_coverImageBasic, nameAr, nameEn, bioAr, …` and `..._mediaGroupNoCover` instead of `..._mediaGroup`.
  - `facilities`: `_coverImageBasic, nameAr, phone (group basic), type, nameEn, descAr, …`; remove `phone` from its contacts block; `..._mediaGroupNoCover`.
  - `activities`: `_coverImageBasic, titleAr, _contactPhoneBasic, category, titleEn, …`; remove `_contactPhoneField` from its contacts block; `..._mediaGroupNoCover`.
  - `clinics`: `doctorName, specialtyAr, bookingPhone (group basic), specialty, specialtyEn, degreeAr, …`; remove `bookingPhone` from its contacts block; keep `..._mediaGroup`.
- [ ] **Step 4:** verify `DocEditor` renders basic fields in list order (read its build loop); if it sorts by group then by original index, the above is enough. Run `admin_test.dart` L425–439 (clinic editor) and `media_test.dart` — they find fields by key, so order changes must not break them.
- [ ] **Step 5: notes.** Fill `noteAr` / `noteEn` for every CollectionDef that has none (alerts, seasons, liturgies, meetings, clinics, facilities, activities, priests, departedPriests, saints, milestones, entries, pages; `categories` already has one — keep it). One plain sentence each, no Firebase / slug words. Example: liturgies `'هنا مواعيد القداسات الأسبوعية. التعديل يظهر على الموقع على طول.'` / `'Weekly liturgy times. Changes show on the site straight away.'`. Priests: `'كل الآباء في شاشة واحدة. اختر «يخدم» أو «متنيح» فوق القائمة.'`.
- [ ] **Step 6:** tests PASS. Commit `feat(admin): image and phone first in daily forms, notes on every list`.

---

### Task 3: Rows — written status, separated actions, narrow layout, reuse the note

**Files:** `lib/ui/admin/collection_list.dart`, `lib/core/l10n.dart`, `test/accessibility_test.dart`, `test/custom_content_test.dart`.

- [ ] **Step 1: failing tests**
  1. `collection list shows the schema note once`: `facilities` list → `find.byKey(Key('admin-collectionNote'))` `findsOneWidget` and `find.text(def.noteAr)` `findsOneWidget`.
  2. `row badges`: docs `{visible:true}`, `{visible:false}`, `{sample:true}`, alert `{endsAt: past}` → badges `ظاهر`, `مخفي`, `بيانات تجريبية`, `منتهي` each found.
  3. `delete is labelled and separate`: `find.widgetWithText(TextButton, 'حذف')` per row; `find.byTooltip('Delete')` still found in English (wrap the button in a `Tooltip`).
  4. `narrow rows wrap actions` at `Size(320, 800)` and `Size(400, 800)`, Arabic, text scale 1.0 and 2.0: no overflow (`tester.takeException()` is null), the row title `Text` is not clipped (`find.text(title)` hit-testable), actions found below the title.
- [ ] **Step 2: note.** Do **not** add a new widget. `_toolbar` already renders `def.noteAr` with `Key('admin-collectionNote')` (L168–173). Fix only its condition so English-only notes also show: `if (def.noteAr.isNotEmpty || def.noteEn.isNotEmpty)`. Task 2 fills the notes, so every list now shows one.
- [ ] **Step 3: l10n keys:** `'statusShown': ['ظاهر', 'Shown']`, `'statusExpired': ['منتهي', 'Expired']`, `'statusSample': ['بيانات تجريبية', 'Sample data']`; reuse `'hidden'` for مخفي. Per Q2, `'filter_unconfirmed'` → `['البيانات التجريبية', 'Sample data']`.
- [ ] **Step 4: badges** in `_tile` title row (after the title): `if (def.hasVisible) _Tag(hidden ? tr('hidden') : tr('statusShown'), hidden ? muted : success)`, `if (isExpired(d.data, CairoTime.now())) _Tag(tr('statusExpired'), alert)`, `if (unconfirmed) _Tag(tr('statusSample'), goldText)`. Keep the existing `⛔ متوقف` subtitle part for `active == false`.
- [ ] **Step 5: actions.**
  - Eye toggle keeps its `IconButton` and tooltip `show` / `hide`.
  - Delete becomes `Tooltip(message: tr('delete'), child: TextButton.icon(key: ValueKey('delete-${d.id}'), icon: Icon(Icons.delete_outline), label: Text(tr('delete')), style: foreground alert))`, preceded by `SizedBox(width: 12)` (wide) so it is not next to the eye.
  - Open-on-site item button keeps `ValueKey('openItem-${d.id}')` and tooltip `openItemOnSite`; on wide rows (`>= 600`) use `TextButton.icon(icon: open_in_new, label: Text(tr('openItemOnSiteShort')))` with new key `'openItemOnSiteShort': ['افتح في الموقع', 'Open on site']`, wrapped in a `Tooltip` with the existing long text so `find.byTooltip('Open detail page on site')` still finds 2.
- [ ] **Step 6: narrow layout (< 600 px).** `trailing: null`; under the subtitle a `Wrap(spacing: 4, runSpacing: 4, children: [...moves, ?openItem, eye, delete])`. Wide: `trailing` row as today plus the gap before delete. Title `Text` gets `maxLines: 2` instead of one-line ellipsis so the badge never pushes it to `…` at 320 px.
- [ ] **Step 7: update tests:** `custom_content_test.dart` L549–550, `accessibility_test.dart` L1090, L1192–1196, L1292 should still pass via tooltips; adjust only if a finder relied on `IconButton` type.
- [ ] **Step 8:** tests PASS. Commit `feat(admin): written row status, labelled delete, wrapped actions on phones`.

---

### Task 4: Written state on every switch

**Files:** `lib/ui/admin/state_switch.dart` (new), `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/doc_editor.dart`, the five settings screens, `lib/core/l10n.dart`, tests.

**Interfaces (produced):**

```dart
enum SwitchKind { visibility, activation }

/// visibility: visible, detailsEnabled, showContacts, showSocials,
/// showDetailImages, showInNav, showSuggestions, any other key starting
/// with 'show'. Everything else: activation.
SwitchKind switchKindFor(String key);

class StateSwitchTile extends StatelessWidget {
  const StateSwitchTile({super.key, required this.title, required this.value,
      required this.onChanged, this.kind = SwitchKind.activation, this.hint = '',
      this.contentPadding});
  // subtitle: '<state>' or '<state> — <hint>'; state from l10n:
  // visibility → switchShown/switchHidden, activation → switchOn/switchOff.
}
```

- [ ] **Step 1: failing tests:** `switchKindFor` table (`visible`, `showContacts`, `detailsEnabled` → visibility; `active`, `enabled`, `replacesRegular`, `replacesDay`, `sample`, `isMobile` → activation); widget test: `DocEditor` for `alerts` shows `مفعّل` / `موقوف` under «مُفعّل» and `ظاهر` under «ظاهر في الموقع»; toggling flips the text; hint text still shown after the state.
- [ ] **Step 2:** `FieldDef` gains optional `final SwitchKind? switchKind;` (default null → `switchKindFor(key)`). No rules / seed impact (UI-only property).
- [ ] **Step 3:** l10n: `'switchShown': ['ظاهر','Shown']`, `'switchHidden': ['مخفي','Hidden']`, `'switchOn': ['مفعّل','On']`, `'switchOff': ['موقوف','Off']`.
- [ ] **Step 4:** `doc_editor.dart` L674 (top-level boolean) and L1297 (objectList row boolean, e.g. `isMobile`) use `StateSwitchTile` with the same `ValueKey('field-${f.key}')`.
- [ ] **Step 5:** replace `SwitchListTile` in `features_editor.dart` (L447, 457, 484, 492, 502, 531, 549, 591, 601), `assistant_admin.dart` (L92, 108), `contact_admin.dart` (L191, 198), `notifications_admin.dart` (L864, 1422, 1636), `occasion_editor.dart` (L170, 187, 196). Keep every existing key. Pick `kind` per switch from what it controls (section on/off in Features = visibility). The bare `Switch` at `features_editor.dart` L717 gets a small state `Text` beside it.
- [ ] **Step 6:** run `flutter test` for every touched screen's test file (`features_test`, `assistant_test`, `contact_*`, `app_settings_admin_test`, notifications tests). Commit `feat(admin): every switch says its state in words`.

---

### Task 5: Unified fathers list (status chips, reorder, new-doc defaults, overview)

**Files:** `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/collection_list.dart`, `lib/ui/admin/admin_screens.dart`, `lib/core/l10n.dart`, `test/admin_test.dart`, `test/accessibility_test.dart`.

**Interfaces (produced):**
- `collectionById('priests')!.filter == null`, label «الآباء» / «Fathers», `orderable: true`.
- `collectionById('departedPriests')` still exists (filter `status: departed`, `newDefaults {'status':'departed'}`) for public-path tests and `reorderBase` — not shown in the nav.
- Chip keys `ValueKey('priestStatus-serving' | 'departed' | 'all')`, default `serving`. Labels `'priestServing': ['يخدم','Serving']`, `'priestDeparted': ['متنيح','Departed']`, reuse `filter_all`.
- `reorderBase` becomes `int reorderBase(CollectionDef def, {String? priestStatus})`: `departedPriests` or `priestStatus == 'departed'` → 1000, else 0.

- [ ] **Step 1: failing tests**
  1. Schema: priests unfiltered; departedPriests filter + base 1000 kept.
  2. Widget: unified list shows only serving by default; tap `priestStatus-departed` → only departed; `priestStatus-all` → both, and no drag handles / `moveUp-*` keys (reorder off).
  3. Reorder on departed chip: move-down on a departed row → fake backend records `reorder('priests', ids, base: 1000)`.
  4. **F6:** with the departed chip on, tap Add, save the minimal form → saved data has `status == 'departed'` and `order == nextOrder(departedDocs, base: 1000)`; with serving chip → `status == 'serving'`, `order == nextOrder(servingDocs, base: 0)`; with `all` chip → serving defaults.
  5. Overview: one «الآباء» card with value = all priests and sub-line `يخدم: N • متنيح: M`; no departed card.
- [ ] **Step 2:** schema change as above. Rename priests labels to «الآباء» / «Fathers».
- [ ] **Step 3:** `_CollectionListScreenState` gets `String _priestStatus = 'serving';` used only when `def.id == 'priests'`. Filtering: after `def.matches`, keep docs where `_priestStatus == 'all' || priestStatusOf(d.data) == _priestStatus`. `canReorder` additionally requires `_priestStatus != 'all'` for priests.
- [ ] **Step 4:** `_reorder` passes `reorderBase(def, priestStatus: _priestStatus)`.
- [ ] **Step 5 (F6):** `_pushEditor` computes defaults instead of passing `def.newDefaults` as-is:

```dart
Map<String, Object?> _newDefaults() {
  if (def.id != 'priests') return def.newDefaults;
  final status = _priestStatus == 'departed' ? 'departed' : 'serving';
  final base = status == 'departed' ? 1000 : 0;
  final same = [for (final x in _lastDocs) if (priestStatusOf(x.data) == status) x.data];
  return {...def.newDefaults, 'status': status, 'order': nextOrder(same, base: base)};
}
```

  `_lastDocs` must hold **all** priests (it is set from `all` before chip filtering — keep it that way). Only used for new docs (`d == null`).
- [ ] **Step 6:** Overview `_countCard` loop skips `departedPriests`; the priests card shows the sub-counts (via `priestStatusOf`) plus hidden / unconfirmed as today.
- [ ] **Step 7:** update `accessibility_test.dart` L864 (keep), L1061 (switch to unified list + departed chip; keep base-1000 assertion), `admin_test.dart` L139 and L357 (keep — def still exists).
- [ ] **Step 8:** tests PASS. Commit `feat(admin): one fathers list with serving / departed chips`.

---

### Task 6: Sidebar — direct tiles, groups, owner-only settings, Messages badge

**Files:** `lib/ui/admin/admin_page.dart`, `lib/core/l10n.dart`, `test/admin_test.dart`, `test/live_loading_test.dart`, `test/accessibility_test.dart`, and destination-id tests (`season_preset_test`, `today_widgets_test`, `program_test`).

**Interfaces (produced):**

```dart
class AdminNavGroup {
  final String id, labelAr, labelEn;
  final List<String> destIds;
  /// A single-destination entry drawn as a plain tile (no ExpansionTile).
  final bool direct;
  final bool ownerOnly;
  const AdminNavGroup(this.id, this.labelAr, this.labelEn, this.destIds,
      {this.direct = false, this.ownerOnly = false});
}
List<AdminNavGroup> adminNavGroups(String role); // owner-only groups dropped for editors
List<AdminDest> adminDestinations(String role);  // flat, derived from groups, same order
bool isOwnerOnlyDest(String id);                 // seasonSettings, assistant, contactCats, admins
```

**Locked map:**

| # | id | Label | Destinations | Kind |
|---|---|---|---|---|
| 1 | `home` | الرئيسية / Home | `overview` | direct |
| 2 | `schedule` | المواعيد / Schedule | `liturgies`, `meetings`, `today`, `seasons`, `seasonPreset` | group |
| 3 | `announcements` | الإعلانات / Announcements | `alerts`, `app` | group |
| 4 | `church` | الكنيسة / Church | `priests`, `saints`, `milestones`, `church` | group |
| 5 | `services` | الخدمات والأنشطة / Services & activities | `facilities`, `activities`, `clinics` | group |
| 6 | `pages` | الصفحات / Pages | `features`, `pages`, `categories`, `entries` | group |
| 7 | `messages` | الرسائل / Messages | `messages` | direct, badge |
| 8 | `settings` | الإعدادات (للمالك) / Settings (owner) | `seasonSettings`, `assistant`, `contactCats`, `admins` | group, ownerOnly |

The `overview` destination label becomes «الرئيسية» / «Home» so the tile and AppBar title match the report.

- [ ] **Step 1: failing tests**

```dart
test('nav groups: no duplicates, departed hidden, owner-only settings', () {
  final owner = adminNavGroups(AdminRoles.owner);
  final flat = [for (final g in owner) ...g.destIds];
  expect(flat.toSet().length, flat.length);
  expect(flat, isNot(contains('departedPriests')));
  expect(adminDestinations(AdminRoles.owner).map((d) => d.id).toList(), flat);
  expect(owner.where((g) => g.direct).map((g) => g.id), ['home', 'messages']);
  final editor = adminDestinations(AdminRoles.editor).map((d) => d.id);
  for (final id in ['seasonSettings', 'assistant', 'contactCats', 'admins']) {
    expect(editor, isNot(contains(id)), reason: id);
  }
  // Every collection and fixed screen except departedPriests is reachable by the owner.
  for (final c in adminCollections) {
    if (c.id != 'departedPriests') expect(flat, contains(c.id));
  }
});
```

  Widget tests: (a) editor dashboard with `initial: 'assistant'` shows `ownerOnly` text (direct-URL / stale-state guard); (b) Messages tile shows `2` with two open messages and updates to `1` after one is marked handled; (c) Overview and Messages tiles are `ListTile`s not inside an `ExpansionTile`; (d) opening `liturgies` from Overview's `onOpen` expands the «المواعيد» group.
- [ ] **Step 2:** implement `adminNavGroups` / `adminDestinations` / `isOwnerOnlyDest` with a private `_destById` map (fixed screens + collections except `departedPriests`).
- [ ] **Step 3: `_screen()` owner gate:** at the top, `if (isOwnerOnlyDest(_current) && widget.role != AdminRoles.owner) return Center(child: Text(context.tr('ownerOnly')));` (replaces the admins-only branch). A live demotion (role stream) therefore drops the screen at once.
- [ ] **Step 4: `_nav`:** for each group: `direct` → one `ListTile(key: nav-<id>)` with the same colours as today; for Messages, `trailing:` a `Badge`/count pill when `openCount > 0`. Non-direct → `ExpansionTile(key: navGroup-<id>, controller: _groupCtl[id])` whose children are the `nav-<id>` tiles. Keep one `ExpansibleController` per group (same type `doc_editor.dart` already uses); in `_open(id)` expand the group that contains `id`. Initially only the current destination's group is expanded.
- [ ] **Step 5: Messages count.** `_AdminDashboardState` subscribes once to `widget.repo.watch('contact_messages')` in `initState` (re-bind in `didUpdateWidget` when `repo` changes, cancel in `dispose`) and keeps `_openMessages = docs.where((d) => messageIsOpen(d.data)).length`. Errors → no badge. Firestore multiplexes identical queries on one client, and Overview already watches this collection, so this adds no extra document reads.
- [ ] **Step 6: update tests that assume a flat menu.**
  - `live_loading_test.dart` L499–534: tiles inside collapsed groups are not built. Before the loop, expand every group (`tap(find.byKey(ValueKey('navGroup-$id')))` for each non-direct group), then keep all colour assertions; also assert direct tiles keep the same colours.
  - `accessibility_test.dart` L998–1023 (owner): `nav-seasonSettings` is in the collapsed Settings group — tap `navGroup-settings` first; `nav-today` is in the already-expanded Schedule group.
  - `season_preset_test`, `today_widgets_test`, `program_test`: re-run; fix only finders, never ids.
- [ ] **Step 7:** run `flutter test test/admin_test.dart test/live_loading_test.dart test/accessibility_test.dart test/season_preset_test.dart test/today_widgets_test.dart test/program_test.dart`. Commit `feat(admin): grouped sidebar with direct Home and Messages, owner-only settings`.

---

### Task 7: Fixed-screen help lines

**Files:** `lib/core/l10n.dart`, `lib/ui/admin/admin_screens.dart` (Messages, Admins), `features_editor.dart`, `notifications_admin.dart` (App), `assistant_admin.dart`, `season_preset_admin.dart`, `contact_admin.dart`, and the `ChurchInfoScreen` call sites for `today` / `seasonSettings` / `church` (pass a `header`).

- [ ] **Step 1:** keys `messagesHint`, `featuresHint`, `todayHint`, `seasonSettingsHint`, `seasonPresetHint`, `churchHint`, `assistantHint`, `appHint`, `contactCatsHint` — one plain sentence each, `[ar, en]`. `AdminsScreen` already has `adminsHelp`; keep it.
- [ ] **Step 2:** one muted `Text` under each screen's existing top area, key `ValueKey('screenHint-<destId>')`. For `ChurchInfoScreen` use the existing `header` parameter; for `assistant` (which already passes a status-card header) put the hint inside that header.
- [ ] **Step 3: test:** for each fixed destination id, pump the dashboard as owner with `initial: id` and expect `screenHint-<id>` `findsOneWidget`. Commit `feat(admin): one-line help under every fixed admin screen`.

---

### Task 8: Docs, ADR, full gate

- [ ] `docs/memory-bank/07-admin-dashboard.md`: new nav map (direct tiles, groups, owner-only settings and the Q1 rules gap), unified fathers + chips + reorder bases, written row/switch states, inbox wording + WhatsApp, basic image/phone per collection.
- [ ] `documentation/features/admin-dashboard.md` (Arabic, real labels from code), `contact-form-and-inbox.md` («محتاجة رد», واتساب), `about-priests-saints.md` («الآباء» + يخدم / متنيح / الكل).
- [ ] ADR via `scripts/new_adr.sh`: "Admin Phase 1 — grouped nav, owner-only settings (UI gate), unified fathers list".
- [ ] `docs/memory-bank/11-open-tasks.md`: Phase 2 / 3 items and Q1 rules follow-up if (a) is chosen.
- [ ] Gate: `flutter analyze`, `flutter test`, `bash scripts/verify.sh`. Manual check at 320 / 400 / 1400 px, Arabic and English, owner and editor.
- [ ] Commit `docs: record admin Phase 1 navigation, rows, switches and inbox`.

---

## Self-review (spec coverage)

| Phase 1 requirement | Task |
|---|---|
| Inbox opens on needs-reply + WhatsApp | 1 |
| Group nav + rename, direct Home / Messages, owner-only settings | 6 |
| Merge priests + departed (admin), correct defaults on Add | 5 |
| Open phone + photo fields, locked order, no leaks | 2 |
| Written status on rows and on every switch | 3, 4 |
| Title + help line per screen | 2–3 (collections), 7 (fixed) |
| Public `departedPriests` section unchanged | 5 |
| Docs + ADR same PR | 8 |
| Excluded Phase 2/3 | Global Constraints |

**Known risks:** collapsed groups break tests that expect every `nav-*` tile to be built (handled in Task 6 Step 6); owner-only is UI-only until Q1 is decided; wording for `sample` (Q2); `StateSwitchTile` touches five settings screens — run their tests individually.

## Execution handoff

Start on branch `feat/admin-phase-1-quick-wins` from up-to-date `main`. Order: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 (5 depends on 0 and 3; 6 depends on 5 for the departed exclusion). Answer Q1–Q4 before Task 3 and Task 6 are merged. Do not implement Phase 2/3 in this branch.
