# PR 5A — Pure Deletions (Dead Rules, Strings & Dead/Test-Only Code)

> **Branch:** `chore/p5a-pure-deletions` (clean `git worktree` from `origin/main`)
> **Scope:** Strictly behavior-preserving deletions. Find every target by **symbol name** (`git grep`).

---

## Packet P5A-1 — Deny `/clinics/{id}` & deduplicate `contentCollections()` in `firestore.rules`

- **Files:** `firestore.rules`, `tool/rules_test/rules.test.mjs`
- **Targets (by symbol):**
  - `validContent(col, d)` — remove the `col == 'clinics'` branch.
  - `validClinic(d, changed)` and `ownClinic(d)` — delete both functions.
  - `match /{col}/{docId}` — extract `function contentCollections()` returning the 11 active collections (`['alerts', 'seasons', 'liturgies', 'meetings', 'activities', 'facilities', 'priests', 'milestones', 'saints', 'categories', 'entries']`) and reuse it across `allow read`, `allow create, update`, and `allow delete` (eliminating the 3x duplicated collection array).
  - Update comments referencing `clinics` on detail-page collections (`6 collections`).
  - **DO NOT TOUCH (`D1`):** Keep `'clinics'` and `'heroVideos'` inside `sectionKeys()`, `legacyFeatureKeys()`, `validHeroVideos`, `imageStyles`, `validSeasonPreset`, and `validPageHeaders` on `settings/features`. Keep `/clinics` redirect in `lib/router.dart` and `retired` IDs in `tool/gen_seed.py`.

### Steps
- [ ] Add a failing deny test in `tool/rules_test/rules.test.mjs` asserting public `getDocs`/`getDoc` and admin `setDoc`/`updateDoc`/`deleteDoc` on `'clinics'` all fail (`assertFails`). Migrate generic CRUD/soft-delete/image/legacy tests that used `'clinics'` as a sample collection over to `'facilities'`.
- [ ] Run `cd tool/rules_test && npm test` → confirm the new deny test FAILS.
- [ ] Apply the `firestore.rules` edits above.
- [ ] Run `cd tool/rules_test && npm test` → confirm 100% PASS (including worst-case expression-budget tests).
- [ ] Commit with explicit pathspecs.

---

## Packet P5A-2 — Remove 11 dead UI string keys & dead `confirmDialog`

- **Files:** `test/bundle_isolation_test.dart`, `lib/core/l10n.dart`, `lib/ui/admin/admin_strings.dart`, `lib/ui/admin/admin_screens.dart`
- **Targets (by symbol):**
  - `deadKeys` in `test/bundle_isolation_test.dart` + `_strings` in `lib/core/l10n.dart`: `allVenues`, `callChurchOffice`, `allSpecialties`, `availableToday`, `specialtyFilter`, `factQualification`, `factDays`, `accentDailyVerse`.
  - `_adminStrings` in `lib/ui/admin/admin_strings.dart`: `adminExpiresAt`, `seasonsTitle`, `deletedMultiUndo`.
  - `confirmDialog` in `lib/ui/admin/admin_screens.dart` (0 callers anywhere).

### Steps
- [ ] Add the 8 public keys to `deadKeys` in `test/bundle_isolation_test.dart`.
- [ ] Run `flutter test test/bundle_isolation_test.dart` → confirm FAIL.
- [ ] Delete the 8 keys from `lib/core/l10n.dart`, the 3 keys from `lib/ui/admin/admin_strings.dart`, and `confirmDialog` from `lib/ui/admin/admin_screens.dart`.
- [ ] Run `flutter analyze && flutter test test/bundle_isolation_test.dart test/admin_test.dart` → PASS.
- [ ] Commit with explicit pathspecs.

---

## Packet P5A-3 — Remove verified dead & test-only code

- **Files:** `lib/data/admin_repository.dart`, `lib/data/README.md`, `lib/ui/admin/admin_schema.dart`, `lib/ui/admin/doc_editor.dart`, `lib/ui/admin/README.md`, `test/app_settings_admin_test.dart`, `lib/ui/admin/pending_delete.dart`, `lib/ui/admin/session_policy.dart`, `test/admin_test.dart`, `lib/domain/push.dart` (D3)
- **Targets (by symbol — verify 0 non-test callers with `git grep` before each deletion):**
  1. `AdminRepository.adminRole` and `AdminRepository.roleChanges` in `lib/data/admin_repository.dart` (superseded by `adminAccess`/`accessChanges` in `admin_access.dart`; update `lib/data/README.md`).
  2. `appSettingsDoc` (`lib/ui/admin/admin_schema.dart`), `FieldType.intChoices`, `FieldDef.intOptions`, `FieldDef.defaultIntValues` (`admin_schema.dart` + the 3 `FieldType.intChoices` switch cases in `lib/ui/admin/doc_editor.dart`), and `test/app_settings_admin_test.dart` (only tests `appSettingsDoc`); update `lib/ui/admin/README.md`.
  3. `PendingDelete.flush` and `PendingDelete.extendAll` (`lib/ui/admin/pending_delete.dart`) — remove their unit-only test blocks in `group('PendingDelete')` of `test/admin_test.dart` while **keeping all `testWidgets` behavior tests intact**.
  4. `SessionPolicy.shouldWarn` and `SessionPolicy.shouldSignOut` (`lib/ui/admin/session_policy.dart`) — remove only their unit-only assertions in `test/admin_test.dart` while keeping active session-policy tests.
  5. **Decision `D3` check:** Inspect `topicFor`, `NotifyConfig.isReminderSourceEnabled`, and `NotifySchedule.dueNow` in `lib/domain/push.dart` and their tests. Keep if they guard Worker JS parity; delete only if redundant.

### Steps
- [ ] Confirm 0 `lib/` callers for each symbol above via `git grep`.
- [ ] Remove dead symbols and their obsolete test-only assertions/files in small commits.
- [ ] Run `flutter analyze && flutter test` → PASS.

---

## Packet P5A-4 — Remove speculative `StorageMediaRepository` & `AppConfig.mediaBackend` *(Decision D2)*

- **Files:** `lib/data/media_repository.dart`, `lib/config/app_config.dart`, `lib/data/README.md`, `lib/config/README.md`, `docs/memory-bank/03-architecture.md`, `05-firebase.md`, `10-decisions-and-history.md`, `11-open-tasks.md`, `documentation/features/images-and-media.md`
- **Targets (by symbol):** Delete `StorageMediaRepository` (`lib/data/media_repository.dart`), simplify `createPublicMediaRepository` → `ReadOnlyMediaRepository(db)` and `createMediaRepository` → `FirestoreMediaRepository(db, actor)`, delete `AppConfig.mediaBackend` (`lib/config/app_config.dart`). **Keep** `MediaRepository` interface and `MediaSource.storage` URL rendering.

### Steps
- [ ] Apply edits and sync the 7 docs/READMEs.
- [ ] Run full verification: `flutter analyze && flutter test`, `cd tool/rules_test && npm test`, `flutter build web --release`, `python3 tool/fingerprint_icon_fonts.py build/web`, `node tool/check_web_bundle.mjs build/web`.
- [ ] Update `docs/plans/phase5/STATUS.md`, push, run PR review loop, squash-merge, verify deploy.
