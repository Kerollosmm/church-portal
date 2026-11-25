# دليل التنفيذ لنموذج أصغر (Small-Model Guide — Phase 5)

> Every packet in Phase 5 identifies targets by **file path and symbol name**, not fragile line numbers.

---

## ١. استهداف الرموز بدل أرقام الأسطر (Symbol-First Navigation)

Line numbers shift as soon as earlier PRs merge. Always locate targets with `git grep -n "<symbol>" <file>` and read a focused window around the match instead of reading whole giant files.

Read **only**:
1. This guide (`SMALL-MODEL-GUIDE.md`)
2. The active packet in `PR-5<X>`
3. The exact symbol blocks named in that packet.

---

## ٢. القواعد الخمس الأساسية (5 Core Guardrails)

1. **Deferred Chunk Isolation (`0` leaks):**
   - Admin code stays inside `lib/ui/admin/` and is never imported by public files or `test/bundle_isolation_test.dart` public checks.
   - Always verify with `flutter build web --release` + `node tool/check_web_bundle.mjs build/web`.
2. **In-File Simplification Over `part of` Splitting:**
   - Keep `State` classes (`DocEditorState`, `_NotificationsAdminSectionState`) in one file. Do not introduce `part of` + `extension on State` + `_updateState` shims.
3. **Preserve Keys & Race-Condition Coverage:**
   - Never rename or drop `Key(...)` / `ValueKey(...)` attributes.
   - In **PR 5B**, all `14` `testWidgets` behavior tests in `group('PendingDelete')` (slow renewal, failed renewal, rapid 3-delete `undoAll`, FAB 48px clearance, expired-snapshot-during-restore) **must continue passing**.
4. **Honest Behavior Scope:**
   - Do not claim a change is "purely internal" if it alters visible UI (e.g., PR 5B upgrading `MessagesScreen` to batched `"Undo all"`).
5. **Stop & Escalate After 2 Failures:**
   - If the same check fails twice in a row, or a bundle/rules limit trips, stop and report exact output instead of improvising.
