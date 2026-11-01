# 04 — Data model (Cloud Firestore)

Four places must agree for every field — change them together:

1. **Dart model** — `lib/domain/models.dart` (`fromMap`, tolerant: wrong types fall back to defaults) and
   `lib/domain/features.dart` (`FeatureSettings`).
2. **Admin schema** — `lib/ui/admin/admin_schema.dart` (`adminCollections`, `churchInfoDoc`).
3. **Security rules** — `firestore.rules` (`valid<Collection>()` key allow-lists, types, sizes).
4. **Seed** — `tool/gen_seed.py` → `assets/seed/seed.json` (+ `tool/known_seed_ids.json`, `tool/retired_seed_ids.json`).

`test/admin_test.dart` ("firestore.rules allow-lists cover every admin field and every seed key") and
`tool/rules_test` ("every seed document passes validation") fail if 2/3/4 drift apart.

## Conventions

- **Bilingual pairs**: `…Ar` / `…En` (rendered with `context.pick`). Exceptions: `Priest.name` (Arabic) + `nameEn`;
  `Clinic.doctorName` (single); `Saint.feastGregorian` (EN) + `feastGregorianAr`.
- **Times**: strings `"HH:mm"` 24 h, Cairo wall clock (`parseHm`; rules regex `^([01][0-9]|2[0-3]):[0-5][0-9]$`,
  empty string allowed where optional).
- **Weekdays**: ISO **1 = Monday … 7 = Sunday** (`weekday`, `Clinic.days`).
- **Instants**: Firestore `Timestamp` (`startsAt`, `endsAt`, `date`, `createdAt`, `updatedAt`). In `seed.json` they
  are ISO strings with the Cairo offset (`gen_seed.py` `T(date, "HH:mm")` uses `ZoneInfo("Africa/Cairo")`, so DST is
  right); `seed_firestore.js` converts the keys `startsAt/endsAt/date/createdAt` to Timestamps.
  One-off liturgy `date` = Cairo midnight of that day; `CairoTime.calendarDate` converts UTC instants to the Cairo date.
- **Loose dates** (priests): strings `YYYY`, `YYYY-MM` or `YYYY-MM-DD` (rules: max 10 chars).

### Common flags on content documents

| Field | Type | Default when missing | Meaning |
|---|---|---|---|
| `visible` | bool | **true** | false = hidden from the public by an admin (kept in DB). Filtered by `publicItems` in providers. Not on `seasons`. |
| `order` | int (−100000…100000) | 0 | Display order (stable sort; ties keep input order). Drag-reorder writes 10, 20, 30… |
| `sample` | bool | false | **Unconfirmed / placeholder** awaiting the church. UI shows `SampleBadge` («بيانات تجريبية») and `PendingConfirmationNote`; assistant prefixes `[UNCONFIRMED]`. Admin label "Unconfirmed (pending church confirmation)". |
| `updatedAt` | timestamp | — | Stamped by `AdminRepository._stamp` (`FieldValue.serverTimestamp()`); rules require `== request.time` or unchanged |
| `updatedBy` | string | — | Admin email (or uid); rules require it to equal `request.auth.token.email` (or uid) or be unchanged |

Rules `common(d)`: ≤ 60 keys, `visible`/`sample` bool, `order` int in range, `stampOk`. `meta()` =
`['visible','sample','order','updatedAt','updatedBy']` is added to every content allow-list.

## `settings/church` — `ChurchSettings`

