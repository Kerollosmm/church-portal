# دليل التنفيذ بنموذج أصغر (Building Phase 3 with a smaller flash-class model)

The report's work is many small, similar edits to a few shared files. That shape suits a smaller, faster coding
model, provided each task arrives fully decided. This file fixes how tasks are cut, handed over and checked.
Read [README.md](README.md) first.

## ١. لماذا يصلح نموذج أصغر (Why a smaller model fits)

- The fixes change shared parts — `admin_schema.dart`, `collection_list.dart`, `doc_editor.dart` — so one change
  repairs 14 screens at once. Each change is narrow and repeats an existing pattern.
- Nothing needs a server or a new service (Spark only, 0 servers), so there is no infrastructure design left to
  the implementer.
- Every design choice is already made in the report (§٤–§١٠ of the README). The model implements; it does not
  decide.

## ٢. تقسيم المكوّنات (Component approach)

Each stage file lists **packets**. A packet is one report item (or one half of it) and builds one small component
with a stated interface. Shared components come first so that later packets only consume them.

| Component **(proposed names)** | File | Used by items |
|---|---|---|
| `AdminStateSwitch` — a switch with its state word («ظاهر / مخفي», «مفعّل / مقفول») | `lib/ui/admin/state_switch.dart` (new) | 9, 12, 21, 27 |
| `UnsavedBar` — fixed bottom bar «فيه تعديلات مش محفوظة · حفظ · إلغاء» | `lib/ui/admin/unsaved_bar.dart` (new) | 11, 31 |
| `UnsavedGuard` — leave dialog with «متابعة التعديل» primary, plus browser Back / tab-close warning | `lib/ui/admin/unsaved_guard.dart` (new) | 7, 13 |
| `PendingDelete` — 10-second postponed delete with «اتمسح · تراجع» | `lib/ui/admin/pending_delete.dart` (new) | 8 |
| `confirmNamedAction` — confirmation that names the item and uses a clear-verb button | `lib/ui/admin/confirm_named.dart` (new) | 6, 8, 12, 31 |
| `FieldDef.lang`, `FieldDef.advanced`, `CollectionDef.help` | `lib/ui/admin/admin_schema.dart` | 19, 24, 27 |
| `ErrorSummary` — «فيه حقلين محتاجين تصحيح», each line jumps to its field | `lib/ui/admin/doc_editor.dart` | 27 |
| `attentionItems(...)` — pure function for «محتاج انتباهك» | `lib/domain/` | 23 |

Existing files the packets touch (from `lib/ui/admin/README.md` and `docs/memory-bank/07-admin-dashboard.md`):
`admin_page.dart` (`adminDestinations(role)`, `AdminDest`), `admin_schema.dart` (`FieldDef`, `CollectionDef`,
`DocDef`), `collection_list.dart` (`CollectionListScreen`), `doc_editor.dart` (`DocEditor`), `admin_screens.dart`
(`OverviewScreen`, `MessagesScreen`, `AdminsScreen`), `notifications_admin.dart` (`_saveDraft`),
`contact_admin.dart` (`saveContactCats`), `features_editor.dart`, `admin_validators.dart`, `lib/core/l10n.dart`,
`lib/data/admin_repository.dart`, `firestore.rules`, `tool/rules_test`, `tool/gen_seed.py`.

## ٣. حدود الحزمة (Packet limits)

A packet handed to the smaller model must satisfy all of these; if it cannot, split it.

1. One report item, one outcome a reviewer can accept or reject alone.
2. At most three source files changed plus their tests and strings.
3. The interface is written out: names, parameters, return types, the Arabic strings verbatim from the report.
4. The tests are named before the code: file, test name, what is asserted.
5. No decision is left open. An open decision is a gate for the owner, not a task for the model.
6. No church content is invented (times, names, phones, account numbers). Templates ship empty.

## ٤. قالب الحزمة (Packet brief template)

```markdown
### Packet P<stage>-<item><letter> — <title>
Report item: #<n> · Category · Priority · Size
Depends on: <packet ids or "none">
Files: <create / modify / test — exact paths>
Interface: <signatures, keys, strings>
Steps:
- [ ] Write the failing test(s) named below
- [ ] Run them and see them fail
- [ ] Implement the interface
- [ ] flutter analyze && flutter test
- [ ] (rules changed) cd tool/rules_test && npm ci && npm test
- [ ] Update docs/memory-bank + documentation/ (Arabic) in the same PR
Acceptance: <observable checks>
Out of scope: <what this packet must not touch>
```

Context to give the model with each packet: this guide, the packet, `AGENTS.md`, `lib/ui/admin/README.md`, the
matching section of `docs/memory-bank/07-admin-dashboard.md`, and only the files the packet names.

## ٥. قواعد ثابتة (Standing rules for the implementer)

From `AGENTS.md` and the report:

- A field change touches four places together: the model, `admin_schema.dart`, `firestore.rules`, the seed
  (`tool/gen_seed.py`) — plus tests. Keep new keys out of the legacy allow-list on large settings docs and add a
  worst-case whole-document emulator test (rules budget of 1,000 expressions).
- Strings go in `lib/core/l10n.dart` as `[ar, en]`. Arabic labels are copied exactly from the stage files.
- A change of names changes the tests that depend on element keys in the same PR, and updates the memory bank in
  the same PR.
- Every admin screen works at 320 px, in RTL and LTR, with switches in both states.
- Pure logic goes in `lib/domain/` with unit tests; time logic goes through `CairoTime`.
- Stored formats do not change: times stay `"HH:mm"` in Firestore even when the label no longer shows `HH:mm`.
- No server, no Blaze, no new paid service.

Commands:

```bash
flutter pub get
flutter analyze
flutter test                                # sandbox/proxy: NO_PROXY=127.0.0.1,localhost flutter test
cd tool/rules_test && npm ci && npm test    # only when firestore.rules changes
python3 tool/gen_seed.py                    # only when the seed changes
```

## ٦. البوابات (Gates)

| Gate | Checked by | Passes when |
|---|---|---|
| Packet gate | Reviewer | the packet's acceptance list is met; analyze clean; tests green; docs updated in the PR |
| PR gate | Reviewer + CI | CI green on the head commit; no element-key test left stale; squash-merge |
| Stage gate (G1, G2, G3) | Owner + trial servant | all packets of the stage merged and live; the six-task trial is run and recorded in [STATUS.md](STATUS.md) |

Escalate to the owner instead of guessing when: a packet needs a value the report leaves open (README §١٥), a
rules change would exceed the expression budget, or a test that depends on an element key cannot be kept.

## ٧. تجميع الطلبات (PR grouping — proposed)

Small PRs, each a handful of packets on the same files, in stage order:

| PR | Branch **(proposed)** | Items |
|---|---|---|
| 3A | `feat/p3a-safe-actions` | 6, 7, 8, 11 |
| 3B | `feat/p3b-written-state` | 9, 10 |
| 3C | `feat/p3c-admin-status-session` | 12, 13 |
| 3D | `feat/p3d-custom-pages` | 14, 15, 16, 17 |
| 3E | `feat/p3e-menu-home` | 18, 19, 21, 23 |
| 3F | `feat/p3f-forms` | 20, 22, 24, 26 |
| 3G | `feat/p3g-english-switch` | 27 |
| 3H | `feat/p3h-inbox` | 25 |
| 3I | `feat/p3i-sitemap-assistant` | 28, 29 |
| 3J | `feat/p3j-remaining` | 30, 31, 32 |
