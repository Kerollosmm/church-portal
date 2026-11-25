# PR 5E — Optional File Splits *(Default: SKIP)*

> **Default Action: SKIP.** Only execute any item below if, after PRs 5A–5D are merged, a specific file still materially slows down editing or test runs.

---

## When a Split Is Actually Justified

1. **`lib/ui/admin/admin_screens.dart` (`OverviewScreen`, `ChurchInfoScreen`, `MessagesScreen`, `AdminsScreen`):**
   - These are 4 completely independent `StatefulWidget`s sharing zero state.
   - If split, update callers' imports directly — **do not** leave a re-export barrel file.
2. **Stateless/modal dialogs in `lib/ui/admin/doc_editor.dart`:**
   - Only extract pure standalone dialogs (`_ImageUrlDialog` → `ImageUrlDialog`, `_LooseDatePickerDialog` → `LooseDatePickerDialog`, inline `_pickLink` → `showSimpleLinkPicker`) into `lib/ui/admin/` — never spread `DocEditorState` across `part of` files.
3. **Monolithic test files (`test/admin_test.dart`, `test/custom_content_test.dart`, `tool/rules_test/rules.test.mjs`):**
   - Skip unless targeted test runtime becomes a real bottleneck.
   - If `rules.test.mjs` is ever split, ensure each suite isolates its Firestore emulator state cleanly without introducing flaky concurrency workarounds.
