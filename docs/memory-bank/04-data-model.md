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
| `sample` | bool | false | **Unconfirmed / placeholder** awaiting the church. Public UI shows nothing since ADR-046 (badge / banner removed); admin shows «غير مؤكد»; assistant prefixes `[UNCONFIRMED]`; ADR-045 suppresses sample templates. Admin label "Unconfirmed (pending church confirmation)". |
| `updatedAt` | timestamp | — | Stamped by `AdminRepository._stamp` (`FieldValue.serverTimestamp()`); rules require `== request.time` or unchanged |
| `updatedBy` | string | — | Admin email (or uid); rules require it to equal `request.auth.token.email` (or uid) or be unchanged |

Rules `common(d, changed)`: ≤ 80 keys (60 before PR #11), `visible`/`sample` bool, `order` int in range, `image`
(if present and not null) passes `validImage`, `stampOk`. `meta()` = `['visible','sample','order','updatedAt','updatedBy']`
is added to every content allow-list. Since PR #11 every check runs only for the keys the write **creates or
changes** (`changedKeys`; a create checks all keys) — see `05-firebase.md` (expression budget).

### Optional `image` (PR #5) — `MediaImage` (`lib/domain/media.dart`)

Allowed (and shown) on **`priests`** (serving + departed), **`saints`**, **`milestones`**, **`activities`**,
**`alerts`**, **`seasons`** (`imageCollections` in `admin_schema.dart`). Since PR #11 the model (`Meeting.image`,
`Clinic.image`, `Facility.image`) and the rules also accept it on **`meetings`**, **`clinics`** and **`facilities`**;
since PR #12 the admin form has the field there too, and since PR #13 their cards show it (meeting / clinic: beside
the title; facility: in place of the type icon). It is **never required**; absent / `null` /
malformed = no image and the card keeps its icon / initials placeholder. The seed has no images.

| Key | Type | Rule |
|---|---|---|
| `source` | `url` \| `inline` \| `storage` | required inside the map |
| `url` | string ≤ 500 | `url`/`storage`: must match `^https://[^/\s]+[.][^/\s]+([/?#]\S*)?$` (https, host with a dot, no spaces) |
| `mediaId` | string | `inline`: required, `^[A-Za-z0-9_-]{1,128}$` → the `media/{mediaId}` doc. `storage`: object name |
| `alt` | string ≤ 300 | accessible description; UI falls back to the item's name |
| `w`, `h` | int 1–10000 | pixel size after resizing (optional) |

- `MediaImage.fromMap` is tolerant (wrong type / unknown source / http URL / missing id → `null`).
- **Legacy `priests.photoUrl`** (string ≤ 500, all empty in the seed) is still allowed by the rules and read as a
  fallback: `Priest.displayImage` = `image` ?? https `photoUrl`. The admin form no longer shows `photoUrl`; setting an
  image overrides it.
