# 05 — Firebase

> No secret values in this file. The service-account key lives only in the GitHub secret
> `FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`. The Firebase **web API key** in `lib/firebase_options.dart` (also used
> dynamically by `.github/workflows/seed.yml` to send a password-reset email) is a public client identifier, not a secret.
> GitHub Secret Scanning Alert #1 flagged this generic Google API key pattern and was resolved as `false_positive`
> (per Google/Firebase guidance: client API keys identify the project, while Firestore Rules protect data and App Check guards AI Logic).

## Project

| | |
|---|---|
| Project id | **`asafra-church-portal`** (`.firebaserc` default, `FIREBASE_PROJECT_ID` in `deploy.yml`) |
| Project number / sender id | `724175543696` |
| Plan | **Spark** (no-cost) — per project setup, not visible in the repo. Business case recommends Blaze + $5 budget alert (see `11-open-tasks.md`). **Cloud Storage for Firebase is not available on Spark** (since Oct 2024 a default bucket needs Blaze; Spark projects cannot provision or access buckets — <https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024>), so uploaded images live in Firestore `media/` (ADR-017). |
| Firestore | Default database, location **`europe-west1`**, created in production mode (README) |
| Hosting | Site **`maximos-domadios-church`** → <https://maximos-domadios-church.web.app> (+ `.firebaseapp.com`) serves the app (target `app`); default site `asafra-church-portal` → `https://asafra-church-portal.web.app` only 301-redirects to the new domain (target `legacy-redirect`). Default site ids can't be renamed — ADR-018. |
| Web app id | `1:724175543696:web:8c75dcd193c3dc5106a715` |
| Android app id | `1:724175543696:android:93a4afeb7a9c7d9806a715`, package `com.asafrachurch.church_portal` |
| iOS | **Not registered**: `DefaultFirebaseOptions.ios` has `PLACEHOLDER_IOS_API_KEY` / `PLACEHOLDER_IOS_APP_ID`; bundle id `com.asafrachurch.churchPortal`. `currentPlatformOrNull` returns null → iOS runs on the seed. |

`lib/firebase_options.dart` notes: the Android options reuse the browser API key; if Android requests are rejected,
replace it with `current_key` from `google-services.json`. `flutterfire configure --project=asafra-church-portal`
regenerates the whole file (keep the `currentPlatformOrNull`/`isConfigured` helpers when you do).

## Authentication

- **Email/password** provider only; **admins only** (no public sign-up anywhere in the app).
- Accounts are created in Firebase console → Authentication → Users, or by the Seed workflow's `admin_email` input
  (`admin.auth().createUser`) which then emails a set-password (reset) link.
- Being signed in is not enough: admin rights = existence of `admins/{uid}` (see rules). Roles `owner`/`editor`.
- `/admin` has "Forgot password?" → `AdminRepository.sendPasswordReset` (answers the same whether the account exists).

## Firestore security rules (`firestore.rules`) — rule by rule

Helpers:
- `signedIn()` — `request.auth != null`.
- `isAdmin()` — signed in **and** `admins/{request.auth.uid}` exists.
- `isOwner()` — `isAdmin()` and that doc's `role == 'owner'` (missing role ≠ owner).
- Field validators: `optString(d,k,max)` (absent/null/string ≤ max), `str(d,k,max)` (cheaper: absent = '', null
  rejected — used on the big settings docs to stay under the 1000-expression budget), `reqString`, `optBool`,
  `optInt(lo,hi)`, `optNumber(lo,hi)`, `optTimestamp`, `optTime` (absent/null/''/`HH:mm`), `optList(max)`,
  `optIn(values)`.
- `stampOk(d)` — `updatedAt` absent, `== request.time`, or unchanged; `updatedBy` absent, equal to the caller's token
  email (or uid), or unchanged. Prevents forging edit history.
- `changedKeys(d)` (PR #11) — create: every key; update: `diff().affectedKeys()`. `validContent` computes it once and
  passes it down; **only changed keys are validated** (a stored value was validated when it was written).
- `common(d, changed)` — ≤ 80 keys, `visible`/`sample` bool, `order` int ±100000, `image` null/absent or `validImage`,
  `stampOk` (each only when changed). Only collections whose allow-list contains `'image'` (alerts, seasons and the 7
  detail collections) can store one.
- `validImage(i)` — keys ⊆ `source,url,mediaId,alt,w,h`; `source` ∈ url/inline/storage; inline → `mediaId`
  `^[A-Za-z0-9_-]{1,128}$`, otherwise `url` ≤ 500 matching `https://[^/\s]+[.][^/\s]+([/?#]\S*)?`; `alt` ≤ 300;
  `w`/`h` absent/null or int 1–10000. Since PR #11 checked on **one joined string** (`source␟url␟mediaId␟alt␟w␟h`,
  U+001F separator, `string()` for w/h after a string `w`/`h` such as `'800'` is rejected) with two regexes — same
  rules, a fraction of the expressions.
