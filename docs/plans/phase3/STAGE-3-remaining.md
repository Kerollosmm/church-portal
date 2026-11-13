# المرحلة 3 — الباقي (Stage 3 — the rest)

**Objective:** church info, message types, the optional items, the trial with a servant, and the deferred
invitation. This stage ends with the panel ready for normal use.

| | |
|---|---|
| **Items** | 30–35 of the unified list (all priority 3) |
| **Owner** | Implementer (30, 31) · Owner + trial servant (33) · Owner (34) · Church office (35) |
| **Start gate** | G2 passed |
| **End gate (G3)** | success criteria S1–S5 of README §١٣ all met |
| **Target** | 2–4 days of the owner's 2–3 week total (README §١٠ D5): 1 small + 1 medium packet, one trial session, two office tasks |
| **PRs (proposed)** | 3J (30, 31) |

---

## PR 3J

### Packet P3-30 — Split church info; clearer coordinates; explain notice priority
Report item: #30 · تحسينات أخرى · not started · est. M
Current: about 33 fields on one page; the coordinates are raw numbers; the meaning of priority is unclear to the
editor.

- **Files:** modify `lib/ui/admin/admin_schema.dart` (`churchInfoDoc`, the alerts collection),
  `lib/ui/admin/admin_screens.dart`, `lib/core/l10n.dart`; test `test/admin_test.dart`.
- **Behaviour:** church info is divided into named groups with the basic ones open. The coordinates get a plain
  explanation of what to enter. The notice priority field says in words which number shows first.
- **Tests:** every existing `churchInfoDoc` field is still present in exactly one group · a save from the split
  form writes the same keys as before · the priority helper text is present in Arabic.
- **Acceptance:** no stored field changes; the page is shorter to read.

### Packet P3-31 — Message types: clearer save, confirm before removal, «إعادة كجديدة» harder to hit
Report item: #31 · تحسينات أخرى · partial · est. S
Current: save is in the screen bar (`saveContactCats`) but easy to miss; removal takes effect on save.

- **Files:** modify `lib/ui/admin/contact_admin.dart`, `lib/ui/admin/admin_screens.dart` (`MessagesScreen`);
  test `test/admin_test.dart`.
- **Behaviour:** the screen uses the fixed save bar (P1-11). Removing a type asks a confirmation that names the
  type (P1-06's `confirmNamedAction`). «إعادة كجديدة» moves out of the way of an accidental press.
- **Tests:** removing a type shows its name in the confirmation · cancelling keeps it · the save bar appears
  after any change · «إعادة كجديدة» is not adjacent to «تمّت».

### Packet P3-32 — One menu order for built-in and custom sections; detail pages for section items (optional)
Report item: #32 · الصفحات المخصصة · not started · open and optional in the memory bank · est. M
Current: built-in sections come first today; items show their full description on the card.

- **Owner decision (13 November 2026, README §١٠ D4): left out for now.** No work in this phase; G3 does not
  depend on it. It stays open and optional in the memory bank.
- **If reopened later:** one ordering across built-in and custom sections in the public menu, and an optional detail page
  per section item so the card no longer carries the whole description. Follows the four-places rule (model,
  schema, rules, seed) with tests.

---

## Item 33 — Trial session with a real servant, and the panel at 320px
Report item: #33 · خطة التبسيط · not started
Current: the admins list is fixed at 320px; the other screens are not fully tested. The page jump and the lost
letters while typing need a retest on an ordinary device.

- [ ] Sit with a servant who has never seen the panel. Hand over the six tasks (README §٣) with no help. Time the
      session and record every stop.
- [ ] Walk every admin screen at 320px width; record any overflow.
- [ ] On an ordinary device, type in long forms and watch for a page jump or lost letters; record the result
      either way.
- **Acceptance (S1):** the six tasks are finished without help in under 15 minutes.

## Item 34 — Adding an admin: e-mail invitation deferred
Report item: #34 · خطة التبسيط · **deferred**
Current: the dialog is still UID + e-mail; the owner still copies the UID from Firebase. Stopping and re-enabling
(item 12) is the near alternative.

- No work in this phase. If the owner later asks for it, it runs on the existing Cloudflare Worker at no cost, as
  a separate plan.

## Item 35 — Office tasks
Report item: #35 · تحسينات أخرى · office task · from the memory bank and the trial report

- [ ] At least two owner accounts.
- [ ] If the photo of Abouna Domadius depends on YouTube, copy it locally. The report rates this risk low.

---

## بوابة نهاية المرحلة (End gate G3 — ready for normal use)

- [ ] S1 — a new servant finishes the six tasks without help in under 15 minutes.
- [ ] S2 — every daily task takes 5 steps or fewer.
- [ ] S3 — not one English or technical word in front of the ordinary editor.
- [ ] S4 — no irreversible action without a confirmation that names the item.
- [ ] S5 — stopping or re-enabling an admin from the panel with one press.
- [ ] Still on the Spark plan, with no server.
- [ ] Infrastructure items (Sentry, Android, the domain) remain tracked in `docs/memory-bank/11-open-tasks.md`.