- Images are ignored by the assistant prompt (`buildAssistantInstruction` only reads text fields; tested — also
  for `gallery` URLs, media ids and alt text since PR #11).

### Optional `imageStyle` (PR #15, ADR-023)

On the 9 image collections (`alerts`, `seasons`, `meetings`, `activities`, `clinics`, `facilities`, `priests`,
`milestones`, `saints`): `imageStyle` string, one of `avatar` · `card` · `banner`; absent / `null` / anything else =
the section default (`settings/features.imageStyles[collection]`), then the built-in default (priests & clinics →
`avatar`, everything else → `card`; saints use a portrait card). Not seeded; new documents do not write it unset.

### Optional item detail page (PR #11) — `ItemDetails` / `CustomField` (`lib/domain/models.dart`)

On the **7 detail collections** `meetings`, `activities`, `clinics`, `facilities`, `priests`, `milestones`,
`saints` (**not** `liturgies`, `seasons`, `alerts`) every model has `details` (`ItemDetails.fromMap(doc)`;
`ItemDetails.none` for const constructors). All keys are optional. Except `detailsEnabled`, they default to the
pre-PR #11 behaviour (images / contacts / socials shown where they already were). `detailsEnabled` is **opt-out
since PR #14** (ADR-021): a document without it — every seeded and untouched item — has a public detail page and a
card link; only an explicit `false` removes them. The data model, rules and assistant grounding are in place
(PR #11); the admin editor since PR #12 (grouped `DocEditor`, `07-admin-dashboard.md`) and the public
`/<section>/:id` pages since PR #13 (`ItemDetailPage`, `06-features.md`). `showContacts` / `showSocials` also gate
the buttons already on the item's list card (PR #13).

| Key | Type / cap (rules) | Default | Meaning |
|---|---|---|---|
| `detailsEnabled` | bool | **true** (missing = on, PR #14 / ADR-021) | the item has a public detail page (and its detail text is grounded for the assistant); only an explicit `false` removes it. Rules still only type-check it |
| `showDetailImages` | bool | true | show cover + gallery on the detail page (also needs `Sections.media`) |
| `showContacts` / `showSocials` | bool | true | show the item's phones / social links (assistant too; socials also need `Sections.socials`) |
| `detailsAr` / `detailsEn` | string ≤ 10,000 | `''` | long text |
| `extraFields` | list ≤ 15 (`MediaLimits.maxExtraFields`) of `{titleAr, titleEn, valueAr, valueEn}` | `[]` | admin-defined rows; all 4 keys written, titles ≤ 150, values ≤ 2000, a title (titleAr, else titleEn) required. The model drops empty rows and caps at 15 |
| `gallery` | list ≤ 8 (`MediaLimits.maxGalleryItems`) of `image` maps | `[]` | same shape as `image` (rules don't range-check `w`/`h` of gallery items); inline bytes fetched only when the detail page opens. The model keeps usable images, max 8 |
| `contactPhone` | string ≤ 20 | `''` | primary phone; **clinics read `bookingPhone`, facilities `phone`** (no new key there) |
| `whatsapp` | string ≤ 20 | `''` | WhatsApp number (clinics already had it) |
| `whatsappUrl`, `facebookUrl` | `''` / http(s) URL ≤ 500 | `''` | group / page links (meetings already had both) |
| `youtubeUrl`, `instagramUrl` | `''` / http(s) URL ≤ 500 | `''` | |
| `externalUrl` | `''` / http(s) URL ≤ 500 | `''` | external / registration button; **activities use their existing `link`** (no `externalUrl` key) |
| `externalLabelAr` / `externalLabelEn` | string ≤ 80 | `''` | custom button label (UI falls back to `openPage`) |
| `contactNoteAr` / `contactNoteEn` | string ≤ 500 | `''` | how to contact / register |

- Rules: `detailKeys()` is concatenated to the 7 allow-lists; each also allows `image` and the phone/link keys it
  lacked (`contactPhone` except clinics/facilities, `externalUrl` except activities). The new text keys must be
  strings (`''` when cleared; the admin form never writes `null`), the shared phone/link keys keep accepting `null`.
  `CustomField.isEmpty` = all four blank.
- Media clean-up: `orphanedMediaIds(before, after)` accepts an `image` map **or** a `gallery` list on either side;
  `extractDocMediaIds(doc)` / `orphanedDocMediaIds(before, after)` cover `image` + `gallery` together, so an inline
  image moved between the cover and the gallery in one save is never deleted (used by PR #12's editor, and since PR
  #11's review fix by the admin list's delete handler, so deleting an item also removes its inline gallery photos).
- Writes: one request cannot carry a full 8-photo `gallery` **and** a full 15-row `extraFields` (Firestore's
  1,000-expression cap) — save each list in its own update. Since PR #12 the admin editor does exactly that
  (`splitSavePayload`: other fields → `gallery` → `extraFields`; `05-firebase.md`).

## `media/{mediaId}` — inline image bytes (PR #5)

Spark plan ⇒ no Cloud Storage, so device uploads are stored **in Firestore**, one doc per image, separate from the
content docs so **lists never download image bytes** (a card fetches its own image lazily, once per session).

| Field | Type | Rule |
|---|---|---|
| `dataBase64` | string | **required**, 4 … **950,000** chars |
| `contentType` | `image/jpeg` \| `image/webp` \| `image/png` | **required** |
| `w`, `h` | int 1–10000 | |
| `bytes` | int 1 … 700,000 | decoded size |
| `createdAt` | timestamp | **required**, `== request.time` on create (unchanged on update) |
| `createdBy` | string | **required**, the admin's token email (or uid) on create (unchanged on update) |
| `refs` | list ≤ 20 | reserved (not written yet) |

Public read; admins create/update/delete (`validMedia`). Written by `FirestoreMediaRepository.upload`; deleted best
effort when an image is replaced/removed in the editor (`orphanedMediaIds`) or its item is deleted (cover + gallery,
`orphanedDocMediaIds`). Not seeded.

## `settings/church` — `ChurchSettings`

| Field | Type | Rules limit | Notes |
|---|---|---|---|
| `nameAr` | string | **required**, ≤ 300 | |
| `nameEn` | string | ≤ 300 | admin form marks it required |
| `addressAr`, `addressEn` | string | ≤ 300 | |
| `transportAr`, `transportEn` | string | ≤ 2000 | "Getting here" |
| `lat`, `lng` | number | −90…90 / −180…180 | `31.260138`, `30.01129` |
| `coordinatesApproximate` | bool | allowed key; **bool** (`optBool`, PR 1) | in seed (`false`), not in Dart model/admin form |
| `mapsQuery` | string | ≤ 200 | used for embed + directions (`"31.260138,30.01129"`) |
| `mapsUrl` | string | ≤ 500 | "Open in Google Maps" |
| `phones` | list of `{labelAr, labelEn, number, isMobile}` | list ≤ 20 | `PhoneEntry`; `isMobile` → WhatsApp button. Legacy `label` key read as fallback |
| `whatsapp` | string | ≤ 20 | chat number (empty — church publishes none) |
| `whatsappChannel`, `facebook`, `youtube`, `instagram` | string (URL) | ≤ 500 | |
| `verseAr`, `verseEn` | string | ≤ 300 | Rev 2:10 — **not shown publicly since PR #17** (the hero shows the verse of the day); kept for the admin form and assistant grounding |
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
| `sections` | map `<sectionKey, bool>` | missing key = **on**; non-bool values ignored. Keys = `Sections.all`: `schedule, meetings, clinics, services, history, milestones, saints, priests, departedPriests, activities, alerts, contactInfo, socials, contactForm, assistant, media` (`media` = show optional item images; not a page) |
| `homeOrder` | list of block keys | `normalizeHomeOrder`: unknown/duplicate dropped, missing appended in default order. Blocks (`HomeBlocks.defaultOrder`): `banner, alerts, nextMass, quickContacts, milestones, directory, map` |
| `homeHidden` | list of block keys | unknown keys dropped |
| `heroTitleAr/En` | string ≤ 200 | empty → church name |
| `heroSubtitleAr/En` | string ≤ 300 | empty → no ribbon (or the address when `heroShowAddress`) |
| `heroSeasonTint` | bool, default **true** (ADR-050) | season theme's colour wash over the hero painting (occasion themes only); written only once off or already stored |
| `heroShowAddress` | bool, default false (PR #22) | address ribbon in the hero when no subtitle; written only once on or already stored |
| `aboutMilestones` | bool, default **true** (ADR-052) | milestones also listed on `/about` («محطات الكنيسة») when the `milestones` section is on; written only once off or already stored; rules: bool |
| `errorReporting` | bool, default **true** (PR #24, ADR-034) | error reports to Sentry from the web / Android app; off = nothing is sent (`ErrorReportingGate`, SDK closed). Written only once off or already stored; seeded `true` |
| `bannerEnabled` | bool | false |
| `bannerAr`, `bannerEn` | string ≤ 500 | banner shows only if enabled **and** some text |
| `bannerLink` | string ≤ 500 | `''`, in-app path `/…`, or `http(s)://host.tld…` (rules regex mirrors `isValidUrl(allowPath: true)`) |
| `theme` | `goldenHour\|holyWeek\|resurrection\|nativity\|epiphany\|fasting\|marian\|navy\|green\|brown\|purple` (PR #17) | missing, legacy `burgundy` and unknown → `goldenHour`. Legacy `purple` (ADR-043) reads as the oxblood accent and is no longer offered. The selected theme applies when no admin range (with `auto`), no active season theme (with `followSeason`) and no Easter date (with `auto` + `easter`) applies — precedence in that order (ADR-043) |
| `occasions` | map (PR #17, ADR-025) | `{auto: bool (false), easter: bool (true), resurrectionDays: int 1–50 (7), schedule: {r1…r12: 'theme\|YYYY-MM-DD\|YYYY-MM-DD'}, followSeason: bool (true), seasonThemes: {seasonKey: themeKey\|'none'}}` (`OccasionConfig`; `followSeason` / `seasonThemes` ADR-043). Inclusive Cairo dates; invalid / reversed ranges dropped when read. Precedence: first matching range (with `auto`) > the active season's theme (with `followSeason`; first key in `SeasonThemes.seasonKeys` order) > the Easter ranges (with `auto` + `easter`) > `theme`. `seasonThemes` stores only differences from the defaults (holy_week → holyWeek, pascha → resurrection, nativity, epiphany, marian, fast → fasting; revivals / summer → none). Missing = manual + follow the season |
| `themeColors` | map (PR #17) | per preset key a string of the 10 palette colours in `ThemePalette.keys` order (`primary\|onPrimary\|onPrimaryAccent\|background\|surface\|surfaceAlt\|ink\|muted\|goldText\|script`), each `#RRGGBB` or empty (= the preset's). Saved auto-corrected for contrast and re-corrected when rendered. Its own field (and write) for the rules budget. Missing = presets as built |
| `heroVideos` | map (PR #17, ADR-026) — **legacy since PR #25 (ADR-036)** | no longer read or written by the app (the YouTube hero video library was removed); a stored value is kept untouched and the rules still accept / validate the key so saves keep working |
| `pageHeaders` | map `<pageKey, PageCustom>` (PR #11) | `{}`. Keys = `CustomizablePages.all`: `about, schedule, education, activities, clinics, services, contact, ask`; each entry `{titleAr, titleEn` ≤ 200, `subtitleAr, subtitleEn` ≤ 300, `introAr, introEn` ≤ 1500`}` (all 6 keys written). Unknown pages / non-maps / empty entries are dropped by `fromMap`; `toMap` writes non-empty entries only. `pageHeader(key)` → `PageCustom.empty` when unset. Rendered since PR #13 (`CustomizablePageHeader` / `PageIntro`: title/subtitle override for the current language only; intro via `context.pick`) |
| `footer` | map (PR #11, FR-G-04) | `{showPhones: true, showSocials: true, showQuickLinks: true, noteAr: '', noteEn: ''}` (`FooterConfig`); notes ≤ 500. Rendered by `Footer` since PR #13 (phones also need `contactInfo`, socials `socials`) |
| `updatedAt`, `updatedBy` | | stampOk |

- `FeatureSettings.defaults` (everything on) is used before the doc loads and when it does not exist.
- **Seed** (`gen_seed.py`): every section on **except `clinics: false`** (PR 1) — `/clinics` stays off until the
  church office confirms the clinics and their booking numbers. Live docs keep whatever the admin set.
- `toMap()` always writes **all** 19 section keys explicitly. Live docs saved before PR #5 lack `media` → on; before
  PR #16 lack `dailyVerse` → on; before PR #18 lack `customSections` / `customPages` → on.
- The seed (PR #11) adds `pageHeaders: {}` and the default `footer` map; live docs get them with
  `node tool/seed_firestore.js --fill-missing` (adds absent fields only) or on the next save in /admin. Missing =
  defaults, so nothing changes until then.
- `HomeBlocks.requires`: `alerts→alerts`, `nextMass→schedule`, `quickContacts→contactInfo`,
  `milestones→milestones`, `map→contactInfo` (block disappears when its section is off). `directory` and `banner`
  have no section.

- **Today layer (PR #31, ADR-039 / ADR-040)** — top-level keys, not seeded, read into `FeatureSettings.today` /
  `.dayEvents` and **never written by `toMap()`** (edited by /admin → «اليوم والبث المباشر» with field-level merges):

  | Key | Type / rule | Default |
  |---|---|---|
  | `copticStrip` | `all` \| `home` \| `off` | `all` (Coptic date strip on every page) |
  | `dayStartMode` | `fixed` \| `sunset` | `fixed` |
  | `dayStartsAt` | `''` or `HH:mm` | `''` = 18:00; `00:00` = civil midnight |
  | `topEvent`, `commemoration` | bool | true, true |
  | `topEventServices` | bool (PR #38, ADR-045): with no church event, the top event shows today's / tonight's programme service of an active season | true |
  | `liveEnabled` | bool | false |
  | `liveUrl` | `''` / http(s) URL ≤ 500 | `''` (banner needs a link) |
  | `liveLabelAr`, `liveLabelEn` | string ≤ 120 | `''` = «بث مباشر الآن من الكنيسة» / "Live now from the church" |
  | `liveEndsAt` | timestamp / null | none (automatic switch-off) |
  | `liveBadgeHideOnHome` | bool (PR #35, ADR-044; validated in the live gate of `validFeatures`) | true (Home shows only the banner while live) |
  | `dayEvents` | list ≤ 20 of strings `date␟endDate␟start␟end␟titleAr␟titleEn␟speakerAr␟speakerEn␟topicAr␟topicEn␟noteAr␟noteEn␟link[␟attachmentUrl␟attachmentLabelAr␟attachmentLabelEn[␟id]]` (U+001F; trailing attachment fields and optional 17th `id` field `[a-z0-9]{8,10}` — PR #38 / ADR-045 / ADR-059; date `YYYY-MM-DD` required, endDate optional, times `''`/HH:mm, titleAr 1–300, texts ≤ 300, notes ≤ 500, link `''` / path / http(s)) | `[]` |
  | `notifyTypes` | list ≤ 6 of strings `id␟time␟daysBefore␟titleAr␟titleEn␟bodyAr␟bodyEn` (ADR-059; 6 fixed types: `announcements, verse_daily, katameros_daily, seasons, feasts, reminders`) | `[]` (built-in defaults apply) |
  | `reminderSources` | comma-separated string of enabled sources (ADR-059; subset of `lit,mtg,day`) | `'lit,mtg,day'` |
  | `venues` | list ≤ 12 of strings `key␟labelAr␟labelEn` (key `[a-z0-9_-]{1,30}`, labelAr 1–80, labelEn ≤ 80) — PR #32, ADR-041 | missing / empty = `main` الكنيسة الكبرى, `lower` القاعة السفلية, `services` مبنى الخدمات |
  | `audiences` | same format — PR #32, ADR-041 | missing / empty = `general` عام, `youth` شباب, `children` أطفال |
  | `seasonVerses` | list ≤ 40 of strings `seasonKey␟textAr␟refAr`, optionally `␟textEn␟refEn` (ADR-047; season key of `validSeason`, text 1–500, ref ≤ 60, textEn ≤ 500, refEn ≤ 60) — PR #33, ADR-042 | missing / empty = the general daily list always |
  | `seasonPreset` | map `{seasonId, seasonKey, appliedAt, startsAt, endsAt, options[≤8, no duplicates], previous{seasonActive, replacesRegular, meetings, clinics, heroMotion, weddingBookingOff, liveUrl, liveEndsAt, attachmentUrl, attachmentLabelAr, attachmentLabelEn, theme}}` or null — written only by /admin «تجهيز الموسم» (PR #33, ADR-042; `startsAt`, option `theme` and `previous.theme` ADR-043) | none applied |
  | `weddingBookingOff` | bool — PR #33, ADR-042 | false (the wedding booking choice shows) |

- PR #18 (ADR-027): `sections.customSections` (custom categories at `/section/*` + their menu entries) and
  `sections.customPages` (custom pages at `/page/*` + their menu entries); missing = on; seeded `true`.
- `dailyVerse` (PR #16, ADR-024): map `{mode: 'daily'|'fixed' (default daily), textAr: string ≤500, refAr: string ≤60,
  textEn?: string ≤500, refEn?: string ≤60}` (English keys ADR-047, written only when set);
  missing map or keys = daily rotation; a fixed verse with empty text falls back to daily. On/off is the section
  **`sections.dailyVerse`** (missing = on; seeded `true`). The map is written only once it differs from the default or
  is already stored. Verse list: bundled asset `assets/verses/daily_verses.json` (not Firestore). Since PR #17 the
  verse is shown **in the hero** (`HeroVerse`), not in a separate card.
- `occasions`, `themeColors` (PR #17): not seeded (`heroVideos`: legacy, see above) (missing = current behaviour); each is written only once
  it differs from the default or is already stored, in its own write (`featuresSaveWrites`). The seed keeps
  `theme: burgundy` on purpose (it exercises the legacy mapping).
- `imageStyles` (PR #15, ADR-023): map `collection → avatar|card|banner`, keys limited to the 9 image collections;
  missing key = built-in default. Written only once an admin sets one (saves keep working against older rules).

## `settings/notifications` — `NotifySchedule` (`lib/domain/push.dart`)

Added in ADR-059 for scheduled remote push notifications and sender state tracking:

| Field | Type / Rule | Description |
|---|---|---|
| `schedule` | list ≤ 20 of strings | Rows: `id␟atUtcIso␟targets␟titleAr␟titleEn␟bodyAr␟bodyEn␟link␟eventKey` (9 U+001F fields; `atUtcIso` = `YYYY-MM-DDTHH:mm:ssZ`, whole seconds, no milliseconds — `scheduleIso()`; titleAr 1–120 and bodyAr 1–300 required). `targets` is `'all'`, `'app'`, or `'web'`. `link` is `/...` or empty. `eventKey` is empty or `(lit\|meeting\|day\|season)-[a-z0-9-]{1,40}`. Client writable by admins. |
| `status` | map `<rowId, rowStatus>` | Per-row delivery status: `{state: 'draft'\|'sending'\|'ok'\|'partial'\|'error'\|'unconfirmed'\|'expired', result, claimedAt: ISO, topics: {<topic>: 'ok'\|'error'\|'unconfirmed'}}`. Server/sender only (client write rejected). |
| `sentLog` | list ≤ 30 strings (or maps) | History log entries: sender writes serialized strings `id␟sentAt␟result␟titleAr␟trigger` (capped at 30 items); Dart parser handles both strings and map objects. Clear allowed for owner only (`size() == 0`). |
| `health` | map | Sender health stats: `{lastRunAt, lastError, lastSeasonDate, sentToday, sparkReadsToday}`. Server/sender only. |
| `reminderPlan` | map | Internal daily reminder planner state. Server/sender only. |
| `remindersSent` | map | Set of processed reminder occurrences. Server/sender only. |
| `updatedAt`, `updatedBy` | stampOk | Audit timestamps. |

Rules: Read restricted to `isAdmin()` (`allow read: if docId != 'notifications' || isAdmin();`). Client writes to server fields (`status`, `reminderPlan`, `remindersSent`, `health`) rejected.

## Content collections

### Optional programme details (PR #32, ADR-041) — `ProgramInfo` (`lib/domain/program.dart`)

On `liturgies`, `meetings` and `seasons` only; every key optional (missing = nothing shown):
`speakerAr`, `speakerEn` (≤ 200), `topicAr`, `topicEn` (≤ 300), `choirAr`, `choirEn` (≤ 200), `venue`, `audience`
(keys of `settings/features.venues` / `.audiences`, `[a-z0-9_-]{0,30}`; an unknown key shows nothing),
`attachmentUrl` (https URL only — a Google Drive or other link; **no file upload**), `attachmentLabelAr/En` (≤ 80;
blank = «البرنامج / الكتيب»). The free-text `placeAr/En`, `audienceAr/En` (liturgies) and `hallAr/En` (meetings)
stay as before.

### `alerts/{id}` — `Alert` (Hideable)
`titleAr` (**req**, ≤300), `titleEn` (≤300), `bodyAr`/`bodyEn` (≤2000; admin form caps 1000), `active` (bool,
default false in model), `startsAt`/`endsAt` (timestamp), `priority` (int 0–1000, higher first), `link` (≤500;
`''`, in-app path `/…` or `http(s)://host.tld…` — rules `optUrlOrPath`), `image` (optional), + meta. Seed ids: `follow-announcements`, `nativity-fast-2026`, `revival-maximus-2027`,
`revival-moses-2027`.

### `seasons/{id}` — `Season` (not Hideable)
`key` (**required**, one of `holy_week, pascha, nativity, epiphany, marian, fast, revival_maximus, revival_moses, summer, apostles, nayrouz, kiahk, great_lent`; epiphany / marian / fast ADR-043, the last four ADR-051), `replaceDates` (optional list ≤ 10 of distinct `YYYY-MM-DD` civil Cairo dates: an additive season replaces the regular services on those days only, ADR-051), `nameAr` (**req**),
`nameEn`, `startsAt`, `endsAt` (timestamps, exact window), `active` (bool, default false in model),
`replacesRegular` (bool, **missing = true**, PR 1: `true` = its services REPLACE the regular schedule on the days they
cover — Holy Week, Pascha, Nativity; `false` = ADDITIVE evening revival, regular morning masses continue — see
`06-features.md`), `image` (optional; shown beside the season's date range — e.g. a revival poster). No
`visible`/`order` in the admin form (rules would allow `meta()` keys). Seed: `nativity-2027`, `holy-week-2027`,
`pascha-2027` (`replacesRegular: true`), `revival-maximus-2027`, `revival-moses-2027` (`replacesRegular: false`).

### `liturgies/{id}` — `Liturgy` (Hideable)
| Field | Type | Notes |
|---|---|---|
| `type` | `mass\|vespers\|praise\|other` | missing → `mass`. Next-service card uses `mass` only, except while a season that replaces the regular schedule is active: then every service of that season counts (ADR-043) |
| `nameAr` (**req**), `nameEn` | string ≤300 | |
| `weekday` | int 1–7 or null | weekly schedule |
| `date` | timestamp or null | one-off (Cairo day). Admin requires `weekday` **or** `date` (`requireAnyOf`) |
| `start` | "HH:mm" | **required key** (rules: `'start' in d`) |
| `end` | "HH:mm" or '' | may be ≤ start = crosses midnight; missing end → start + 120 min |
| `placeAr/En`, `audienceAr/En` | string ≤300 | |
| `seasonKey` | season key or null | null = regular schedule. Keys: holy_week, pascha, nativity, epiphany, marian, fast (the last three ADR-043), revival_maximus, revival_moses, summer, apostles, nayrouz, kiahk, great_lent (ADR-051). An undated seasonal service does not occur on a day its schedule-replacing season has dated services (ADR-043) |
| `replacesDay` | bool, missing = false (ADR-050) | seasonal feast liturgy in an ADDITIVE season: hides every regular mass of its day (off: only the overlapping ones). Rules: `optBool` |
| `order`, `visible`, `sample` | | |
Seed: 47 docs, all `sample: true` (ids like `fri-1`, `sun-youth`, `sat-vespers`, `nat-eve`, `rev-max-1…7`,
`rev-max-feast`, `hw-day-1…3`, `hw-eve-1…3`, `hw-palm`, `hw-thursday`, `hw-friday`, `hw-saturday`, `pascha-eve`,
`pascha-day`, `rev-moses-1…7`, `rev-moses-feast`).

### `meetings/{id}` — `Meeting` (Hideable)
`stage` (**req** ≤40; admin choices `angels, primary, preparatory, secondary, youth, university, graduates, family,
men, women, elderly`; others render under "Other stages"), `nameAr` (**req**), `nameEn`, `weekday` (1–7),
`start`/`end` (HH:mm), `hallAr/En`, `facebookUrl`/`whatsappUrl` (≤500, `''` or `http(s)://host.tld…` — rules
`optHttpUrl`), `notes` (≤300), meta. Seed: 11 docs (id =
stage), all `sample: true`.

### `activities/{id}` — `Activity` (Hideable, orderable)
`category` (≤40; admin choices `service, choir, hymns, youth, servants, media, drama, scouts, deacons, bible, summer,
sports, exhibitions`, default `service`), `titleAr` (**req**), `titleEn`, `descAr/En` (≤2000), `scheduleAr/En` (≤300),
`ageRange` (≤60), `contactPhone` (≤20), `link` (≤500, `''` or `http(s)://host.tld…` — rules `optHttpUrl`),
`image` (optional), meta. Seed: 11 verified docs (`deacons-choir`, `avamose-choir`,
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
`name` (Arabic, **req**), `nameEn`, `photoUrl` (≤500, all empty; legacy, not in the admin form), `image` (optional,
see above), `rank` (`hegumen\|priest`, default `priest`),
`ordinationDate`, `hegumenDate`, `departedDate` (loose dates ≤10), `status` (`serving\|departed`, **missing =
serving**), `bioAr/En` (≤5000), meta. Two admin screens over one collection: `priests` (filter `status = serving`) and
`departedPriests` (filter `status = departed`, new docs default `status: departed`). Seed: 9 serving
(`bemwa, bigol, bedaba, doumadious, moussa, yonathan, loukas, saleeb, barnaba`; sample: bigol, saleeb, barnaba) +
2 departed (`tadros` verified, `maximus` sample).

### `milestones/{id}` — `Milestone` (Hideable, orderable)
`titleAr` (**req**), `titleEn`, `descAr/En` (≤2000), `year` (int 1–2200), `icon` (`church, people, altar, pope, star`),
`image` (optional), `order`, `visible` (no `sample` in admin). Seed: `since-1980`, `deacons-2022`, `hegumens-2022`, `pope-visit`. Live `pope-visit` images are Hosting files
`/media/milestones/pope-visit-*.webp` (ADR-046; never Storage on Spark).

### `saints/{id}` — `Saint` (Hideable, orderable)
`nameAr` (**req**), `nameEn`, `bioAr/En` (≤5000), `feastCopticAr/En`, `feastGregorian` (EN), `feastGregorianAr`
(≤300), `image` (optional), `order`, `visible`. Seed: `maximus-domadius`, `moses-black`.

### `categories/{auto-id}` — `CustomCategory` (`lib/domain/custom_content.dart`, PR #18, ADR-027; Hideable, orderable)
`slug` (**req**, `[a-z0-9]+(-[a-z0-9]+)*` ≤ 60, unique per collection — checked by the admin form, not the rules;
public page `/section/<slug>`), `nameAr` (**req**, ≤ 120, not blank), `nameEn` (≤ 120), `introAr/En` (≤ 1500),
`icon` (`star, church, people, heart, book, music, medical, school, event, volunteer, donate, info`; missing =
star), `imageStyle` (default style of its items, ADR-023), `showInNav` (bool, missing = **true**), `visible`,
`order`. Not seeded. Deleting one first sets `visible: false` on its visible entries (never deletes them).

### `entries/{auto-id}` — `CategoryEntry` (PR #18; Hideable, orderable)
`categoryId` (**req**, the category's doc id; an entry whose category is gone is never public), `titleAr`
(**req**, ≤ 300), `titleEn` (≤ 300), `descAr/En` (≤ 2000), `contactPhone` (digits / `+`, ≤ 20), `externalUrl`
(`''`, an in-app path or an http(s) URL, ≤ 500), `externalLabelAr/En` (≤ 80), `image` + `imageStyle` (item style,
else the category's), `visible`, `order`, `sample`. Not seeded.

### `pages/{auto-id}` — `CustomPage` (PR #18; Hideable, orderable)
`slug` (**req**, as above; public page `/page/<slug>`), `titleAr` (**req**, ≤ 200, not blank), `titleEn` (≤ 200),
`subtitleAr/En` (≤ 300), `image` (optional hero), `showInNav` (bool, missing = **false**: pages are off the menu
by default), `visible`, `order`, `blocks` (≤ 20, saved in their own write). **Each block is one string**:
`type␟textAr␟textEn␟url␟account␟instapay␟wallet` (U+001F, `PageBlock.encode` / `fromStored`; maps are still read
tolerantly). Types: `heading`, `paragraph` (texts ≤ 4000), `image` (`url` = https picture link, texts = caption),
`button` / `link` (texts = label, `url` = in-app path or http(s) URL), `donation` (`account` ≤ 120, `instapay` ≤ 80,
`wallet` ≤ 30, texts = notes; display only). Not seeded.

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

PR #18 (ADR-028) adds: `category` (the id of a `settings/contact` category — `c1…c4` defaults or, since PR #19, a
stable random id `c[0-9a-z]{1,15}`; must exist and be on), `kind`
(`general|booking|complaint|suggestion`, must match the slot), bookings: `bookingType` (subtype key
`[a-z0-9_-]{1,30}`) + `preferredDate` (`YYYY-MM-DD`, required) + a non-empty `phone`; `anonymous: true` (complaint /
suggestion slots that allow it) — then the doc has **only** `category, kind, anonymous, message, lang, status,
createdAt` (no name / phone / email at all). Admin-only: `status` also `contacted|confirmed|declined` (bookings),
`adminNotes` (≤ 2000). Messages without `category` (older ones) are general inquiries in the inbox.

### `settings/contact` — `ContactSettings` (`lib/domain/contact_categories.dart`, PR #18, ADR-028)
`categories: {<id>: string}`, 1–12 entries. **Ids are stable and never reused (PR #19):** the defaults are
`c1…c4`, every type an admin adds gets `newContactCategoryId` = `c` + 10 random lower-case letters / digits (never
digits only, never an id removed in the editor), so deleting a type never re-labels its old messages (they show
under "Other / deleted type"). The rules check only the id format (`c[0-9a-z]{1,15}`); non-reuse is guaranteed by
the editor (random ids), not by the rules. Legacy slot ids `c5…c12` stay valid. Each entry is one string `kind␟on␟anon␟order␟labelAr␟labelEn␟subtypes` (on / anon
`1`/`0`; anon only for complaint / suggestion; `labelAr` 1–80 not blank, `labelEn` ≤ 80; up to 8 subtypes
`key|labelAr|labelEn` joined by U+001E, Arabic label 1–60). **Missing doc = code defaults**
(`ContactSettings.defaults` = rules `defaultContactCats()`): c1 general inquiry, c2 hall booking (wedding فرح /
condolence عزاء), c3 complaint (anonymous allowed), c4 suggestion (anonymous allowed). Not seeded.

### `settings/assistant` — `AssistantSettings` (`lib/domain/assistant_settings.dart`, PR #19, ADR-029)
Public read, admin write (`validAssistant`). **Missing doc / blank text / null number = code default**; not seeded.

| Field | Type / limit | Default (code) |
|---|---|---|
| `model` | `''` or `gemini-[a-z0-9][a-z0-9.-]{0,52}` (≤ 60) | `AppConfig.geminiModel` = `gemini-3.1-flash-lite`; 1.x/2.x ids ignored, a rejected model falls back |
| `instructions` | string ≤ 4000 | `defaultInstructions` (persona / tone; the scope + grounding rules are always added) |
| `topics` | string ≤ 2000, one topic per line (`-`/`*`/`•` bullets stripped) | `defaultTopics` (times, meetings, clinics, activities, priests, saints, history, announcements, contact, bookings, donations, custom sections / pages) |
| `refusalAr`, `refusalEn` | string ≤ 500 | `defaultRefusalAr/En` |
| `welcomeAr`, `welcomeEn` | string ≤ 500 | `askIntroText` (names only switched-on sections, ADR-051) |
| `showSuggestions` | bool (PR #21) | `false` — no chips on /ask; when on, only the admin questions below (no built-in fallbacks) |
| `suggestionsAr`, `suggestionsEn` | string ≤ 300, one question per line, first 3 used | none |
| `sourceDomains` | string ≤ 300, `[a-z0-9., -]*`, comma separated (PR #21, ADR-031) | `st-takla.org` — the only source for faith questions outside the data (search link) |
| `faithReplyAr`, `faithReplyEn` | string ≤ 300 (PR #21, ADR-031) | `defaultFaithReplyAr/En` — shown before the source-search and `/contact` links |
| `mentionUnconfirmed` | bool (PR #21, ADR-030) | `false` — off: `[UNCONFIRMED]` markers are stripped from the prompt and the model never mentions them |
| `maxChars` | null or int 50–1000 | 500 |
| `perMinute` | null or int 1–20 | 4 |
| `perDay` | null or int 1–100 (PR #21, ADR-031) | 3 questions per device per Cairo day |
| `perDaySeason` | null or int 1–100 (ADR-042) | 6 while an exceptional season is active |
| `exceptionalSeasons` | null or list ≤ 13 of season keys (ADR-051) | `exceptionalSeasonKeys`: holy_week, pascha, nativity, revival_maximus, revival_moses, great_lent, kiahk, marian; `[]` = none |
| `perSession` | legacy, null or int 1–200 — still accepted by the rules, **ignored** since PR #21 | — |
| `updatedAt`, `updatedBy` | stamps (`stampOk`) | |

Out-of-range stored numbers are clamped when read.

### `meta/contact_rate`
Single doc `{lastAt: timestamp, lastMsgId: string}` — global server-side throttle: every contact create must set
`lastAt == request.time` **and** `lastMsgId = <the new message's id>` in the same batch (`submitContact`), and it may
only advance when `request.time > lastAt + 10 s` (PR 1; was 20 s). The rules require that `lastMsgId` (10–64
alphanumerics) did not exist before the write and exists after it, and the message create requires
`getAfter(meta/contact_rate).lastMsgId == its id`, so the throttle can never be bumped on its own (SEC-01). Nobody
can read or delete it. Older live docs without `lastMsgId` are simply replaced by the next valid submission.

### `push_queue/{id}` (ADR-060)
Batch-written queue doc created by web clients subscribing or unsubscribing to push topics.
- Fields:
  - `token`: FCM registration token (`^[a-zA-Z0-9:_-]{20,400}$`).
  - `want`: list of general topics (`web_announcements_ar`, `web_announcements_en`, `web_seasons_ar`, `web_seasons_en`).
  - `rem`: list of reminder topics, comma-separated string (`<= 2600` chars), max 30 topics matching `remList()`.
  - `drop`: list of dropped reminder topics, comma-separated string (`<= 2600` chars), max 30 topics matching `remList()`.
  - `prevToken`: optional previous token for rotation.
  - `createdAt`: server timestamp (`== request.time`).
- Rules: create-only, read/update/delete denied to all clients. Verified against `meta/push_rate` in the same batch.
- Drained every 15 min by Cloudflare Worker Cron 2 via Google IID REST.

### `meta/push_rate` (ADR-060)
Rate throttle doc for `push_queue` batch writes:
- Fields: `{lastAt: timestamp, count: int, day: int, lastId: string}`.
- Rules: 3-second throttle (`request.time > resource.data.lastAt + duration.value(3, 's')`), UTC integer day, count capped at 1000/day. Read/delete denied to all clients.

### `meta/push_topics` & `meta/push_plan` (ADR-060)
- `meta/push_topics`: topic subscriber counts and health stats, written by Cloudflare Worker Cron 2 (Google IID queue drain).
- `meta/push_plan`: computed schedule of upcoming reminder topics, written by Cloudflare Worker Cron 3 (reminder planner).
- Rules: read-only for `isAdmin()`, client writes denied.

### `admins/{uid}`
`{email: string (≤254, required), role: 'owner' | 'editor'}` (+ optional `updatedAt/updatedBy`, checked by
`stampOk` since PR 1).
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
- `seed_firestore.js --fill-missing` adds only absent fields to existing docs and **recurses into nested maps**
  (PR 1, `missingFields`): e.g. a new key inside `settings/features.sections` is added as a field-path update, while
  every existing value (admin edits included) is left untouched. `--force` overwrites whole docs (never on production
  without explicit approval).
- `tool/known_seed_ids.json`: every id any seed ever wrote (grow-only). `gen_seed.py` asserts
  `known − current − retired = ∅`, so removing an id from the seed **requires** adding it to `retired`.
- Seed counts (current): settings 2, alerts 4, seasons 5, liturgies 47, meetings 11, activities 11, clinics 11,
  facilities 5, priests 11, milestones 4, saints 2.

## Hosting data file `/data/today.json` (PR #31, ADR-040)

Not Firestore: written by `.github/workflows/synaxarium.yml` (twice a day) and every `deploy.yml` build.
`{"source": "api.katameros.app", "fetchedAt": ISO, "days": {"YYYY-MM-DD": {"coptic": "25/2/1743", "feastAr", "feastEn",
"ar": [Synaxarium titles], "en": [...]}}}` for yesterday … +7 (Cairo dates). Read by `SynaxariumSource`
(device-cached). Missing / malformed = computed feasts.

## Indexes

`firestore.indexes.json` is empty: the app reads whole (small) collections with `snapshots()` and filters/sorts in
Dart, so no composite indexes are needed. Adding a server-side `where`+`orderBy` query will require one.
