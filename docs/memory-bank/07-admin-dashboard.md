# 07 — Admin dashboard (`/admin`)

Code: `lib/ui/admin/` — `admin_page.dart`, `admin_schema.dart`, `doc_editor.dart`, `collection_list.dart`,
`features_editor.dart`, `admin_screens.dart`, `admin_validators.dart`; data access `lib/data/admin_repository.dart`.
Tests: `test/admin_test.dart`; server rules: `firestore.rules` + `tool/rules_test`.

## How to sign in

1. Open **`https://maximos-domadios-church.web.app/admin`** (not linked from the public site; `AppConfig.adminPath`).
2. Email + password (Firebase Auth). "Forgot password?" sends a reset email.
3. The account must have a document **`admins/{uid}`** (`{email, role}`). Otherwise: «هذا الحساب ليس لديه صلاحية
   التعديل» + Sign out.
4. Arabic-first; `EN`/`ع` toggles the language. Desktop (≥ 1000 px): sidebar; phones: ☰ drawer.

Bootstrap the **first owner** (no owner can exist before): Firebase console → Firestore → `admins/<UID>` =
`{ "email": "...", "role": "owner" }`, or the **Seed Firestore** workflow input `admin_email` (finds/creates the Auth
user, makes it owner, emails a set-password link), or `admin` = `UID:email`, or locally
`node tool/seed_firestore.js --only none --admin <UID>:<email>`.

## Sign-in / permission flow (`admin_page.dart`)

```mermaid
flowchart TD
  A[AdminPage] -->|adminRepositoryProvider == null| U[adminUnavailable: Firebase not configured]
  A -->|authStateChanges: no user| L[_LoginForm]
  A -->|user| C[_AdminCheck]
  C -->|adminRole uid: server read, 15 s timeout| E{error?}
  E -- yes --> R[adminCheckFailed + Retry / Sign out]
  E -- no --> S[StreamBuilder roleChanges]
  S -->|null| N[notAdmin + Sign out]
  S -->|owner / editor| D[AdminDashboard]
```

- `adminRole(uid)` reads `admins/{uid}` **from the server** (`Source.server`) so a cold cache never shows "not admin";
  network errors show Retry instead of a misleading denial.
- `roleChanges(uid)` then streams the role live: a demoted owner loses the Admins screen, a removed admin loses the
  dashboard immediately. Cache-only "missing" snapshots are skipped.

## Roles

| Capability | Editor | Owner |
|---|---|---|
| All content collections (CRUD, hide/show, reorder) | ✔ | ✔ |
| Sections & home page (`settings/features`) | ✔ | ✔ |
| Church info (`settings/church`) | ✔ | ✔ |
| Contact messages: read, mark handled/new, delete | ✔ | ✔ |
| **Admins** screen: add / change role / remove **other** admins | ✘ ("ownerOnly") | ✔ |
| Change or remove **themselves** | ✘ | ✘ (UI + rules) → an owner always remains |

The same matrix is enforced server-side by `firestore.rules` (`isAdmin()` vs `isOwner()`). Note: the business case
wanted settings and message deletion owner-only; the implementation deliberately grants them to editors (ADR-011).

## Navigation (`adminDestinations(role)`)

`overview` → `features` → `church` → one entry per `adminCollections` item (alerts, seasons, liturgies, meetings,
clinics, facilities, activities, priests, departedPriests, saints, milestones) → `messages` → `admins` (owners only).
The app bar shows "Admin — <screen>", a 🌐 button to the public site and the language toggle; the nav shows the
signed-in email + role and Sign out.

## Screens

