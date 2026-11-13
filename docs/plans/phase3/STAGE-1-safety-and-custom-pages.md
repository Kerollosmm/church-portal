# المرحلة 1 — الأمان والصفحات المخصصة (Stage 1 — safety and custom pages)

**Objective:** nothing is lost and nothing is sent by mistake; custom pages take fewer steps. Covers the send
confirmation, the risk of losing edits, delete with undo, the written state of switches, the preview of replaced
masses, the save bar, stopping an admin, automatic slug, the donations template and the merged sections screens.

| | |
|---|---|
| **Items** | 6–17 of the unified list (all priority 1, except item 17 which is priority 2 — README §١٥ C5) |
| **Owner** | Implementer (smaller model, one packet at a time) · Reviewer · Owner for the gates |
| **Start gate** | G0 passed (items 1–5 verified) · sign-out value chosen: 30 minutes (README §١٠ D1) |
| **End gate (G1)** | all packets merged and live · trial session with a servant who has never seen the panel, six tasks without help, stops recorded |
| **Target** | about 1 week of the owner's 2–3 week total (README §١٠ D5): 5 small + 7 medium packets |
| **PRs (proposed)** | 3A (6, 7, 8, 11) → 3B (9, 10) → 3C (12, 13) → 3D (14, 15, 16, 17) |

Names marked **(proposed)** are for the implementer and reviewer to keep consistent across packets; the report
does not fix them. Arabic strings are the report's and are used verbatim.

---

## PR 3A — الأفعال الآمنة (Safe actions)

### Packet P1-06 — Confirmation before sending to everyone
Report item: #6 · خطة التبسيط · Priority 1 · not started · est. S
Current: `_saveDraft` saves and sends with no dialog; confirmation exists only for delete and for clearing the log.

- **Files:** modify `lib/ui/admin/notifications_admin.dart`, `lib/core/l10n.dart`; create
  `lib/ui/admin/confirm_named.dart`; test `test/notifications_admin_widget_test.dart`.
- **Interface (proposed):**
  `Future<bool> confirmNamedAction(BuildContext context, {required String summary, required String actionLabel, bool destructive = false})`.
  Called from `_saveDraft` whenever the draft goes to everyone or is sent «دلوقتي».
  Summary: «هيتبعت لكل المشتركين دلوقتي: [العنوان]». Action button: «ابعت للكل».
- **Tests:** saving a send-to-everyone draft shows the dialog with the draft's title · cancelling writes nothing ·
  confirming writes exactly once · a draft that is neither "to everyone" nor «دلوقتي» saves without the dialog.
- **Acceptance:** no path sends a notification to everyone without the named confirmation.

### Packet P1-07 — Unsaved edits: right button, browser Back, tab close, announcement «إلغاء»
Report item: #7 · خطة التبسيط · Priority 1 · not started · est. M
Current: «تجاهل» is still a `FilledButton`; no `beforeunload`; cancelling an announcement closes without asking.

- **Files:** create `lib/ui/admin/unsaved_guard.dart`; modify `lib/ui/admin/doc_editor.dart`,
  `lib/ui/admin/notifications_admin.dart`; test `test/admin_test.dart`.
- **Interface (proposed):** `class UnsavedGuard extends StatefulWidget { final bool dirty; final Widget child; }`
  — intercepts in-app back and side-menu navigation with the leave dialog, and on the web registers
  `beforeunload` while `dirty` is true (conditional import so the Android build imports no web API).
  Leave dialog: «متابعة التعديل» is the `FilledButton`; «تجاهل» is a text button.
- **Tests:** in the leave dialog «متابعة التعديل» is the filled button · back with a dirty form shows the dialog,
  with a clean form it does not · announcement «إلغاء» with typed text asks first · choosing a side-menu entry
  with a dirty form asks first.
- **Acceptance:** no way out of a dirty form loses work without the dialog (X, «إلغاء», in-app back, side menu,
  browser Back, tab close).

### Packet P1-08 — 10-second undo after delete; confirmations name the item
Report item: #8 · خطة التبسيط · Priority 1 · not started · est. M
Current: delete asks a generic confirmation; postponed undo is not built.

