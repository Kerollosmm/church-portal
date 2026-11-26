# PR 5D — Admin In-File Deduplication (`DocEditor` & `NotificationsAdmin`)

> **Branch:** `refactor/p5d-admin-dedup` (clean `git worktree` from `origin/main` after PR 5C merges)
> **Scope:** Strictly behavior-preserving in-file deduplication. **No** `part of` + `extension on State` + `_updateState` shims, **no** `AdminChip`, **no** `Footer`+barrel.

---

## Packet P5D-1 — In-file deduplication in `lib/ui/admin/doc_editor.dart`

- **Files:** `lib/ui/admin/doc_editor.dart`, `test/admin_test.dart`, `test/custom_content_test.dart`
- **Targets (by symbol):**
  1. **Deduplicate collapsed vs expanded block-row controls** inside `_objectList`:
     - Extract `_moveObjectRow(FieldDef f, int index, int delta)` and `_removeObjectRow(FieldDef f, int index)` on `DocEditorState` and call them from both the collapsed block card and the expanded block card.
  2. **Unify shown-predicates:**
     - Replace `_isFieldShown(FieldDef f)` and `_isSubFieldShown(FieldDef sf, _Row row)` with one `_isShown(FieldDef f, Map<String, dynamic> values)` (called with `_values` or `row.values`).
  3. **Deduplicate block-type lookup & redundant `fields.any((f) => f.key == 'type')` checks:**
     - Extract `String _blockTypeOf(_Row row)` replacing repeated `(row.values['type'] ?? row.text['type']?.text ?? BlockTypes.paragraph).toString()` expressions.
     - Simplify repeated `fields.any((f) => f.key == 'type')` checks in `_Row` init/collect helpers.

### Steps
- [ ] Verify existing tests cover collapsed & expanded block move/remove in `test/custom_content_test.dart`.
- [ ] Apply the 3 in-file deduplications in `lib/ui/admin/doc_editor.dart`.
- [ ] Run `flutter analyze && flutter test test/admin_test.dart test/custom_content_test.dart test/media_test.dart test/admin_pickers_test.dart` → PASS.
- [ ] Commit with explicit pathspecs.

---

## Packet P5D-2 — Collapse `_draft*` state into `_Draft` & remove `LinkTargetLike` in `notifications_admin.dart`

- **Files:** `lib/ui/admin/notifications_admin.dart`, `test/notifications_admin_widget_test.dart`, `test/preview_qa_fixes_test.dart`
- **Targets (by symbol):**
  1. **Single immutable `_Draft` value class:**
     - Replace the 11 `_draft*` snapshot fields (`_draftId`, `_draftSoon`, `_draftDay`, `_draftMinutes`, `_draftTargets`, `_draftLink`, `_draftLinkLabelAr`, `_draftLinkLabelEn`, `_draftEventKey`, plus their `_initialDraft*` mirrors) with an immutable `_Draft` class (`_draft` and `_initialDraft` with `copyWith` and `==` / `hashCode`, keeping the 4 `TextEditingController`s + their initial strings separate).
     - Simplifies dirty comparison (`_draft != _initialDraft`) and draft reset/load.
  2. **Delete single-use `LinkTargetLike`:**
     - Remove `class LinkTargetLike` and change `_knownLink(String path)` to return `({String labelAr, String labelEn})?`.

### Steps
- [ ] Run `flutter test test/notifications_admin_widget_test.dart test/preview_qa_fixes_test.dart` as baseline.
- [ ] Introduce `_Draft` and replace `LinkTargetLike` in `lib/ui/admin/notifications_admin.dart`.
- [ ] Run full verification: `flutter analyze && flutter test`, `flutter build web --release`, `python3 tool/fingerprint_icon_fonts.py build/web`, `node tool/check_web_bundle.mjs build/web` → PASS (`0` deferred leaks, `main.dart.js` gzip `<= 1,399,000 B`).
- [ ] Update `docs/plans/phase5/STATUS.md`, push, run PR review loop, squash-merge, verify deploy.