| Field | Type | Rules limit | Notes |
|---|---|---|---|
| `nameAr` | string | **required**, ≤ 300 | |
| `nameEn` | string | ≤ 300 | admin form marks it required |
| `addressAr`, `addressEn` | string | ≤ 300 | |
| `transportAr`, `transportEn` | string | ≤ 2000 | "Getting here" |
| `lat`, `lng` | number | −90…90 / −180…180 | `31.260138`, `30.01129` |
| `coordinatesApproximate` | bool | allowed key | in seed (`false`), not in Dart model/admin form |
| `mapsQuery` | string | ≤ 200 | used for embed + directions (`"31.260138,30.01129"`) |
| `mapsUrl` | string | ≤ 500 | "Open in Google Maps" |
| `phones` | list of `{labelAr, labelEn, number, isMobile}` | list ≤ 20 | `PhoneEntry`; `isMobile` → WhatsApp button. Legacy `label` key read as fallback |
| `whatsapp` | string | ≤ 20 | chat number (empty — church publishes none) |
| `whatsappChannel`, `facebook`, `youtube`, `instagram` | string (URL) | ≤ 500 | |
| `verseAr`, `verseEn` | string | ≤ 300 | Rev 2:10 |
| `verseRef`, `verseRefAr` | string | ≤ 60 | `"Rev 2:10"`, `"رؤيا ٢: ١٠"` |
| `heroImageUrl` | string | ≤ 500 | empty → gradient hero |
| `historyAr`, `historyEn` | string | ≤ 8000 | |
| `bishopAr`, `bishopEn` | string | ≤ 300 | |
| `altars` | list of `{nameAr, nameEn, kind: main\|second\|annex}` | list ≤ 20 | `Altar`; empty in seed |
| `assistantEnabled` | bool | | default **false** in model; seed `true` |
| `sample` | bool | | |
| `updatedAt`, `updatedBy` | | stampOk | |

Existence of `settings/church` = "database is seeded" (see `03-architecture.md`). It can never be deleted (rules).

## `settings/features` — `FeatureSettings` (`lib/domain/features.dart`)

| Field | Type | Default / parsing |
|---|---|---|
| `sections` | map `<sectionKey, bool>` | missing key = **on**; non-bool values ignored. Keys = `Sections.all`: `schedule, meetings, clinics, services, history, milestones, saints, priests, departedPriests, activities, alerts, contactInfo, socials, contactForm, assistant` |
| `homeOrder` | list of block keys | `normalizeHomeOrder`: unknown/duplicate dropped, missing appended in default order. Blocks (`HomeBlocks.defaultOrder`): `banner, alerts, nextMass, quickContacts, milestones, directory, map` |
| `homeHidden` | list of block keys | unknown keys dropped |
| `heroTitleAr/En` | string ≤ 200 | empty → church name |
| `heroSubtitleAr/En` | string ≤ 300 | empty → address |
| `bannerEnabled` | bool | false |
| `bannerAr`, `bannerEn` | string ≤ 500 | banner shows only if enabled **and** some text |
| `bannerLink` | string ≤ 500 | `''`, in-app path `/…`, or `http(s)://host.tld…` (rules regex mirrors `isValidUrl(allowPath: true)`) |
| `theme` | `burgundy\|navy\|green\|brown\|purple` | unknown → burgundy (`ThemePresets.all` ARGB values) |
| `updatedAt`, `updatedBy` | | stampOk |

- `FeatureSettings.defaults` (everything on) is used before the doc loads and when it does not exist.
- `toMap()` always writes **all** 15 section keys explicitly.
- `HomeBlocks.requires`: `alerts→alerts`, `nextMass→schedule`, `quickContacts→contactInfo`,
  `milestones→milestones`, `map→contactInfo` (block disappears when its section is off). `directory` and `banner`
  have no section.

## Content collections

### `alerts/{id}` — `Alert` (Hideable)
`titleAr` (**req**, ≤300), `titleEn` (≤300), `bodyAr`/`bodyEn` (≤2000; admin form caps 1000), `active` (bool,
default false in model), `startsAt`/`endsAt` (timestamp), `priority` (int 0–1000, higher first), `link` (≤500;
in-app path or URL), + meta. Seed ids: `follow-announcements`, `nativity-fast-2026`, `revival-maximus-2027`,
`revival-moses-2027`.

### `seasons/{id}` — `Season` (not Hideable)
`key` (**required**, one of `holy_week, pascha, nativity, revival_maximus, revival_moses, summer`), `nameAr` (**req**),
`nameEn`, `startsAt`, `endsAt` (timestamps, exact window), `active` (bool, default false in model). No `visible`/`order`
in the admin form (rules would allow `meta()` keys). Seed: `nativity-2027`, `revival-maximus-2027`, `holy-week-2027`,
`pascha-2027`, `revival-moses-2027`.