- **Files:** create `lib/ui/admin/pending_delete.dart`; modify `lib/ui/admin/collection_list.dart`,
  `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Interface (proposed):**
  `class PendingDelete { PendingDelete({Duration window = const Duration(seconds: 10)}); void schedule(String id, Future<void> Function() commit); bool undo(String id); Future<void> flush(); }`
  The row disappears at once, a bar shows «اتمسح · تراجع» with the item's name for 10 seconds, and the real delete
  (including the item's media cleanup) runs when the window ends. `flush()` runs on leaving the screen.
- **Behaviour fixed by the report:** item delete (priest, service, notice, page) = immediate + undo. The section
  delete keeps its explanatory confirmation and now names the section. No server is involved.
- **Tests:** deleting hides the row and calls no backend delete before 10 s · «تراجع» restores the row and no
  delete is ever sent · after 10 s exactly one delete is sent · leaving the screen commits the pending delete ·
  the bar text contains the item's title.
- **Acceptance:** an item deleted by mistake is back with one press within 10 seconds, with its images intact.

### Packet P1-11 — Fixed bottom save bar
Report item: #11 · خطة التبسيط · Priority 1 · not started · est. M
Current: the save button sits in a different place from screen to screen.

- **Files:** create `lib/ui/admin/unsaved_bar.dart`; modify `lib/ui/admin/doc_editor.dart` and the settings
  editors that save (`features_editor.dart`, `contact_admin.dart`, `assistant_admin.dart`); test
  `test/admin_test.dart`.
- **Interface (proposed):**
  `class UnsavedBar extends StatelessWidget { final bool dirty; final VoidCallback onSave; final VoidCallback onCancel; final bool saving; }`
  Text: «فيه تعديلات مش محفوظة · حفظ · إلغاء». Shown only while `dirty`; pinned to the bottom above the keyboard.
- **Tests:** the bar is absent on a clean form and present after an edit · «حفظ» calls the editor's save once ·
  the bar does not overflow at 320 px in Arabic and English.
- **Acceptance:** on every editing screen the save control is in the same place.

---

## PR 3B — الحالة المكتوبة (Written state)

### Packet P1-09 — State word next to every switch and on every row
Report item: #9 · خطة التبسيط · Priority 1 · not started · est. S
Current: switches carry no written state and are easy to read backwards in RTL.

- **Files:** create `lib/ui/admin/state_switch.dart`; modify `lib/ui/admin/doc_editor.dart`,
  `lib/ui/admin/features_editor.dart`, `lib/ui/admin/collection_list.dart`; test `test/admin_test.dart`.
- **Interface (proposed):**
  `class AdminStateSwitch extends StatelessWidget { final bool value; final ValueChanged<bool>? onChanged; final String onLabel; final String offLabel; }`
  Label pairs: «ظاهر / مخفي» for visibility, «مفعّل / مقفول» for features. Rows show ظاهر, مخفي, منتهي or
  «بيانات تجريبية».
- **Tests:** the label reads the on-word when true and the off-word when false, in RTL and LTR · every boolean
  field rendered by `DocEditor` uses `AdminStateSwitch` · a list row of a hidden item shows «مخفي».
- **Acceptance:** no switch in the panel is without its state word; the public stream, notifications and
  unconfirmed-data switches all show it.

### Packet P1-10 — Preview before «يحل محل قداسات اليوم المعتادة»
Report item: #10 · خطة التبسيط · Priority 1 · partial · est. M
Current: a long hint on the field (ADR-050) and a replacement warning in season preparation (PR #48); no list of
the masses that will be hidden.

- **Files:** modify `lib/domain/schedule.dart` (where `replacesDay` is already decided), `lib/ui/admin/doc_editor.dart`;
  test `test/domain_test.dart`, `test/admin_test.dart`.
- **Interface (proposed):** a pure function
  `List<Liturgy> liturgiesHiddenBy(Liturgy replacing, Iterable<Liturgy> all)` that reuses the same rule the public
  page applies, so the preview can never disagree with the site.
- **UI:** when the checkbox is on, the form shows «القداسات دي مش هتظهر يوم كذا» followed by the list (name and
  time, 12-hour).
- **Tests:** a one-off feast mass on a weekday hides that weekday's usual masses and nothing else · with the
  checkbox off the list is empty · the preview list equals what the public schedule hides for the same data.
- **Acceptance:** the editor sees which masses disappear before saving.

---

## PR 3C — حالة المشرف والجلسة (Admin status and session)

### Packet P1-12 — «نشط / موقوف» on every admin, optional end date
Report item: #12 · خطة التبسيط · Priority 1 · decided, not started · est. M
Decision: needs an `active` field in `admins` and Firestore rules; runs on Spark with no server.

- **Files:** modify `firestore.rules`, `tool/rules_test/`, `lib/data/admin_repository.dart`,
  `lib/ui/admin/admin_screens.dart` (`AdminsScreen`), `lib/ui/admin/admin_page.dart` (role check),
  `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Data contract:** `admins/{uid}.active` — boolean, a missing field means active. Optional end date
  `admins/{uid}.expiresAt` **(proposed name)** — timestamp; absent = no end.
