# PR 5B — Simplify Soft-Delete & 10s Undo, Then Share with `MessagesScreen`

> **Branch:** `refactor/p5b-simplify-undo` (clean `git worktree` from `origin/main`)
> **Prerequisite:** Wait for / merge open **PR #99** (`lib/ui/admin/collection_list.dart`) and **PR 5A** before starting.
> **Explicit Behavior Note:** Upgrading `MessagesScreen` to share batched `"Undo all"` is a **deliberate visible UX improvement** (not strictly behavior-preserving).

---

## Packet P5B-1 — Simplify `PendingDelete` & `CollectionListScreen` undo first

- **Files:** `lib/ui/admin/pending_delete.dart`, `lib/ui/admin/collection_list.dart`, `test/admin_test.dart`
- **Problem:** `CollectionListScreen` currently holds ~350 lines of undo glue (`_pendingDelete`, `_pendingEntries`, `_inFlightDeleteWrites`, `_deleteGen`, `_restoringIds`, `_undoSnackBar*`, `_fabCooldownTimer`, `_deferredErrorSnacks`) paired with `holdAll`/`releaseHold` anchor timers in `PendingDelete`. Wrapping that complexity verbatim into a 10-parameter controller just moves the complexity.
- **Target Design:**
  1. Simplify soft-delete batching to **one shared batch deadline + serialized per-ID write guard** and one shared lazy-purge helper (`purgeExpiredSoftDeletes`).
  2. Keep FAB elevation & 650 ms cooldown (`_UndoClearFabLocation`, `_FabSnackHeightTracker`) local to `CollectionListScreen` (the only screen with a FAB) — do **not** push FAB layout concerns into a shared undo helper.
  3. **Race-Condition Constraint (Critical):** Only remove `holdAll`/`releaseHold` if the simplified batch guard passes **all `14` existing `testWidgets` behavior tests** in `group('PendingDelete')` of `test/admin_test.dart` (slow renewal, failed renewal, rapid 3-delete atomic `undoAll`, FAB 48px clearance, expired-snapshot-during-restore, lazy purge after 10s).

### Steps
- [ ] Run `flutter test test/admin_test.dart --name "PendingDelete"` as baseline and record pass count.
- [ ] Simplify `PendingDelete` and extract the non-FAB soft-delete + undo helper in `lib/ui/admin/pending_delete.dart` (or `soft_delete_helper.dart` inside `lib/ui/admin/`).
- [ ] Wire `CollectionListScreen` to the simplified helper while keeping `_UndoClearFabLocation` local.
- [ ] Run `flutter analyze && flutter test test/admin_test.dart test/custom_content_test.dart` → assert all `14` `testWidgets` behavior tests PASS.
- [ ] Commit with explicit pathspecs.

---

## Packet P5B-2 — Wire `MessagesScreen` to the simplified undo helper

- **Files:** `lib/ui/admin/admin_screens.dart` (`MessagesScreen`), `test/admin_test.dart`, `docs/memory-bank/07-admin-dashboard.md`
- **Rules:**
  - Keep `confirmNamedAction(...)` confirmation dialog **before** soft-deleting a message in `MessagesScreen._delete`.
  - Use `deletedUndo` for single-message undo and `deletedItemMultiUndo` when multiple messages are pending undo, with `removeMedia: false`.
  - Preserve `MessagesScreen`'s existing `ValueKey`s and SnackBar copy.

### Steps
- [ ] Add a `testWidgets` test in `test/admin_test.dart` (`MessagesScreen`) verifying rapid 2-message soft-delete shows batched `"Undo all"` and restores both messages (`deletedAt: null`) with `0` hard deletes.
- [ ] Wire `MessagesScreen` (`_checkLazyPurge`, `_delete`) to the shared simplified helper.
- [ ] Run `flutter analyze && flutter test`, `flutter build web --release`, `node tool/check_web_bundle.mjs build/web` → confirm PASS and `0` deferred leaks.
- [ ] Update `docs/memory-bank/07-admin-dashboard.md` (noting batched undo in Inbox) and `docs/plans/phase5/STATUS.md`, push, run PR review loop, squash-merge, verify deploy.