### `liturgies/{id}` — `Liturgy` (Hideable)
| Field | Type | Notes |
|---|---|---|
| `type` | `mass\|vespers\|praise\|other` | missing → `mass`. Next-mass card uses `mass` only |
| `nameAr` (**req**), `nameEn` | string ≤300 | |
| `weekday` | int 1–7 or null | weekly schedule |
| `date` | timestamp or null | one-off (Cairo day). Admin requires `weekday` **or** `date` (`requireAnyOf`) |
| `start` | "HH:mm" | **required key** (rules: `'start' in d`) |
| `end` | "HH:mm" or '' | may be ≤ start = crosses midnight; missing end → start + 120 min |
| `placeAr/En`, `audienceAr/En` | string ≤300 | |
| `seasonKey` | season key or null | null = regular schedule |
| `order`, `visible`, `sample` | | |
Seed: 47 docs, all `sample: true` (ids like `fri-1`, `sun-youth`, `sat-vespers`, `nat-eve`, `rev-max-1…7`,
`rev-max-feast`, `hw-day-1…3`, `hw-eve-1…3`, `hw-palm`, `hw-thursday`, `hw-friday`, `hw-saturday`, `pascha-eve`,
`pascha-day`, `rev-moses-1…7`, `rev-moses-feast`).

### `meetings/{id}` — `Meeting` (Hideable)
`stage` (**req** ≤40; admin choices `angels, primary, preparatory, secondary, youth, university, graduates, family,
men, women, elderly`; others render under "Other stages"), `nameAr` (**req**), `nameEn`, `weekday` (1–7),
`start`/`end` (HH:mm), `hallAr/En`, `facebookUrl`/`whatsappUrl` (≤500), `notes` (≤300), meta. Seed: 11 docs (id =
stage), all `sample: true`.

### `activities/{id}` — `Activity` (Hideable, orderable)
`category` (≤40; admin choices `service, choir, hymns, youth, servants, media, drama, scouts, deacons, bible, summer,
sports, exhibitions`, default `service`), `titleAr` (**req**), `titleEn`, `descAr/En` (≤2000), `scheduleAr/En` (≤300),
`ageRange` (≤60), `contactPhone` (≤20), `link` (≤500), meta. Seed: 11 verified docs (`deacons-choir`, `avamose-choir`,
`davids-tones`, `hymns-school`, `maximous-youth`, `prep-boys`, `antibiotic-mime`, `karouz-school`, `servant-care`,
`media-center`, `kalimtein`).

### `clinics/{id}` — `Clinic` (Hideable, orderable)
`specialty` (**req** key ≤40, e.g. `dental` — also the `?specialty=` URL value), `specialtyAr` (**req**),
`specialtyEn`, `doctorName` (**req**), `degreeAr/En`, `days` (list ⊆ {1..7}, ≤7), `start`/`end` (HH:mm, end must be
after start in admin), `bookingPhone`/`whatsapp` (≤20), `active` (bool, **missing = true**), meta. Seed: 11 generic
placeholders («طبيب <التخصص> — يُعلن لاحقًا», no phones), all `sample: true`.

### `facilities/{id}` — `Facility` (Hideable, orderable) — shown on `/public-services`
`type` (≤40; `service, nursery, employment, halls, other`), `nameAr` (**req**), `nameEn`, `descAr/En` (≤2000),
`phone` (≤20), `hoursAr/En` (≤300), meta. Seed: `anba-abraam` (verified), `nursery`, `employment`, `halls`, `library`
(sample).