- **Rules (proposed):** `isAdmin()` and `isOwner()` also require `active != false` and, when the end date exists, that the
  request time is before it. Only an owner writes these two fields, and never on their own document, so an owner
  always remains. Include a worst-case whole-document test for the rules budget.
- **UI:** in `AdminsScreen`, an `AdminStateSwitch` «نشط / موقوف» per admin with a simple confirmation, and an
  optional end-date picker. A stopped account that signs in sees a clear "stopped" message and Sign out; the
  account document is not deleted.
- **Tests (rules):** a stopped editor cannot write content · a stopped editor cannot read `contact_messages` ·
  an expired editor is refused · re-enabling restores access · an editor cannot change `active` · an owner cannot
  stop themselves. **Tests (widget):** the switch shows «موقوف» for a stopped admin; toggling asks once.
- **Acceptance (S5):** the owner stops or re-enables an admin from the panel with one press; the temporary editor
  edits all content while active; settings and admins stay owner-only.

### Packet P1-13 — Automatic sign-out on the office device, «افتكرني» on a personal device
Report item: #13 · خطة التبسيط · Priority 1 · decided, not built · est. M

- **Files:** create `lib/ui/admin/session_policy.dart`; modify `lib/ui/admin/admin_page.dart` (login form and
  dashboard); test `test/admin_test.dart`.
- **Interface (proposed):**
  `class SessionPolicy { const SessionPolicy({required this.idleLimit, required this.warnBefore}); bool shouldWarn(Duration idle); bool shouldSignOut(Duration idle); }`
  — pure Dart. **Decided values (D1):** `idleLimit` = 30 minutes, `warnBefore` = 60 seconds. A widget around
  `AdminDashboard` resets the idle clock on **both** pointer and keyboard input, shows a warning prompt 60 seconds
  before the limit (so at 29 minutes idle) with a way to stay signed in, then signs out.
- **Login:** a «افتكرني» checkbox. Ticked = personal device: the session persists and no idle sign-out runs.
  Unticked = shared office device: idle sign-out applies.
- **Tests:** `shouldWarn` / `shouldSignOut` at the boundaries (29:00 warns, 30:00 signs out) · a pointer event and
  a key event each reset the clock · input during the warning cancels it · activity resets the clock · with «افتكرني» ticked
  no sign-out happens · at the limit with a dirty form the unsaved-edits warning is shown before sign-out.
- **Acceptance:** an unattended shared device signs itself out after 30 minutes without use, 60 seconds after a
  warning; a personal device with «افتكرني» ticked stays signed in.

---

## PR 3D — الصفحات المخصصة (Custom pages)

### Packet P1-14 — Automatic link (slug) from the Arabic title
Report item: #14 · الصفحات المخصصة · Priority 1 · not started · est. S
Current: the field is required and typed by hand in English for pages and sections.

- **Files:** modify `lib/ui/admin/admin_validators.dart`, `lib/ui/admin/admin_schema.dart`,
  `lib/ui/admin/doc_editor.dart`; test `test/custom_content_test.dart`.
