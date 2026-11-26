# PR 5C — Domain Deduplication (`isoDate`, `planNotifications`, Push Defaults)

> **Branch:** `refactor/p5c-domain-dedup` (clean `git worktree` from `origin/main` after PR 5B merges)
> **Scope:** Strictly behavior-preserving pure-Dart domain cleanup.

---

## Packet P5C-1 — Merge ONLY the 3 byte-identical `YYYY-MM-DD` formatters

- **Files:** `lib/domain/reminders.dart` (`isoDate`), `lib/domain/today.dart` (`dayKey`), `lib/domain/occasion_theme.dart` (`formatDate`), plus their callers in `lib/` and `test/`.
- **Rules:**
  - Keep `isoDate(DateTime d)` in `lib/domain/reminders.dart` (or `lib/domain/time_format.dart`) as the single formatter.
  - Replace `dayKey` (`today.dart`) and `formatDate` (`occasion_theme.dart`) callers directly with `isoDate` — **no** `parse_helpers.dart`, **no** public forwarding wrappers.
  - **DO NOT TOUCH** `_ymd(DateTime d)` in `lib/domain/assistant_context.dart`: it converts UTC instants via `CairoTime.calendarDate(d)` first and is **not** identical.

### Steps
- [ ] Locate all callers of `dayKey` and `formatDate` (`git grep -n "\bdayKey\b\|\bformatDate(" lib/ test/`).
- [ ] Replace with `isoDate` and delete `dayKey` and `occasion_theme.formatDate`.
- [ ] Run `flutter analyze && flutter test` → PASS.
- [ ] Commit with explicit pathspecs.

---

## Packet P5C-2 — Extract 2 focused helpers in `planNotifications`

- **Files:** `lib/domain/notify_plan.dart`, `test/notify_plan_test.dart`
- **Targets (by symbol inside `planNotifications`):**
  1. `_shiftOutOfQuietHours(tz.TZDateTime scheduledAt, PushPrefs prefs)` — unifies the 3 duplicate `if (prefs.quietHoursEnabled) { evaluateQuietHours(...); }` blocks for daily verse, Katameros, and feasts.
  2. `_buildReminderNotification(...)` — unifies the ~60-line copy-paste between the recurring reminder branch and the one-off reminder branch.
- **Do NOT** split `planNotifications` into 7 helpers; keep the rest of the loops inline.

### Steps
- [ ] Run `flutter test test/notify_plan_test.dart` and record baseline pass count.
- [ ] Extract `_shiftOutOfQuietHours` and `_buildReminderNotification` in `lib/domain/notify_plan.dart`.
- [ ] Re-run `flutter test test/notify_plan_test.dart` → confirm exact same pass count.
- [ ] Commit with explicit pathspecs.

---

## Packet P5C-3 — Centralize duplicated push defaults in `lib/domain/push.dart`

- **Files:** `lib/domain/push.dart`, `lib/ui/admin/notifications_admin.dart`
- **Targets (by symbol — locate via `git grep`):**
  - Centralize `[0, 15, 60, 1440]` as `PushSettings.defaultReminderLeads` (used in `PushSettings` constructor, `fromMap`, and `notifications_admin.dart` `_reminderLeads` initialization).
  - Centralize `'22:00'` / `'07:00'` as `QuietHours.defaultFrom` / `QuietHours.defaultTo` (used in `QuietHours` constructor and `fromMap`).
  - Reuse `NotifyTypeConfig.defaultVerseTime` (`'07:00'`), `defaultKatamerosTime` (`'06:30'`), and `defaultFeastsTime` (`'07:30'`) inside `NotifyTypeSpec.builtInDefaults`.

### Steps
- [ ] Replace duplicated literal defaults with the canonical constants above.
- [ ] Run `flutter analyze && flutter test`, `flutter build web --release`, `node tool/check_web_bundle.mjs build/web` → PASS.
- [ ] Update `docs/plans/phase5/STATUS.md`, push, run PR review loop, squash-merge, verify deploy.
