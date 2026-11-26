# حالة التنفيذ (Phase 5 Status Tracker)

> Single checklist for Phase 5. Update inside each PR branch before marking ready for review.
> Overview: [README.md](README.md) · Runbook: [HANDOFF.md](HANDOFF.md) · Guide: [SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md).

---

## ١. قرارات المالك والمتطلبات المسبقة (Decisions & Prerequisites)

- [x] **D1:** Keep legacy `clinics` / `heroVideos` keys in `settings/features` allow-lists in `firestore.rules` (default: **KEEP**)
- [x] **D2:** Remove speculative `StorageMediaRepository` & `AppConfig.mediaBackend` in PR 5A (default: **REMOVE**)
- [x] **D3:** Check `topicFor`, `NotifyConfig.isReminderSourceEnabled`, `NotifySchedule.dueNow` for Worker JS parity before removing in PR 5A
- [x] **Prereq (before PR 5B):** Open PR #99 (`lib/ui/admin/collection_list.dart`) merged or coordinated (`MERGED` 2026-11-25)
- [x] **Prereq (before PR 5A-docs):** Open PR #95 (`docs/memory-bank/11-open-tasks.md`) coordinated (`11-open-tasks.md` left untouched)

---

## ٢. القياسات (Baseline vs Progress)

| Metric | Baseline (`main` @ `deb8328`) | After 5A | After 5B | After 5C | After 5D |
|---|---|---|---|---|---|
| `flutter analyze` issues | 0 | 0 | 0 | 0 | 0 |
| Total Dart tests passing | *(record in 5A)* | All Linux CI green (1,612 local; Windows `dart.bat` check passes on Linux CI) | All Linux CI green (`1,620`; `1,619` local on Windows) | All Linux CI green (`1,620`; `1,619` local on Windows) | All Linux CI green (`45692469460`; `1,620/1,621` local on Windows — Windows `dart.bat` check passes on Linux CI) |
| Rules emulator suites passing | *(record in 5A)* | 42 suites / 186 tests | 42 suites / 186 tests | *(unchanged — no rules change)* | *(unchanged — no rules change)* |
| `main.dart.js` gzip `-9` (`<= 1,399,000 B`) | `1,330,341 B` | `1,349,211 B` (`+49,789 B` headroom, Linux CI `9bc860e`; `0` deferred leaks) | `1,348,956 B` (`+50,044 B` headroom, Linux CI `7e02cf5` / `#102`; `0` deferred leaks) | `1,348,971 B` (`+50,029 B` headroom, Linux CI `e57ebb3` / `#103`; `0` deferred leaks) | `1,349,223 B` (`+49,777 B` headroom, Linux CI `7670674` / `#104`; `0` deferred leaks) |

---

## ٣. تتبع الطلبات والحزم (PR & Packet Checklists)

### PR 5A — `chore/p5a-pure-deletions` ([Guide](PR-5A-pure-deletions.md))
- [x] **P5A-1:** Deny `/clinics/{id}` in `firestore.rules`, extract `contentCollections()`, add deny test & migrate sample tests
- [x] **P5A-2:** Pin & remove 8 dead `l10n.dart` keys, remove 3 dead `admin_strings.dart` keys, delete dead `confirmDialog`
- [x] **P5A-3:** Delete dead/test-only symbols (`AdminRepository.adminRole`/`roleChanges`, `appSettingsDoc` + `FieldType.intChoices`, `PendingDelete.flush`/`extendAll`, `SessionPolicy.shouldWarn`/`shouldSignOut`, and `D3` push helpers if non-parity)
- [x] **P5A-4:** *(D2)* Remove `StorageMediaRepository` + `AppConfig.mediaBackend` + sync docs
- [x] **Gate 5A:** `flutter analyze` · `flutter test` · `rules_test` · `check_web_bundle.mjs` · Review loop · CI · Merge (`SHA: 9bc860e`) · Live deploy (`45531373715`)

### PR 5A-docs — `docs/p5-docs-links-and-paths` ([Guide](PR-5A-docs-links-and-paths.md))
- [x] **P5A-docs:** Fix `AGENTS.md` / `project-rules.md` script commands, fix `CLAUDE.md` & `docs/agents/domain.md` targets, fix `07-admin-dashboard.md` `adminExpiresAt`, replace 356 repo `file:///` links with relative paths, sync `operations.md`
- [x] **Gate 5A-docs:** Link check · Review loop · CI · Merge (`SHA: 012dbe4`) · PR [#101](https://github.com/Kerollosmm/church-portal/pull/101)

### PR 5B — `refactor/p5b-simplify-undo` ([Guide](PR-5B-simplify-undo.md))
- [x] **P5B-1:** Extract `SoftDeleteUndo` and deduplicate `CollectionListScreen` undo state (all 19 `PendingDelete` / 14 `testWidgets` race tests green)
- [x] **P5B-2:** Wire `MessagesScreen` to `SoftDeleteUndo` + `checkLazyPurge` (`confirmNamedAction`, `removeMedia: false`, batch `"Undo all"` + race tests added)
- [x] **Gate 5B:** `flutter analyze` · `flutter test` · `rules_test` · `check_web_bundle.mjs` · Docs synced · Review loop · CI · Preview check (PR [#102](https://github.com/Kerollosmm/church-portal/pull/102)) · Merge (`SHA: bf12824`) · Live deploy (`45648798284`)

### PR 5C — `refactor/p5c-domain-dedup` ([Guide](PR-5C-domain-dedup.md))
- [x] **P5C-1:** Unify the 3 byte-identical `YYYY-MM-DD` formatters (`isoDate`, `dayKey`, `occasion_theme.formatDate`), keeping `CairoTime` `_ymd` separate
- [x] **P5C-2:** Extract 2 helpers in `planNotifications` (`_shiftOutOfQuietHours`, `_buildReminderNotification`)
- [x] **P5C-3:** Centralize duplicated push defaults in `lib/domain/push.dart`
- [x] **Gate 5C:** `flutter analyze` · `flutter test` · `check_web_bundle.mjs` · Review loop · CI · Preview check (PR [#103](https://github.com/Kerollosmm/church-portal/pull/103)) · Merge (`SHA: 9072fc3`) · Live deploy (`45668989660`)

### PR 5D — `refactor/p5d-admin-dedup` ([Guide](PR-5D-admin-dedup.md))
- [x] **P5D-1:** In-file dedup in `doc_editor.dart` (`_moveObjectRow`, `_removeObjectRow`, unified `_isShown`, `_blockTypeOf`, `_Row._hasTypeField`)
- [x] **P5D-2:** Collapse `_draft*`/`_initialDraft*` in `notifications_admin.dart` into `_Draft` value class + remove `LinkTargetLike`
- [x] **Gate 5D:** `flutter analyze` · `flutter test` · `check_web_bundle.mjs` · Review loop · CI · Preview check (PR [#104](https://github.com/Kerollosmm/church-portal/pull/104)) · Merge (`SHA: 7670674`) · Live deploy (`45692469461`)

### PR 5E — Optional Splits ([Guide](PR-5E-optional-splits.md)) — **Default: SKIP**
- [x] Evaluated after 5A–5D: **skipped** (`Default: SKIP` confirmed with owner at `7670674` — `admin_screens.dart` 1,379 lines, `doc_editor.dart` 3,247 lines, CI `firestore-rules` 1m13s–1m30s, `analyze-test-build` 6m13s–6m30s, `main.dart.js` gzip `1,349,223 B` / `+49,777 B` headroom)