### Overview (`OverviewScreen`, `admin_screens.dart`)
Live counts per collection (respecting each screen's filter, e.g. serving vs departed priests) with hidden /
unconfirmed sub-counts, **new messages** (status ≠ handled, red when > 0), **sections on** (`N/16`), quick links
(church info, sections & home, alerts, open site) and the **8 latest edits** (title, `updatedAt`, `updatedBy`). A
failed stream shows "—". If the screen is rebuilt with a different backend (`widget.repo`), `didUpdateWidget`
cancels and re-subscribes every stream (BUG-18; `ChurchInfoScreen` does the same).

### Sections & home page (`FeaturesScreen` / `FeaturesEditor`, `features_editor.dart`) → `settings/features`
- Switch each of the 16 sections on/off (+ "enable all"); labels from `Sections.labels`. The 16th, **«الصور» /
  Images**, hides every optional item image site-wide (default on).
- **Home layout**: drag to reorder the 7 blocks — or tap **Move up / Move down** (`ValueKey('home-<block>-up|down')`,
  WCAG 2.5.7 single-pointer alternative) — show/hide each; a block whose section is off is flagged
  («blockSectionOff»).
- Hero title/subtitle AR/EN (≤ 200/300), announcement banner (on/off, AR/EN text ≤ 500, link validated by
  `isValidUrl(allowPath: true)`), **site colour** (5 `ThemePresets`).
- "Save changes" writes `FeatureSettings.toMap()` with `saveDoc` (merge + stamp). If the doc does not exist yet, a
  note says everything is on by default. If someone else saves while you have unsaved edits, a banner offers a reload
  instead of wiping your edits. The snapshot of **your own save** no longer remounts the form (BUG-12):
  `isEchoOfEditor(shown, latest, editorValues)` (`admin_validators.dart`) — if only metadata changed or every changed
  field already equals what the form holds, the editor key is kept, so the scroll position stays.

### Church info (`ChurchInfoScreen`) → `settings/church`
`DocEditor` over `churchInfoDoc` fields: names, bishop, address, transport, lat/lng (ranges), map query, Maps link,
**phones** (object list: label AR/EN, number, mobile/WhatsApp — ≤ 20 rows), WhatsApp number/channel, Facebook,
YouTube, Instagram, verse + references, hero image URL, history AR/EN (≤ 8000), **altars** (object list: name AR/EN,
kind main/second/annex), `assistantEnabled`, `sample`. Same "updated elsewhere → reload" banner, and the same
own-save rule (no scroll jump to the top after Save, BUG-12).

### Content lists (`CollectionListScreen`, `collection_list.dart`)
For each `CollectionDef`:
- Live list (`repo.watch(collection)`) filtered by the screen filter (`def.matches`), sorted by `sortAdminDocs`
  (orderable: by `order`; others by `order`/weekday, then start, then id).
- **Search** (all string values + id) and filter chips **all / visible / hidden / unconfirmed**; "showing N of M".
- **Open on site** (`Key('admin-openOnSite')`, «عرض بالموقع»): opens `CollectionDef.publicPath` (e.g. `/clinics`) in a
  new tab on web (`Uri.base.resolve`), or navigates there on mobile.
- Tile: title (`titleKeys`), subtitle (weekday, date, time range, season/stage/category/type/specialty labels,
  ⛔ inactive, start/end), tags *Hidden* / *Unconfirmed*, "updated by … at …".
- 👁 **hide/show** (`update(visible)`) — only when the collection has a `visible` field (not seasons).
- **Drag to reorder** — or tap **Move up / Move down** on each tile (`ValueKey('moveUp-<id>')`, WCAG 2.5.7) —
  (`reorder(collection, ids, base:)` → `order` = base + 10, 20, 30… in one batch) for orderable collections — clinics,
  facilities, activities, priests, departed fathers, saints, milestones — and only when search is empty, filter = all
  and > 1 item. **Departed fathers use base 1000** (`reorderBase(def)`: 1010, 1020…) because they share the
  `priests` collection with serving priests, so the two lists never get colliding `order` values (BUG-13).
  Liturgies and meetings use the numeric **Order** field instead.
- `DocEditor.save`: on a **`TimeoutException`** (15 s, offline) the images uploaded for the document are **kept** —
  Firestore keeps the write queued and may still commit it pointing at them; other errors still delete them
  (BUG-13).
- **Add** (FAB) / tap to **edit** → full-screen `DocEditor`; **delete** with confirmation dialog.

| Screen id | Collection | Orderable | Has visible | Has sample | Notes |
|---|---|---|---|---|---|
| alerts | alerts | – | ✔ | – | title, body, active, starts/ends (Cairo), priority 0–1000, link (path or URL) |
| seasons | seasons | – | – | – | key choice, names, starts/ends, active |
| liturgies | liturgies | – (order field) | ✔ | ✔ | needs weekday **or** one-off date; end may be before start (midnight) |
| meetings | meetings | – (order field) | ✔ | ✔ | stage choice |
| clinics | clinics | ✔ | ✔ | ✔ | `active` missing = true |
| facilities | facilities | ✔ | ✔ | ✔ | "Public services" |
| activities | activities | ✔ | ✔ | ✔ | category choice |
| priests | priests (status = serving) | ✔ | ✔ | ✔ | missing status = serving |
| departedPriests | priests (status = departed) | ✔ | ✔ | ✔ | new docs start with `status: departed` |
| saints | saints | ✔ | ✔ | – | |
| milestones | milestones | ✔ | ✔ | – | icon choice |

`CollectionDef.publicPath` drives the **Open on site** button.

### Generic form (`DocEditor`, `doc_editor.dart`)
- Field widgets by `FieldType`: text, multiline, integer, decimal, boolean, time (HH:mm), weekday, weekdays (chips),
  dateTime / date (Cairo), looseDate, choice (labels via `choiceLabel`/`opt_*`), url, phone, objectList, **image**.
- Validation (`admin_validators.dart` `validateFieldValue`): required, max length (`effectiveMaxLength`), `HH:mm`,
  real calendar dates (rejects 2027-02-30), loose dates, numeric ranges (Arabic digits accepted), URLs (`https://…`
  or in-app path where `allowPath`), phones (`^\+?[0-9]{5,15}$` after normalising). Cross-field
  `validateDocument`: `requireAnyOf` (weekday or date → «needWeekdayOrDate»), end after start (except liturgies),
  `endsAt` after `startsAt`.
- New docs write all collected values (+ `newDefaults`); **existing docs write only changed fields**
  (`changedFields`, deep compare) with merge — never overwriting another admin's concurrent edits to other fields.
- Every save stamps `updatedAt` (server time) and `updatedBy` (email) via `AdminRepository._stamp`.
- Boolean defaults: `missingBool` (value assumed when an existing doc lacks the field, e.g. `visible` = true,
  clinic `active` = true) vs `newBool` (value for new docs, e.g. `sample` = false).

### Optional image field (`FieldType.image`, PR #5)
On priests, departed fathers, saints, milestones, activities, alerts and seasons the form has **«الصورة (اختياري) /
Image (optional)»** with a 96 px preview and:
- **Upload image** (رفع صورة): opens the device gallery/file picker (`image_picker`). The file is resized and
  compressed **in the browser/app before anything is stored** (`prepareUpload`, `lib/data/image_processing.dart`):
  long edge ≤ **800 px** (640 px second pass), quality 0.8 → 0.5 until ≤ **~250 KB**; web encodes WebP via canvas
  (JPEG where WebP is unsupported), Android uses the Dart `image` package (JPEG). Files > 25 MB are refused before
  decoding; results still > **700 KB** are refused («الصورة كبيرة جدًا…»). The preview says "uploaded when you
  save" — the `media/{id}` doc is written **only when you press Save**, then the item gets
  `image = {source: inline, mediaId, alt, w, h}`. If the save fails, the uploaded media doc is deleted again and the
  picked image stays so you can retry.
- **Image link** (رابط صورة): paste an **https://** image URL (validated: https, host, no spaces, ≤ 500) →
  `{source: url, url}`.
- **Remove image** (إزالة الصورة): saves `image: null`; the card goes back to its icon.
- **Image description** (alt, ≤ 300) for screen readers (defaults to the item's name on the site).
- Replacing or removing an inline image, or deleting the item from the list, deletes the old `media/{id}` doc
  **best effort** (`orphanedMediaIds`). Orphans can remain if that delete fails or two admins edit at once; clean-up:
  Firestore console → `media` → delete ids not referenced by any content doc's `image.mediaId` (open task).
- Upload is disabled when the backend has no `MediaRepository` (URL still works). Switch all images off/on in
  **Sections & home page → «الصور» / Images**.

### Contact messages (`MessagesScreen`) → `contact_messages`
Newest first (`createdAt`), filter chips **new** (default) / handled / all; each card: name, time, message, phone
(call), email (`mailto:`);
**Mark handled / Mark new** (`update(status)`), copy to clipboard, delete with confirmation.

### Admins (`AdminsScreen`, owners only) → `admins`
List with role dropdown (owner/editor) and remove button — disabled for yourself ("(you)"). **Add admin** dialog: UID
(validated by `isValidAdminUid`: 1–128 chars, no `/`; copy it from Firebase console → Authentication → Users), email,
role. The Auth user itself must be created in the console (or via the Seed workflow) first.

## Gotchas for agents

- Adding a field = schema `FieldDef` + model + rules allow-list + seed (+ tests). The admin test cross-checks the
  rules allow-lists against `adminCollections` and seed keys.
- Max lengths in `FieldDef` must not exceed the rules limits (e.g. alert body form 1000 vs rule 2000 is fine; the
  reverse would make saves fail with permission-denied).
- `AdminBackend` is an interface so widget tests use an in-memory fake; keep new admin I/O behind it.
  `AdminBackend.media` (default null) exposes the `MediaRepository`; `DocEditor` takes `media`, `pickImage` and
  `prepareImage` so tests inject bytes and a fake store (`test/media_test.dart`).