### `priests/{id}` — `Priest` (Hideable, orderable)
`name` (Arabic, **req**), `nameEn`, `photoUrl` (≤500, all empty), `rank` (`hegumen\|priest`, default `priest`),
`ordinationDate`, `hegumenDate`, `departedDate` (loose dates ≤10), `status` (`serving\|departed`, **missing =
serving**), `bioAr/En` (≤5000), meta. Two admin screens over one collection: `priests` (filter `status = serving`) and
`departedPriests` (filter `status = departed`, new docs default `status: departed`). Seed: 9 serving
(`bemwa, bigol, bedaba, doumadious, moussa, yonathan, loukas, saleeb, barnaba`; sample: bigol, saleeb, barnaba) +
2 departed (`tadros` verified, `maximus` sample).

### `milestones/{id}` — `Milestone` (Hideable, orderable)
`titleAr` (**req**), `titleEn`, `descAr/En` (≤2000), `year` (int 1–2200), `icon` (`church, people, altar, pope, star`),
`order`, `visible` (no `sample` in admin). Seed: `since-1980`, `deacons-2022`, `hegumens-2022`, `pope-visit`.

### `saints/{id}` — `Saint` (Hideable, orderable)
`nameAr` (**req**), `nameEn`, `bioAr/En` (≤5000), `feastCopticAr/En`, `feastGregorian` (EN), `feastGregorianAr`
(≤300), `order`, `visible`. Seed: `maximus-domadius`, `moses-black`.

## Non-content collections

### `contact_messages/{id}` (created by the public form, `FirestoreRepository.submitContact`)
| Field | Type | Rule |
|---|---|---|
| `name` | string | 2–80, not whitespace-only (**required**) |
| `phone` | string | `''` or `^[0-9+]{5,15}$` (client normalises to local Egyptian form) |
| `email` | string | `''` or simple email, ≤254 |
| `message` | string | 5–1000, not whitespace-only (**required**) |
| `lang` | `ar\|en` | |
| `status` | `new` on create; admins toggle `new\|handled` | **required** |
| `createdAt` | `serverTimestamp()` == `request.time` | **required** |
At least one of phone/email must be non-empty. Written in **one batch** with `meta/contact_rate` (see below).
Admins add `updatedAt/updatedBy` when changing status.

### `meta/contact_rate`
Single doc `{lastAt: timestamp}` — global server-side throttle: every contact create must set
`lastAt == request.time` in the same batch, and it may only advance when `request.time > lastAt + 20 s`. Nobody can
read or delete it.

### `admins/{uid}`
`{email: string (≤254, required), role: 'owner' | 'editor'}` (+ optional `updatedAt/updatedBy` allowed by rules).
Doc id = Firebase Auth **UID**. Missing/unknown role is treated as **editor** (`AdminRepository.adminRole`,
`roleChanges`; rules `isOwner` checks `role == 'owner'`). `AdminRoles` in `admin_repository.dart`.

## Seed ids & retirement (`tool/`)

- `tool/gen_seed.py` is the **only** source of `assets/seed/seed.json` (never hand-edit the JSON; CI regenerates it
  and fails on any diff).
- `retired` dict in `gen_seed.py` → `tool/retired_seed_ids.json`: ids earlier seeds created that are no longer in the
  seed (`alerts: school-blessing-2026, holy-week-2027, summer-2027`; `seasons: summer-2027`;
  `liturgies: sum-sun-1, sum-sun-2, sum-sun-eve, sum-fri-1, sum-fri-2, sum-fri-3`;
  `activities: scouts, deacons, hymns, bible, summer, sports, exhibitions`; `priests: p1, p2, p3`;
  `milestones: founding, pastoral, consecration`). `seed_firestore.js --force` deletes them **unless** the doc carries
  `updatedAt`/`updatedBy` (edited in /admin).
- `tool/known_seed_ids.json`: every id any seed ever wrote (grow-only). `gen_seed.py` asserts
  `known − current − retired = ∅`, so removing an id from the seed **requires** adding it to `retired`.
- Seed counts (current): settings 2, alerts 4, seasons 5, liturgies 47, meetings 11, activities 11, clinics 11,
  facilities 5, priests 11, milestones 4, saints 2.

## Indexes

`firestore.indexes.json` is empty: the app reads whole (small) collections with `snapshots()` and filters/sorts in
Dart, so no composite indexes are needed. Adding a server-side `where`+`orderBy` query will require one.