- PR #11 detail helpers: `detailKeys()`; `validDetailCommon(d, changed)` → `validGallery` (≤ 8 × `galleryImage` =
  `validImage` without the w/h range), `validExtraFields` (≤ 15 rows: the 4 keys read directly, lengths + a title via
  one regex; unknown extra keys in a row are not rejected), `validDetailText` (4 toggles ∈ {true,false}; youtube /
  instagram http(s) URLs, labels ≤ 80, notes ≤ 500, details ≤ 10,000 on one joined string); `validDetailContacts`
  (`contactPhone`/`whatsapp` ≤ 20, `whatsappUrl`/`facebookUrl`/`externalUrl` `''`/null/http(s) ≤ 500; it also checks
  the meetings' Facebook/WhatsApp URLs, the activities' `contactPhone` and the clinics' `whatsapp` whenever a write
  sets them); `ownFieldsUnchanged(changed)` skips a collection's own-field checks when an update touches only
  detail / meta keys; `ownMeeting/ownActivity/ownClinic/ownFacility/ownPriest/ownMilestone/ownSaint` check the
  collection's own fields on one joined string. Optional text fields are read inline as
  `(d.get(k, null) == null ? '' : d.k)`: absent/null is accepted, a non-string (`phone: 123`, `nameEn: true`) makes
  the string `+` fail → denied (`string()` would have turned it into text; Codex P2 on PR #11). A helper function
  for this cost ~2× the expressions, hence inline. `weekday`/`year` are read with `string()` after a string value
  (`'5'`) is rejected; priest `rank`/`status` use `in [null, …]` (the text `'null'` is rejected); required fields
  must be non-empty strings.
- `keysAllowed(allowed)` — **create**: all keys ∈ allowed; **update**: only *changed* keys ∈ allowed
  (`diff().affectedKeys()`), so legacy fields already in a doc never block an edit.
- **Rules 1,000-Expression Budget (ADR-057, ADR-059):** On large settings documents (`settings/features`), evaluating 50+
  keys in an allow-list or nested objects like 9 page headers hits Firestore's 1,000-expression ceiling. Rules solve
  this via **Fast-path branching**: `changed.hasOnly(legacyFeatureKeys()) ? validLegacyFeatures(...) : (validInstallPush(...) && validLegacyFeatures(...))`.
  Writes touching only legacy keys never allocate or evaluate the new schemas. In addition, single-key checks use the
  primitive `'key' in set` operator (1 expression) instead of `set.hasAny(['key'])`. In `validInstallPush`, `validInstallSettings` and `validPushSettings` are gated behind `!changed.hasAny(...)` checks to short-circuit, and `validPushCore` uses single `.join('\u001f').matches(...)` regexes to check sets of types in 2 expressions instead of 36 expressions.

Match blocks:

| Path | read | create / update | delete |
|---|---|---|---|
| `/{col}/{docId}` for `alerts, seasons, liturgies, meetings, activities, clinics, facilities, priests, milestones, saints, categories, entries, pages` | **public** | `isAdmin() && validContent(col, data)` → `common` + per-collection `validAlert/validSeason/validLiturgy/validMeeting/validActivity/validClinic/validFacility/validPriest/validMilestone/validSaint/validCategory/validEntry/validPage` (allow-list + types/sizes; see `04-data-model.md`). PR #18 (ADR-027): `slugOk` (`[a-z0-9]+(-[a-z0-9]+)*` ≤ 60), category icon list, entry `categoryId` id-shaped (existence not required), page header checked on create / header change, `validBlocks` (≤ 20, unrolled) → `validPageBlock` = **one regex on one string** per block | `isAdmin()` |
| `/settings/{docId}` | **public** (except `docId == 'notifications'` which is `isAdmin()` only) | `isAdmin()` and (`church` → `validChurch`, `features` → `validFeatures`, `contact` → `validContactSettings`, `assistant` → `validAssistant`, `notifications` → `validNotifications`: allows schedule ≤ 20 rows, forbids client writes to status/health/reminders, allows owner to clear sentLog); any other doc id denied | **never** |
| `/media/{mediaId}` | **get: public** (by id); **list: `isAdmin()` only** (PR 1, SEC-02) | `isAdmin() && validMedia(data)`: keys ⊆ `dataBase64, contentType, w, h, bytes, createdAt, createdBy, refs`; required `dataBase64` (4–950,000 chars), `contentType` ∈ jpeg/webp/png, `createdAt` (== `request.time`, or unchanged), `createdBy` (token email/uid, or unchanged); `bytes` ≤ 700,000; `w/h` 1–10000; `refs` list ≤ 20 | `isAdmin()` |
| `/admins/{uid}` | own doc, or any doc if `isOwner()` | `isOwner()` **and** `uid != caller` (cannot change yourself → an owner always remains); keys ⊆ `email, role, updatedAt, updatedBy`; email required ≤254; role ∈ owner/editor; `stampOk` (PR 1, SEC-03) | `isOwner() && uid != caller` |
| `/meta/contact_rate` | never | keys ⊆ `lastAt, lastMsgId`; `lastAt == request.time`; `lastMsgId` string 10–64 alphanumerics; `!exists(contact_messages/lastMsgId)` **and** `existsAfter(contact_messages/lastMsgId)` (so it is only writable in the same batch as a NEW message — SEC-01); and (new doc or `request.time > lastAt + 10 s`) | never |
| `/contact_messages/{id}` | `isAdmin()` | **create (public, no auth)**: `validContactMessage` **and** `getAfter(meta/contact_rate).lastAt == request.time` **and** `getAfter(meta/contact_rate).lastMsgId == id` (same batch). **update**: `isAdmin()`, only `status/adminNotes/updatedAt/updatedBy` change, status ∈ new/handled/contacted/confirmed/declined, `adminNotes` string ≤ 2000, `stampOk`. PR #18 (ADR-028): `validContactMessage` reads the category with `contactCat(id)` (id must pass `contactIdOk` since PR #19) (`settings/contact` if it exists — one `exists` + one `get` — else `defaultContactCats()`); a message with `category` needs that slot switched on and a matching `kind`; bookings need a phone + `preferredDate` (YYYY-MM-DD) and an optional `bookingType` key; `anonymous: true` only for an anon-allowed complaint / suggestion slot and then **no** `name/phone/email/bookingType/preferredDate` key; messages without `category` keep the original checks (`validIdentifiedMessage`) | `isAdmin()` |

Anything not matched (e.g. a new collection) is **denied** by default — new collections need a rules change.

Notable details:
- `validSeason` requires `key` in the 6 season keys, `replacesRegular` optional bool (PR 1); `validLiturgy` requires
  the `start` key and `seasonKey` ∈ keys.
- Links (PR 1, SEC-04): `optHttpUrl` (`''` or `^[Hh][Tt][Tt][Pp][Ss]?://[^/ ]+[.][^/ ]+([/?#][^ ]*)?$` — scheme
  case-insensitive like the admin form) on `activities.link`,
  `meetings.facebookUrl/whatsappUrl` and `settings/church` `facebook/youtube/instagram/whatsappChannel`;
  `optUrlOrPath` (also an in-app path `/…`) on `alerts.link`. Rejects `javascript:`, `data:`, `//host`, etc.
  `mapsUrl`/`heroImageUrl` keep length-only checks.
- `validClinic`: `days` list ≤ 7 and ⊆ [1..7].
- `validPriest`: `rank` ∈ hegumen/priest, `status` ∈ serving/departed, dates ≤ 10 chars.
- **Image display styles (PR #15, ADR-023):** `common()` accepts `imageStyle` only as absent/`null`/`avatar`/`card`/
  `banner` when it changes; it is on the allow-list of the 9 image collections (and `ownFieldsUnchanged`), never on
  `liturgies`. `validFeatures` accepts `imageStyles` as a map whose keys are the 9 collections and values the 3 styles.
  Emulator tests: "ADR-023" group in `tool/rules_test/rules.test.mjs`.
- **Verse of the day (PR #16, ADR-024):** `validFeatures` allows `dailyVerse`; `validDailyVerse` (only when it changes):
  map with keys ⊆ mode/textAr/refAr, `mode` ∈ daily/fixed, strings with text ≤500 and ref ≤60
  (joined + regex). Emulator tests: "Verse of the day" group in `tool/rules_test/rules.test.mjs`.
- **Occasion themes & hero videos (PR #17, ADR-025/026):** `validFeatures` allows `occasions`, `themeColors`,
  `heroVideos`; `theme` ∈ `themeKeys()` + legacy `burgundy`. `validOccasions`: keys ⊆ auto/easter/resurrectionDays/
  schedule, bools, int 1–50, schedule keys ⊆ r1…r12, each changed slot a string matching
  `preset|YYYY-MM-DD|YYYY-MM-DD` (2000–2099) with start ≤ end (`split`). `validThemeColors`: keys ⊆ presets, each
  changed preset a string of ten `|`-separated optional `#RRGGBB`. `validHeroVideos`: keys ⊆ items/active/byTheme,
  slots v1…v12, `active` ∈ '' + slots, `byTheme` keys ⊆ presets and values ⊆ slots; each changed item exactly
  `{name, url}` with name 1–80 chars and url `https://www.youtube.com/watch?v=<id>` or `https://youtu.be/<id>`
  (`[A-Za-z0-9_-]{11}`, nothing after). Strings (not maps) and caller-computed changed-key sets keep a full first save
  of 12 ranges, 11 palettes or 12 videos under the 1,000-expression cap (maps of maps did not). Contrast is not
  checkable in rules: the app corrects on save and again on render. Emulator groups "ADR-025" and "ADR-026". **ADR-036 (PR #25):** the app no longer writes `heroVideos`; `validHeroVideos`
  and the allowed key stay (marked LEGACY in `firestore.rules`) so documents that already store it keep saving.
- **Today layer (PR #31, ADR-039 / ADR-040):** `validFeatures` allows `copticStrip` (`all`/`home`/`off`),
  `dayStartMode` (`fixed`/`sunset`), `dayStartsAt` ('' or HH:mm), `topEvent` / `commemoration` (bools) — checked
  together only when one of them changes — and `liveEnabled` (bool), `liveUrl` ('' or http(s) URL with a host, ≤ 500),
  `liveLabelAr` / `liveLabelEn` (≤ 120), `liveEndsAt` (timestamp / null). `dayEvents`: `validDayEvents` = list ≤ 20,
  each item checked by `validDayEvent`: ONE string of 13 U+001F-joined fields (date YYYY-MM-DD with month 01–12 and
  day 01–31, optional endDate of the same form (an endDate before date is refused by the admin form and read as one day by
  the client; a per-event `split` compare exceeded the 1,000-expression cap at 20 events), optional HH:mm
  start / end, titleAr 1–300, titleEn / speaker / topic ≤ 300, notes ≤ 500, link '' / in-app path / http(s) URL),
  unrolled per index like `blockItems` so 20 events stay under the 1,000-expression cap. Emulator group
  "ADR-039 / ADR-040". No new document or collection.
- **Programme details (PR #32, ADR-041):** `validSeason`, `validLiturgy`, `validMeeting` allow `programKeys()`
  (speaker / topic / choir ar+en, venue, audience, attachmentUrl, attachmentLabelAr/En); `validProgram(d, changed)`
  runs only when one changes and checks all eleven on one U+001F-joined string (texts 200 / 300 / 200 / 80, keys
  `[a-z0-9_-]{0,30}`, attachmentUrl '' or https with a host, no whitespace, at most 500 characters). `ownFieldsUnchanged` accepts programme-only meeting edits.
  `validFeatures` allows `venues` / `audiences`: `validProgramOptions` = list ≤ 12 whose `join('\u001e')` matches one
  regex of `key␟labelAr␟labelEn` rows. Emulator group "ADR-041".
- **Season presets (PR #33, ADR-042):** `validFeatures` allows `seasonVerses` (`validSeasonVerses`: ≤ 40 rows, one
  `join('\u001e')` + regex of `seasonKey␟textAr␟refAr`), `seasonPreset` (`validSeasonPreset`: allowed keys, season id
  pattern, season key list, timestamps, ≤ 7 known options, `previous` keys typed, its four strings checked as one
  joined string; null clears it) and `weddingBookingOff` (bool). `validAssistant` allows `perDaySeason` 1–100. The
  apply / restore is one client batch (`AdminRepository.saveDocs`) of `settings/features` + `seasons/{id}`, each doc
  checked by its own rule. Emulator group "ADR-042".
- `validFeatures`: key allow-list via `keysAllowed` (create: `keys().hasOnly`; update: only the **changed** keys must
  be allowed, so an untouched legacy key no longer blocks a merge save — same as `settings/church`, PR #10), `sections` keys ⊆ the 19 section keys (PR #16 added `dailyVerse`, PR #18 `customSections` / `customPages`)
  (incl. `media`)
  and values bool, `homeOrder`/`homeHidden` ⊆ the 7 block keys (≤ 7), `bannerLink` via `optUrlOrPath(d, 'bannerLink',
  500)` (empty, in-app path or http(s) URL with a case-insensitive scheme — same as alert links, PR #10), `theme` ∈ 5
  presets; PR #11: `footer` (`validFooter`: keys ⊆ 5, three bools, notes ≤ 500) and `pageHeaders` (`validPageHeaders`:
  pages ⊆ the 8 `CustomizablePages`, each changed entry exactly the 6 keys with 200/300/1500 caps). Every group is
  checked only when changed (the editor saves the whole doc).
- `validChurch`: phones/altars lists ≤ 20; `nameAr` required; `coordinatesApproximate` optional bool (PR 1).
- **Editors and owners have the same content/settings/inbox rights**; only `admins/*` management is owner-only.
- Tests: `tool/rules_test/rules.test.mjs` (Node test runner + `@firebase/rules-unit-testing` in the Firestore
  emulator, project `demo-church-portal`): public read/no write, non-admin denied, contact create + throttle,
  every seed doc valid, clinic create/hide/reorder/delete, unknown keys/bad types/bad times rejected, stamps,
  legacy fields, church coordinates, feature toggles shapes, inbox, owner/editor admin management, **optional
  images** (valid url/inline/null images, malformed maps, image on a collection without it, `media/` public read,
  admin-only writes, type/size/stamp checks, the 950,000-char cap), and PR 1's **SEC-01–SEC-04** (standalone
  `contact_rate` pings and mismatched `lastMsgId` rejected, 10 s throttle, `media` list admin-only, admin stamps,
  `Season.replacesRegular`, `coordinatesApproximate`, safe links incl. upper-case schemes, replaying an existing message, a 5 s resend),
  and PR #10's upper-case `HTTPS://` `bannerLink`, untouched legacy key on a `settings/features` merge, and stamped
  `setAdmin` writes; PR #11's detail pages (worst-case create + 8-photo gallery + 15 rows + list-with-text saves on all
  7 collections, optional/cleared values, cover image on meetings/clinics/facilities, gallery/extraFields shapes,
  `javascript:` links, bools/lengths, no duplicate inputs, no detail keys on liturgies/seasons/alerts, 80-key cap,
  stored lists re-checked only when changed) and `pageHeaders`/`footer`. PR #12 adds "admin editor save paths": the
  real write sequence of `DocEditor` (max-size create, then the 8-photo gallery, then 15 rows, on all 7
  collections; an every-field edit; both lists in one write denied) and of `FeaturesScreen` (whole document, then
  `pageHeaders` alone; the combined first save is denied; a reset page is removed). 54 tests.
- **Expression budget (measured in PR #11):** Firestore evaluates at most **1,000 expressions per request**, shared by
  every `match` block the path hits (that is why `validContent` keeps its `col in [...]` early exit: without it
  `settings/church` writes ran out). Literals, field reads and `+` all count; an unrolled list item costs ~10. The
  PR #11 plan's per-field checks (`optString` per key, `validImage` per gallery item, `str` per page-header field)
  exceeded it with **2** gallery images or **4** page headers, so PR #11 validates only changed keys and checks text
  on joined strings. Measured headroom (emulator, docId-length pad; 1 unit ≈ 8.5 expressions): create of a fully
  filled doc 7–17 units (clinics lowest; 18–28 before the PR #11 type fix); update writing the full 8-photo gallery
  19–23; 15 full `extraFields` rows 17–22; a list plus detail text in one save 4–10; an ordinary edit 56–61; **both lists at max in one write: over the cap** (denied, fail-closed) — PR #12
  saves each list in its own update. **`settings/features`:** the whole document plus all 8 changed page headers in
  one write is also over the cap, so since PR #12 `FeaturesScreen` writes everything else first and `pageHeaders`
  on its own, only when it changed (`featuresSaveWrites`). Adding checks: measure first; keep per-item work to one
  regex.
- **Merge writes (PR #12):** `AdminRepository.save` (existing docs) and `saveDoc` use
  `SetOptions(mergeFields: <written keys>)`: untouched fields stay (legacy keys never block an edit), but a written
  map field is **replaced**, not deep-merged — a page header the admin resets disappears from `pageHeaders`, and a
  cover image switched from inline to a link loses its old `mediaId`/`w`/`h`.
- **Web push rules (ADR-060):**
  - `push_queue/{id}`: create-only, read/update/delete denied; validates payload (`token`, `want`, `rem`, `drop`, `retries == 0`, `createdAt == request.time`) and binds `meta/push_rate` in the same batch.
  - `meta/push_rate`: create/update throttle (3s spacing, integer UTC day, count <= 1000). Evaluates all scalar checks before cross-document existence checks. Read/delete denied to all clients (including admins).
  - `meta/push_topics` and `meta/push_plan`: read-only for `isAdmin()`, client write denied.

## Cloud Storage (not used — Spark)

- `storage.rules` in the repo root is a **draft, not deployed** (`firebase.json` has no `storage` entry): public read
  of `media/*`, admin-only writes (cross-service `firestore.exists(admins/uid)`), ≤ 700 KB, jpeg/webp/png
  (`^image/(jpeg|webp|png)([;].*)?$`, so parameterised headers like `image/jpeg; charset=utf-8` pass — PR 1;
  guarded by `request.resource.contentType is string` before `.matches`, PR #10).
- The app's `StorageMediaRepository` (`lib/data/media_repository.dart`) is a stub selected by
  `--dart-define=MEDIA_BACKEND=storage`; switch steps are in ADR-017 (`10-decisions-and-history.md`).
- Spark quota note: each inline image costs **one Firestore document read** per visitor session (cached in memory and
  by Firestore persistence), counted in the 50K reads/day. Keep images optional and few; the admin can switch them all
  off (section `media`). Gallery photos (PR #13) cost those reads only when a visitor opens that item's detail page
  (the page reuses the list stream: no extra read for the item itself). PR #13 changes no rules.

## Indexes

`firestore.indexes.json`: `{"indexes": [], "fieldOverrides": []}` — no composite queries (see `04-data-model.md`).
Deployed with the rules on every push to `main`.

## Hosting (`firebase.json`, `.firebaserc`)

> **Headers & Sentry (PR #24):** the app target sends no `Content-Security-Policy` (headers: Cache-Control,
> X-Content-Type-Options, Referrer-Policy, X-Frame-Options, HSTS, Permissions-Policy), so the Sentry JS bundle from
> `browser.sentry-cdn.com` and event posts to `*.ingest.de.sentry.io` need no change. **If a CSP is ever added**, it
> must allow `script-src https://browser.sentry-cdn.com` and `connect-src https://*.ingest.de.sentry.io` (ADR-034).

Two targets (array in `firebase.json`, mapped in `.firebaserc` → `targets.asafra-church-portal.hosting`):

| Target | Site | Serves |
|---|---|---|
| `app` | `maximos-domadios-church` (https://maximos-domadios-church.web.app) | The Flutter web app (settings below), live + PR previews |
| `legacy-redirect` | `asafra-church-portal` (old default site) | `redirects: [{regex: ^/(.*)$, destination: https://maximos-domadios-church.web.app/:1, type: 301}]` — every path keeps its path; public dir `hosting/legacy_redirect/` (meta-refresh fallback page only). `/__/*` reserved URLs still work there. |

Site `maximos-domadios-church` was created 1 Nov 2026 with `firebase hosting:sites:create` run by the deploy service
account from a throw-away workflow (SA has Hosting Admin). Auth **authorized domains** include
`maximos-domadios-church.web.app` and `.firebaseapp.com` (added in the console, 1 Nov 2026); both browser API keys
have no application (referrer) restriction, so no key change was needed. `authDomain` in `firebase_options.dart`
stays `asafra-church-portal.firebaseapp.com` (admin sign-in is email/password, no redirect/popup flow).

App target settings:

- `public: build/web` (output of `flutter build web --release`); ignores `firebase.json`, dotfiles, `node_modules`.
- `cleanUrls: true`, `trailingSlash: false`, **rewrite `"regex": "^/[^.]*$"` → `/index.html`** (SPA + path URL
  strategy; ADR-037 — was `**`) — every extension-less path, so the PR #13 item detail URLs (`/clinics/<id>`,
  `/about/priests/<id>`…), `/section/<slug>`, `/page/<slug>`, `/admin`, `/ask` load with HTTP 200 and the app decides
  what they show, while a missing **file** (`/.well-known/ard.json`, `*.map`, `wp-login.php` probes) is a real 404
  instead of `index.html`. A second rewrite (`^/(section|page|<the 7 detail base paths>)/[^/]+$`) keeps
  `/section/<slug>`, `/page/<slug>` and item pages working when the slug / id contains a dot (Codex review). `web/llms.txt` (ADR-037) describes the site for AI
  agents (H1 + page links, all in the sitemap).
- Headers on `**` also include `Cross-Origin-Opener-Policy: same-origin-allow-popups` (ADR-037; keeps Google sign-in
  popups working). The hero `mp4` clips keep Hosting's default cache (fixed, non-fingerprinted paths — CodeRabbit).
- SEO in `web/index.html` (PR 3 of the review plan): a **static** `<link rel="canonical"
  href="https://maximos-domadios-church.web.app/">` in the shell. Since PR #10 (amending ADR-019) Flutter rewrites it
  per route with `setDocumentRouteMeta` (`lib/core/document_lang*.dart`): indexable routes get
  `kCanonicalOrigin + path`; `/admin`, the 404 page and switched-off sections (`FeatureGate`, `AssistantGate` for
  `/ask`) drop the canonical link and add `<meta name="robots" content="noindex">` instead (never both); item
  detail pages (PR #13) are indexable only while the item's page is available (`ItemDetailPage`). Crawlers
  that do not run JS still see `/` as the canonical. **`sitemap.xml` is generated at deploy (PR #30, ADR-038):**
  `deploy.yml` → `build` runs `tool/build_sitemap.sh` after `flutter build web` with the deploy key
  (`firebase-credentials`, `continue-on-error`): `tool/export_public_content.js` reads `settings/features` + the 7
  detail collections + `categories` + `pages` with **`get()` only** (never writes), `dart run tool/gen_sitemap.dart`
  applies `lib/domain/sitemap.dart` (fixed pages by `routeEnabled`; public `/section/<slug>` / `/page/<slug>` while
  `customSections` / `customPages` are on — nav-hidden pages included, as the app indexes them; item pages that open),
  the XML is validated and written to `build/web/sitemap.xml`; the key is deleted at once. Any failure → `::warning::`
  and the static `web/sitemap.xml` (fixed pages the seed keeps on; `/clinics` omitted while seed clinics are off)
  ships instead. The sitemap reflects content at deploy time. `web/robots.txt` points to `/sitemap.xml`. Plus a `<script type="application/ld+json">` **`Church`** block with only
  verified facts mirrored from `settings/church` / `docs/CONTENT_SOURCES.md` and the display title: Arabic name
  (`nameAr`), `alternateName` = the English display title "St. Maximus & Domadius and St. Moses the Black Church"
  (`appName` in `l10n.dart`, ADR-018) and the full `nameEn`, `PostalAddress` (آخر شارع 45، العصافرة قبلي، قطاع المنتزه، الإسكندرية, EG), `GeoCoordinates`
  31.260138, 30.01129, `telephone` +2035368888, `sameAs` Facebook/YouTube/Instagram/WhatsApp channel.
  `test/phase3_test.dart` parses it and compares `name`, both `alternateName`s (`appName` / `nameEn`), the
  `streetAddress` prefix of `addressAr`, `geo` and `sameAs` with the seed / l10n; `telephone`, the address type,
  `addressCountry` and `url` are hard-coded in the test; `image` is not checked. If the church's facts change, update
  the seed, `web/index.html` and the hard-coded test values together.
- Headers: `**` → `Cache-Control: no-cache` (Flutter bundles are not content-hashed, so HTML must revalidate),
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options: SAMEORIGIN`,
  `Strict-Transport-Security: max-age=31536000; includeSubDomains`, `Permissions-Policy: camera=(), microphone=(),
  geolocation=()` (PR 1, SEC-05);
  images/fonts and `canvaskit/**` → `public, max-age=604800` (7 days).
  `**/*.@(js|mjs|wasm)` → 30 days + `stale-while-revalidate` (this also covers canvaskit `.js` / `.wasm`, which stay cached).
  **ADR-069:** `main.dart.js`, `main.dart.mjs`, `main.dart.wasm`, and `main.dart.js_*.part.js` are **not**
  content-hashed. A later header sets them to `Cache-Control: no-cache` (revalidate with ETag). Without it,
  a browser keeps an old `main.dart.js` beside a new part file and `/ask` and `/readings` throw
  `DeferredLoadException` (`part main.dart.js_N.part.js not loaded`). `DeferredLoader` reloads the tab once
  per session when that exception fires, then shows the existing retry card.
  **Icon fonts are fingerprinted (PR #23):** `flutter build web` tree-shakes `MaterialIcons-Regular.otf` /
  `CupertinoIcons.ttf` to the icons in use but keeps one file name, so the 7-day font cache kept an old subset and
  icons added later (the PR #18 admin menu entries) drew as blank space. `tool/fingerprint_icon_fonts.py` (run by
  `ci.yml` and `deploy.yml` right after the build) renames them `<name>.<sha256[:12]>.<ext>` and rewrites
  `assets/FontManifest.json` (no-cache), so a new subset is a new URL. Manual deploys must run it too.
- **Live** deploy: push to `main` → `deploy.yml` job `deploy-live` (`firebase deploy --only hosting:app,hosting:legacy-redirect`),
  environment `production` (URL the new domain).
- **Previews**: every same-repo PR → channel **`pr-<number>`** of the `app` target only (`--only app`), `--expires 7d`; the URL is posted/updated in one PR
  comment (marker `<!-- firebase-hosting-preview -->`). Previews are built **without** the reCAPTCHA key, so App Check
  is off there and the assistant is hidden; everything else works against the production Firestore (read-only for the
  public, real writes from the contact form and /admin!).
- Rollback: Firebase console → Hosting → release history → roll back.

## App Check (`lib/data/app_check_providers.dart` `selectAppCheckPlan`, activated lazily by `ensureAppCheckActivated()` in `firebase_bootstrap.dart`)

ADR-029 (PR #19). **Since ADR-037 (PR #29) App Check is not activated at start-up**: `ensureAppCheckActivated()`
(one shared Future) runs on the assistant's first `warmUp()` / `generate()`, so public pages never load reCAPTCHA
Enterprise. `FirebaseStatus.appCheckActive` = "App Check is configured for this build" (`plan.activate`), which
still gates the assistant; a later activation failure shows the assistant's normal error instead of hiding it.
**ADR-046:** the FlutterFire web plugin saves the provider in `localStorage` (`FlutterFire-[DEFAULT]-recaptchaType` /
`…-recaptchaSiteKey`) and would re-activate App Check at `Firebase.initializeApp` on every later load; the
`boot-prefs` script in `web/index.html` deletes those keys (local + session storage) before Flutter loads, so only /ask
loads reCAPTCHA. Firebase AI Logic **requires** App Check enforcement since 2 Nov 2026; it is **Enforced** in the
console.

| Build | Provider |
|---|---|
| Web release with key | `ReCaptchaEnterpriseProvider(AppConfig.recaptchaSiteKey)` — the key is a **reCAPTCHA Enterprise** key ("church-portal-web", site key `6LdJhw4uAAAAAI7yuMKtTRMVc_r9LdX1qPBqHMW3`, a public value); a `ReCaptchaV3Provider` would be rejected |
| Web release without key (`PLACEHOLDER…`, empty — PR previews) | **not configured** → `appCheckActive = false` → assistant hidden |
| Debug builds or `--dart-define=APPCHECK_DEBUG=true` | `WebDebugProvider` / `AndroidDebugProvider` / `AppleDebugProvider` (token from `APPCHECK_DEBUG_TOKEN` or SDK-generated and printed in console/logcat — register it under App Check → Manage debug tokens) |
| Android release | `AndroidPlayIntegrityProvider` is still what `selectAppCheckPlan` picks. The sideloaded assistant does **not** use it: questions go to the Worker (`WorkerAssistantModel`). Play Integrity cannot attest a GitHub-sideloaded APK, and App Check stays **not** enforced on Firestore. |
| iOS release | `AppleAppAttestWithDeviceCheckFallbackProvider` |

- **Site key**: `AppConfig.recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue:
  'PLACEHOLDER_RECAPTCHA_SITE_KEY')`. CI passes the **repository variable** `RECAPTCHA_SITE_KEY` (Settings →
  Variables, not a secret; **set** Nov 2026) only for push builds (`deploy.yml`, which prints a `::notice::` when it
  builds with it and a `::warning::` on a push build without it). The key is registered for
  `maximos-domadios-church.web.app`, `maximos-domadios-church.firebaseapp.com`, `localhost`; the web app is
  registered in App Check with the reCAPTCHA Enterprise provider.
- **Android assistant**: the chat is in the app (`AssistantPage`, same deferred chunk). A non-web build calls
  `POST /assistant` on the existing Worker `church-portal-push-sender` (`tool/assistant_worker.js`) instead of
  Firebase AI Logic, because a GitHub-sideloaded APK cannot get a Play Integrity token. Web is unchanged
  (reCAPTCHA Enterprise, App Check Enforced on AI Logic only). Do **not** enforce App Check on Firestore.
  Owner steps are in `11-open-tasks.md` (secret `GEMINI_API_KEY`, `npx wrangler deploy`, repo variable
  `ASSISTANT_WORKER_URL`). Nothing here needs Workers Paid, Blaze, or Cloud Functions.
- App Check is enforced for **Firebase AI Logic** only (the web assistant). Do **not** enforce it on Firestore.

## Firebase AI Logic — "Ask the church" assistant (ADR-014, ADR-029)

- **Backend (web):** Gemini Developer API (`FirebaseAI.googleAI()`), free tier on Spark. `FirebaseAssistantModel`
  (`lib/data/assistant_model.dart`) makes one stateless `generateContent` call per question: `systemInstruction`
  = the grounding prompt, contents = kept history + the question, `GenerationConfig(temperature: 0.2,
  maxOutputTokens: 1024)`, 45 s timeout. The SDK attaches the App Check token itself (`app.getService<FirebaseAppCheck>()`).
- **Backend (Android):** the same prompt, history, temperature and token cap, sent by `WorkerAssistantModel`
  (`lib/data/assistant_model_io.dart`) to the Worker, which calls
  `generativelanguage.googleapis.com` with secret `GEMINI_API_KEY` (header, never logged). The instruction is
  the one the app already built (`buildAssistantInstruction`); the Worker does not invent church facts.
  Chosen only when `dart.library.io` is available, so the web deferred chunk still loads `firebase_ai` and
  `main.dart.js` does not grow. `ASSISTANT_WORKER_URL` is a compile-time define (GitHub variable of the same
  name on the APK workflow).
- **Worker free-plan caps** (`tool/assistant_worker.js`, one `PUSH_KV` read + one write per accepted question):
  body ≤ 512 KiB; instruction ≤ 150,000 chars (the bundled seed prompt is already ~29,000 chars
  with 47 liturgies and no custom pages; live pages add up to 20 × 2,500). Prompt ≤ 1,200; history ≤ 20
  turns; each turn ≤ 8,000 chars (the Worker's own reply slice, so the next question can resend it).
  Header `x-church-app` must be
  `church-portal-android` and `x-church-device` a 32-hex device id. Per Cairo day: 400 questions globally,
  100 per device (the admin maximum — the app still enforces the real per-day number, default 3, first),
  40 per IP hash, and 20 per IP per minute. Workers Free is about 100,000 requests/day; KV free is about
  100,000 reads/day and **1,000 writes/day** shared with the readings/OAuth cache, so the global cap stays
  at 400. No Durable Objects and no WAF rate-limiting (both are paid). KV is eventually consistent; a rare
  double-count is acceptable. Gemini Developer API free tier; no Blaze.
- **Model:** default **`gemini-3.1-flash-lite`** (`AppConfig.geminiModel`, build override `GEMINI_MODEL`):
  the cheapest stable Flash-Lite on <https://firebase.google.com/docs/ai-logic/models> that needs no Blaze
  (checked 3 Nov 2026; `gemini-3.5-flash-lite` is the newer, pricier one). Gemma is **not** supported by the AI
  Logic cloud API (FAQ: only in some hybrid / on-device configurations). Admins can set `settings/assistant.model`
  (`gemini-[a-z0-9][a-z0-9.-]{0,52}`); 1.x / 2.x ids are ignored; a model the API rejects as unknown /
  unsupported (the error must name the model or "model" **and** say 404 / not found / unsupported / deprecated — an
  unrelated 404 is just an error) is replaced by the default for the rest of the visit.
- **Visible** only when `assistantVisibleProvider` is true: section `assistant` on **and** Firebase available **and**
  App Check active **and** `settings/church.assistantEnabled == true`.
- **Instruction** (`lib/domain/assistant_context.dart` `buildAssistantInstruction`):
  1. Church name (+ address when contact info is on).
  2. **Persona** — `settings/assistant.instructions` or `AssistantSettings.defaultInstructions` (tone, ≤ ~6 lines,
     bullets).
  3. **Scope (fixed)** — only this church, its services, this website **and the Coptic Orthodox faith** (PR #21: a
     fixed extra topic — saints, rites, sacraments, feasts, fasts, hymns, Bible, church calendar / history); allowed topics = admin list (one per
     line, bullets stripped) or `defaultTopics`; anything else (general knowledge, news, politics, other churches,
     jokes, stories, homework, maths, translation, coding…) → reply exactly `[[OUT_OF_SCOPE]]`; greetings are fine;
     requests to change / reveal / bypass the rules or role-play are out of scope.
  4. **Grounding (fixed, rewritten in PR #21 / ADR-030)** — (a) questions the data answers → direct, confident
     answer, **no** "unconfirmed / may change / call the church" disclaimers; `[UNCONFIRMED]` markers reach the model
     only when `settings/assistant.mentionUnconfirmed` is on, and then it may say so once, briefly, only for the item
     asked about (off: stripped + "never say information is unconfirmed"); (b) church / faith questions not in the
     data → **never** general knowledge: the model replies exactly `[[SOURCE_SEARCH]]` and the app shows admin
     `faithReplyAr/En` + a Google search restricted to `sourceDomains` (`site:st-takla.org <question>`) + `/contact`
     (ADR-031: Google Search grounding is not on the free tier for gemini-3.1-flash-lite); (c) never invent this church's times, dates, names,
     phones, prices, fees, amounts or links → "not listed" + point to `/contact` (when contactInfo or contactForm is
     on, else the office phone); unrelated topics still `[[OUT_OF_SCOPE]]`; **simple Markdown only** (bold, italic,
     `-` / `1.` lists, http(s) / tel / `/path` links); reply in the question's language; times like 06:30 AM, Africa/Cairo with today's Cairo date; no
     medical / legal / spiritual-direction advice; no personal data; topics with no section are "not offered";
     website paths may be suggested.
  5. Sections included **only if switched on** in `settings/features`: Contacts (contactInfo: address, directions,
     maps URL, phones; socials: WhatsApp, Facebook, YouTube, WhatsApp channel, Instagram); weekly liturgy schedule
     (undated only), special one-off services (every non-seasonal dated liturgy — even with a weekday set — while
     `isDatedLiturgyCurrent`), Holy seasons (active seasons only, `[REPLACES regular schedule]` / `[ADDITIVE …]`,
     `[ACTIVE NOW]`) (schedule); current announcements (alerts: `visibleAlerts`); clinics (active only, incl.
     WhatsApp); meetings (incl. notes); activities; public services (facilities); About the church (history: bishop
     + history summary, each language clipped to 700); serving priests and departed priests with repose date;
     patron saints; **Our story** (milestones, description clipped to 300). Item detail pages (`detailsEnabled`
     not `false`): detail text (300 per language), custom fields (titles 100 / values 300), contacts when
     `showContacts`, links when `showSocials` **and** the socials section is on. **PR #19:** **Contact form and
     bookings** (contactForm: every visible contact type with its behaviour — booking needs mobile + date, its
     occasions, "can be sent anonymously"); **custom sections** (customSections: each public category with its
     path `/section/<slug>`, at most 20 sections, intro clipped to 300, up to 30 visible items with description clipped to 300, phone
     and link); **custom pages** (customPages: at most 20 public pages, each with its path `/page/<slug>`, subtitle, headings,
     paragraphs clipped to 400, buttons / links, donation account / InstaPay / wallet; ≤ 2,500 chars per page — a
     block that does not fit is skipped and later shorter ones still go in).
     Never any image / gallery data. Every bilingual field goes through `_bi(ar, en)`.
  6. Items with `sample: true` are prefixed **`[UNCONFIRMED]`**; since PR #21 (ADR-030) the model is told to mention it
     (once, briefly, only when asked about that item) **only** when the admin switch `settings/assistant.mentionUnconfirmed`
     is on (default off) — otherwise it answers straight from the data with no disclaimer.
- **Conversation** (`AssistantConversation`, pure Dart): checks length (`maxChars`, default 500; the text field
  also caps it), per-rolling-minute (`perMinute`, default 4) and **per device per Africa/Cairo day** (`perDay`, default 3 — PR #21,
  ADR-031; `AssistantRateLimiter` + `AssistantUsageStore` in shared_preferences / localStorage; the legacy per-visit
  `perSession` is ignored) limits **before** anything is sent (blocked questions show `askTooLong` / `askSlowDown` /
  `askDayLimit`); a reply holding `[[SOURCE_SEARCH]]` becomes the faith reply (`faithReplyAr/En`) + a Google search
  restricted to `sourceDomains` (default `st-takla.org`, `sourceSearchUrl`) + `/contact`; prefixes
  `[Current Cairo time: YYYY-MM-DD HH:mm (Weekday)]`; a reply that contains `[[OUT_OF_SCOPE]]` anywhere
  becomes the admin refusal (`refusalAr` / `refusalEn`, else the built-in ones) in the question's language
  (Arabic **letters** → Arabic; Arabic-Indic digits / tatweel do not count) and is **not** kept in the history; answers are kept (max 20 contents = 10 turns);
  the history is cleared when the enabled sections, `assistantDetailSignature` or `assistantCustomSignature`
  (contact types, custom sections / items / pages grounding — Codex review on PR #19) or the allowed topics change. The model is injected
  through `assistantModelProvider` (declared in the deferred `assistant_page.dart`, so `firebase_ai` stays out of
  the main bundle); tests use a fake.
- Before the first question `_awaitContent()` waits (≤ 10 s) for settings, features, assistant settings, the content
  lists, and — while their section is on — milestones, contact settings, categories + entries, custom pages; the
  section flags are re-read after each round so a section switched on meanwhile is awaited too (CodeRabbit).
- **PR #20 (grounding fix):** the page **`ref.watch`es every grounding provider in `build`** (`_watchGrounding`:
  features, liturgies, seasons, clinics, meetings, activities, facilities, alerts, priests, saints; milestones /
  contact settings / categories + entries / custom pages while their section is on). **Riverpod 3 pauses a provider
  with no listener** (its stream subscription is paused in `onCancel`), so the PR #19 page — which only `ref.read`
  them — never got liturgies & co. on a direct visit to `/ask`: `_awaitContent` hit its 10 s timeout and the first
  prompt had empty sections (live: «مواعيد القداسات إيه؟» → "no mass schedule data"). Rule: **any content the
  instruction reads must be watched by the page**, never only read. Watching also preloads the data on page open.
- **PR #20 (first-call error):** `AssistantModel.warmUp()` mints the App Check token in `initState` (when
  `firebaseStatus.appCheckActive`; `FirebaseAppCheck.getToken`, 15 s, errors swallowed), and
  `AssistantConversation.ask` retries a failed or empty call **once** after `retryDelay` (700 ms) — still one
  question for the limits; quota / rate-limit / bad-request / safety errors are not retried
  (`isRetryableAssistantError`); the model-unavailable fallback is unchanged. The one-off "تعذّر الحصول على إجابة الآن" on
  the first question was most likely the first reCAPTCHA Enterprise token racing the call (no client logs to prove it).
- **Admin-editable** (`settings/assistant`, `/admin` → AI assistant): model, persona instructions, allowed topics,
  refusal (ar/en), welcome text (ar/en; else `askIntro`), `showSuggestions` (default **off**; when on only the admin's
  suggested questions ar/en, ≤ 3 lines — there are no built-in ones since PR #21), `sourceDomains`, `faithReplyAr/En`,
  `mentionUnconfirmed`, `maxChars`, `perMinute`, `perDay` (`perSession` is a legacy key the rules still accept). The switches stay the section `assistant` and
  `settings/church.assistantEnabled` (both shown on that screen).
- Kill switches (all platforms): section toggle `assistant`, `settings/church.assistantEnabled`, or App Check
  not configured for the build (since ADR-037 a later activation **failure** no longer hides it — the assistant shows
  its normal error). **Web release builds only:** a missing/placeholder reCAPTCHA key also hides it. Android/iOS
  release builds activate Play Integrity / App Attest without the key, so the assistant shows there when the
  other conditions hold. Android questions go to the Worker and do not need a Play Integrity token. Cost cap /
  quota for the web AI Logic path is a console task;
  on Spark the Developer API free tier is rate-limited, never billed.

## Sentry (external service, PR #24, ADR-034)

Not part of Firebase, but configured next to it. Facts below were given by the owner (3–4 Nov 2026) and live in the
Sentry UI, not in the repo:
- Org **`kerollos-0e`**, project **`church-portal`**, EU region (`*.ingest.de.sentry.io`; the public DSN is
  `AppConfig.sentryDefaultDsn`). Plan: **Education Sponsored Team** until **2027-11-03** (then it falls back to the
  free plan unless renewed — the app sends errors only, no tracing / replay, so it fits the free quota too).
- Alert e-mails go to the developer's own e-mail (the address of the Sentry account; change it in Sentry → User
  settings → Notifications); an **uptime monitor** watches the live
  site; **Seer / Autofix** is on (AI issue analysis inside Sentry — it reads the scrubbed events and stack traces only).
- Still open (see `11-open-tasks.md`): *Prevent Storing of IP Addresses* + server-side data scrubbers in the project
  settings; source maps / Android symbols need a Sentry auth token.
- In the app: switch `/admin` → Sections & home page → **Error reports** (`settings/features.errorReporting`) and
  the owner-only **Send test error** button. Everything else in `03-architecture.md` → *Error reporting*.

## Service account (CI/CD)

- GitHub secret **`FIREBASE_SERVICE_ACCOUNT_ASAFRA_CHURCH_PORTAL`** = full JSON key of a deploy service account
  (e.g. `github-deployer`). Used by `deploy.yml` (live, rules, preview) and `seed.yml` via the composite action
  `.github/actions/firebase-credentials`.
- Roles to grant (README §6): **Firebase Hosting Admin**, **Firebase Rules Admin**, **Cloud Datastore Index Admin**,
  **Service Account User**, **API Keys Viewer** (or simply *Firebase Admin*). The seed job additionally needs
  Firestore data write and Firebase Auth admin (for `--admin-email`) — *Firebase Admin* covers it.
- The account deliberately lacks `serviceusage.services.get`; the composite action **pre-seeds firebase-tools'
  `apiEnablementCache`** (`~/.config/configstore/firebase-tools.json`) for `firebasehosting`, `firestore`,
  `firebaserules`, `identitytoolkit` APIs instead of widening IAM (alternative: grant *Service Usage Consumer*).
- The action keeps only the **first JSON object** of the secret (stray characters after it produce a
  `::warning::Ignored N extra character(s)…` — re-save the secret cleanly; tracked in `11-open-tasks.md`), validates
  `type == service_account`, writes `$RUNNER_TEMP/sa.json` with mode 600, exports `GOOGLE_APPLICATION_CREDENTIALS`,
  never prints the key; every job deletes the file in an `if: always()` step.
- `.gitignore` blocks `*service-account*.json` / `*serviceAccount*.json`. Never commit keys.

## Local emulators

`firebase.json` has no `emulators` block; the rules tests start the Firestore emulator via
`firebase emulators:exec --only firestore --project demo-church-portal --config ../../firebase.json` (needs Java 11+;
CI uses Temurin 21). The devcontainer forwards 4000 (Emulator UI), 8085, 9099.