- **Interface (proposed):** `String slugFromTitle(String title, {required Set<String> taken})` — pure and
  deterministic; its output always passes the existing slug validator and is unique against `taken`.
- **Behaviour:** a new page or section gets its link from the Arabic title with no typing. The field is shown and
  editable only under «متقدم». An existing item's link never changes when its title changes.
- **Tests:** an Arabic title yields a valid slug · two equal titles yield two different slugs · an empty or
  symbol-only title still yields a valid slug · editing the title of a saved page leaves its slug as it was.
- **Acceptance:** an ordinary editor creates a page without ever seeing the word slug.

### Packet P1-15 — Ready «صفحة تبرعات» template
Report item: #15 · الصفحات المخصصة · Priority 1 · not started · est. S
Current: the donation paragraph type exists; there is no whole-page template with title, paragraphs and link.

- **Files:** modify `lib/ui/admin/collection_list.dart` (the pages list's add action),
  `lib/ui/admin/admin_schema.dart`, `lib/core/l10n.dart`; test `test/custom_content_test.dart`.
- **Behaviour:** adding a page offers «صفحة تبرعات». Choosing it opens the editor with the title, the paragraph
  blocks and the donation block already laid out, and the link made automatically (P1-14). Account, InstaPay and
  wallet fields are **empty** for the office to fill.
- **Tests:** the template produces a document that passes `validateDocument` once the empty fields are filled ·
  the template contains no account number, phone or name · steps from "add" to "saved" are 5 or fewer.
- **Acceptance (T6):** the donations page takes 5 steps instead of 10–13.

### Packet P1-16 — One screen for sections and their items
Report item: #16 · الصفحات المخصصة · Priority 1 · not started · est. M
Current: two separate screens; adding an item needs an existing section, and the required «القسم» list starts
empty.

- **Files:** modify `lib/ui/admin/collection_list.dart`, `lib/ui/admin/admin_page.dart`,
  `lib/ui/admin/doc_editor.dart`; test `test/custom_content_test.dart`.
- **Behaviour:** one screen lists each section with its items under it. «+» inside a section opens the item
  editor with «القسم» already chosen. Deleting a section keeps its explanatory confirmation.
- **Tests:** the screen shows items grouped under their section · adding from inside a section pre-selects it ·
  with no sections the screen shows the empty state of P1-17.
- **Acceptance:** an editor adds a section and its first item without changing screens.

### Packet P1-17 — Clearer empty state and hints for sections and items
Report item: #17 · الصفحات المخصصة · Priority 2 · not started · est. S
Current: the section help text points to «الأقسام والصفحة الرئيسية» and «عناوين الصفحات»; hints are small and
technical.

- **Files:** modify `lib/core/l10n.dart`, `lib/ui/admin/collection_list.dart`; test `test/custom_content_test.dart`.
- **Behaviour:** empty lists say what to do: «مفيش أقسام لسه · + أضف أول قسم». Hints are larger and do not send
  the reader to another screen.
- **Tests:** the empty sections screen shows the text and a working add button · no hint string names another
  screen.
- **Acceptance:** a new editor facing an empty list knows the next press.

---

## بوابة نهاية المرحلة (End gate G1)

- [ ] PRs 3A–3D merged and live; `flutter analyze` clean; all tests and rules tests green.
- [ ] Memory bank and Arabic documentation updated in each PR.
- [ ] Trial session: a servant who has never seen the panel does the six tasks without help; where they stop is
      recorded in [STATUS.md](STATUS.md).
- [ ] S4 holds: no irreversible action without a confirmation that names the item.
- [ ] S5 holds: an admin is stopped and re-enabled from the panel with one press.

## مخاطر تستحق المراجعة (Review focus)

1. A tab closed during the 10-second window: the item must stay (delete not sent), never half-deleted.
2. A stopped admin with the dashboard already open: the live role stream must lock the dashboard at once.
3. Idle sign-out while a form is dirty: the work is not dropped silently.
4. Two admins: one deletes with undo pending while the other edits the same item.
5. Rules budget: the `active` / end-date checks on the largest settings document save.
