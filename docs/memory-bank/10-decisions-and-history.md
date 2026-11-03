# 10 — Decisions (ADR-style) & history

Format: context → decision → consequences. Add a new ADR for every non-obvious choice; never rewrite old ones —
supersede them.

## ADR-001 — Public directory, not a church management system
- **Context:** the PRD's core insight — earlier efforts built heavy ERP/CSMS systems nobody needed.
- **Decision:** read-only public portal; only admins authenticate; no member data.
- **Consequences:** tiny data model, public-read rules, near-zero cost; any member/attendance feature is out of scope
  unless re-approved (privacy/PDPL).

## ADR-002 — Flutter (web + Android) + Firebase
- **Decision:** one Flutter codebase; Firebase Hosting, Firestore, Auth, App Check, AI Logic.
- **Consequences:** fast to build and host for free; trade-offs are web first-load size and weak SEO (canvas). Mitigated
  partly by `web/index.html` meta tags + splash; static HTML shell/JSON-LD not done (open task).

## ADR-003 — Arabic-first RTL with English toggle; shareable `?lang=en`
- **Decision:** default locale `ar`; English via toggle; `?lang=en` read at startup and kept in sync by the router
  redirect; `<html lang>` synced; no `dir="rtl"` in `index.html` (breaks the map iframe platform view).
- **Consequences:** language is not stored on the device (only in the URL).
  *Superseded for web language storage by ADR-019 (`localStorage`); still true for the native apps.*

## ADR-004 — All schedule logic in Africa/Cairo via the IANA database
- **Decision:** `CairoTime` (package `timezone`) for every "now"/weekday/date; seed instants generated with
  `ZoneInfo("Africa/Cairo")`.
- **Consequences:** visitors with phones on other zones see correct times; DST (Egypt EEST) handled; never use
  `DateTime.now().weekday` directly.

## ADR-005 — Pure-Dart domain layer
- **Decision:** `lib/domain/` has no Flutter/Firebase imports; all rules (next mass, seasons, alerts, clinics, phones,
  contact validation, toggles, assistant prompt) are unit-tested there.

## ADR-006 — Seasons replace regular services per occurrence window
- **Context:** naive "season active today ⇒ replace the whole day" broke days where a season starts mid-day.
- **Decision (PR #1 review):** a seasonal service counts only if it starts inside its season's `[startsAt, endsAt]`, and
  it replaces only regular services that start inside that window; replacement is decided on all seasonal services
  (Holy Week hours suspend weekday masses) before filtering by type.

## ADR-007 — Offline/unconfigured fallback to bundled seed
- **Decision:** `assets/seed/seed.json` == the Firestore seed; app never crashes when Firebase fails; if
  `settings/church` is missing the whole app uses the seed; per-stream fallback on errors; footer notice when on seed.
- **Consequences:** `gen_seed.py` is the single source of the seed; CI enforces the generated file is committed;
  `seed_firestore.js` writes `settings` last.

## ADR-008 — Seed safety: create-only by default, retired ids, known ids
- **Decision:** default seeding skips existing docs; `--force` overwrites but deletes retired ids only if not edited in
  /admin; `--fill-missing` adds absent top-level fields in a transaction; `--force` + `--fill-missing` refused;
  `known_seed_ids.json` (grow-only) + `retired` list asserted by `gen_seed.py` and tests.
- **Consequences:** admin edits are never clobbered accidentally; removing a seeded id requires retiring it.

## ADR-009 — No invented content; `sample` flag
- **Decision (PR #2):** replace sample data with verified data; anything unverified stays as clearly labelled
  placeholders (`sample: true`, badge, page notice, assistant `[UNCONFIRMED]`); sources in `docs/CONTENT_SOURCES.md`.

## ADR-010 — Contact form abuse control without auth
- **Decision:** client validation + honeypot + client limiter (60 s, 3/h) + **server global throttle** via
  `meta/contact_rate` written in the same batch (rules: `lastAt == request.time`, ≥ 20 s apart) + strict field
  validation; create-only for the public.
- **Consequences:** two visitors submitting within 20 s → the second is rejected (acceptable at parish scale).
- **Update (PR 1, SEC-01):** the throttle doc also stores `lastMsgId` = the id of the message created in the same
  batch; the rules require that message to be new (`!exists` before, `existsAfter`), so the throttle can no longer be
  pinged on its own to block the form. Cooldown lowered to **10 s**. A client timeout no longer clears the form or
  promises delivery (BUG-06).

## ADR-011 — Two admin roles; editors manage settings too
- **Context:** business case wanted settings, flags and message deletion owner-only.
- **Decision (PR #3):** `owner` manages admins (never themselves, so an owner always remains); `editor` can edit all
  content, `settings/church`, `settings/features` and the inbox. Missing role = editor.
- **Consequences:** simpler rules; trust editors more. Revisit if the church wants stricter separation (would need
  `isOwner()` on `settings/*` and message delete, plus UI gating).

## ADR-012 — Validated writes with key allow-lists that tolerate legacy fields
- **Decision:** per-collection allow-lists; creates use only allowed keys, updates may only *change* allowed keys
  (`diff().affectedKeys()`); admin edits write only changed fields (`changedFields`). `str()` helper on big settings docs
  to stay under the rules' 1000-expression budget.

## ADR-013 — Feature toggles in one streamed doc
- **Decision (PR #3):** `settings/features` holds section on/off, home layout, hero texts, banner, theme; missing key =
  on; a switched-off section disappears everywhere including the assistant prompt; routes show "not available";
  gated pages wait for the doc to avoid flashes.

## ADR-014 — Assistant gated by App Check and grounded on live content
- **Decision:** Gemini (`gemini-2.5-flash`, Developer API) via Firebase AI Logic; system prompt built from the live
  content of enabled sections; App Check enforced, so the assistant is hidden when App Check is not active (no
  reCAPTCHA key, preview channels).
- **Consequences:** the assistant is currently hidden on the live site until `RECAPTCHA_SITE_KEY` is set.
- **Amended by ADR-029 (PR #19):** reCAPTCHA **Enterprise** provider (key set Nov 2026), default model
  `gemini-3.1-flash-lite` (admin-editable), fixed church-only scope.

## ADR-015 — Deploy with firebase-tools CLI and a tolerant credentials action
- **Context:** `FirebaseExtended/action-hosting-deploy` and a secret with stray trailing characters broke PR deploys;
  the deploy SA lacks `serviceusage.services.get`.
- **Decision (PR #1):** composite action `.github/actions/firebase-credentials` (first JSON object only, 0600 file,
  primes the API-enablement cache); `npx firebase-tools@latest` for live/rules/preview; preview builds without the
  reCAPTCHA key.

## ADR-016 — Path URL strategy + Hosting SPA rewrite
- **Decision:** `usePathUrlStrategy()` for clean URLs; Hosting rewrites `**` → `/index.html`; `no-cache` on HTML/JS
  because Flutter bundles are not content-hashed.

## ADR-017 — Optional images stored inline in Firestore (Spark), Cloud Storage later
- **Context (PR #5):** the church wanted photos on priests, saints, milestones, activities, alerts and seasons, but
  **as an optional extra, not a core feature**. The project is on **Spark**; Cloud Storage for Firebase needs
  **Blaze** (Spark projects cannot provision or access a bucket —
  <https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024>).
- **Decision:** an optional `image` map on each supported content doc (`source: url | inline | storage`). Admins
  either paste an https URL, or upload from the device: the client resizes (≤ 800 px) and compresses (~250 KB target,
  700 KB hard cap) and stores base64 in a **separate** `media/{id}` doc so list queries stay light and each card
  fetches its own bytes lazily (memory-cached). Access goes through `MediaRepository`
  (`FirestoreMediaRepository` now; `StorageMediaRepository` stub chosen by `--dart-define=MEDIA_BACKEND=storage`).
  A `media` section toggle hides every image. Rules validate the map in the shared `common()` and cap
  `dataBase64` at 950,000 chars (Firestore's doc limit is 1 MiB). Web uses canvas (WebP) to avoid shipping a Dart
  image codec in the web bundle; Android/tests use the `image` package.
- **Consequences:** works on the free plan; each inline image costs one read per visitor session (counts toward 50K
  reads/day) and ≤ ~950 KB of Firestore storage (1 GiB free); orphan `media` docs are deleted best effort.
  Priests' old `photoUrl` stays readable as a fallback.
- **Switching to Cloud Storage after a Blaze upgrade:** (1) upgrade + budget alert, enable Storage in the console;
  (2) `flutter pub add firebase_storage` and implement `StorageMediaRepository.upload/delete`
  (`ref('media/<id>.<ext>').putData(...)` → `getDownloadURL()` → `MediaImage(source: 'storage', url, mediaId)`);
  (3) add `"storage": {"rules": "storage.rules"}` to `firebase.json`, review the draft `storage.rules`, deploy
  (`firebase deploy --only storage`; give the deploy SA *Firebase Rules Admin* for Storage too); (4) build with
  `--dart-define=MEDIA_BACKEND=storage` (CI: add it to `deploy.yml`). Existing inline images keep rendering; migrate
  them later by re-uploading if wanted, then delete the `media` docs.

## ADR-018 — Rebrand: full church title, parish seal, new Hosting domain with 301 from the old one
- **Context (PR #6):** the church asked for its own name instead of «كنيسة العصافرة», its official seal as the logo,
  and a domain that carries the church's name. A Firebase project's default Hosting site id (`asafra-church-portal`)
  cannot be renamed.
- **Decision:** display title «كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود» / "St. Maximus & Domadius
  and St. Moses the Black Church" (`appName`), short «كنيسة مكسيموس ودوماديوس» (`appShort`, manifest `short_name`,
  Android label). Headers use the seal + short name on phones (max two lines, ellipsis) and add the admin-editable
  full name on wide screens. A **second Hosting site `maximos-domadios-church`** serves the app (https://maximos-domadios-church.web.app); the old default
  site gets a tiny config that **301-redirects every path** (regex `^/(.*)$` → `/:1`) so old links/bookmarks/QR codes
  keep working. Hosting targets `app` / `legacy-redirect`; previews only for `app`. Icons are generated from the seal
  by `tool/gen_branding.sh` (maroon `#470812` sampled from the seal for maskable/adaptive backgrounds and the PWA
  `theme_color`; manifest `background_color` stays cream `#FBF6EC` to match the HTML splash). No static
  `<link rel=canonical>` in the SPA shell (it would point every route at `/`); `og:url` is the home page.
  *Superseded for the canonical by ADR-019 (PR 3 of the review plan).*
- **Consequences:** Auth authorized domains include the new domains (needed for admin sign-in); a future reCAPTCHA
  key must list the new domain; `authDomain` stays on `asafra-church-portal.firebaseapp.com` (email/password only).
  Firestore `settings/church.nameAr/nameEn` remain the admin-editable source for the full name once loaded.

## ADR-019 — Review plan PR 3: PDPL consent, static canonical + JSON-LD, deferred routes, saved language
- **Context:** the review plan's PR 3 (`feat/phase3-compliance-seo-perf`), followed exactly at the owner's request.
- **Decision:** (1) the contact form shows a PDPL privacy notice and requires an unticked consent checkbox
  (`ContactField.consent`); consent is validated client-side only and not stored, so `firestore.rules` and the
  message shape are unchanged. (2) `web/index.html` gets a static `<link rel="canonical"
  href="https://maximos-domadios-church.web.app/">` and a verified `Church` JSON-LD block. This reverses ADR-018's
  "no static canonical": the owner chose the plan's static tag knowing it points every SPA route at `/`
  (per-route canonical stays an open task). (3) `/admin` and `/ask` are `deferred as` imports wrapped in
  `DeferredLoader`, so the public bundle no longer carries the dashboard or the AI SDK; `/ask` downloads its chunk
  only once settings say the assistant is on (`AssistantGate`). (4) The language choice is
  saved in `localStorage` (`church_portal_lang`) through a conditional import on the existing `package:web` (no new
  dependency); startup precedence `?lang=` → saved → Arabic; only `toggle()`/`set()` save, URL-driven changes do not.
- **Consequences:** JSON-LD duplicates `settings/church` facts and must be edited by hand when they change (a test
  pins it to the seed). Deferred chunks add one extra request on the first `/admin` / `/ask` visit. Native apps
  don't remember the language yet.
- **Amended by PR #10:** the static `/` canonical stays in `web/index.html` as the starting value, but Flutter now
  rewrites `<link rel="canonical">` per route (`setDocumentRouteMeta`) and swaps it for
  `<meta name="robots" content="noindex">` on `/admin`, the 404 page and switched-off sections (Google advises against
  combining `noindex` with a canonical elsewhere). `web/sitemap.xml` comments out `/clinics` while the clinics
  section is off.

## ADR-020 — Item detail pages & site-wide header/footer customization (PR #11 data/rules/grounding, PR #12 admin, PR #13 public UI)
- **Context:** the customization plan (PRs #11–#13) gives admins optional rich detail pages on 7 collections (long
  text, up to 15 custom fields, up to 8 gallery photos, contacts and social links) plus per-page header/intro overrides
  and footer options (FR-G-04), with zero change for existing documents. PR #11 lands the domain models
  (`ItemDetails`, `CustomField`, `PageCustom`, `FooterConfig`, prefix-aware `sectionsForPath`), the rules, the seed
  maps and the assistant grounding; PR #12 the admin editor, PR #13 the public pages.
- **Decision:** every new toggle defaults to today's behaviour (`detailsEnabled: false`, images/contacts/socials on);
  no duplicate inputs (clinics keep `bookingPhone`, facilities `phone`, activities `link`, meetings their
  Facebook/WhatsApp URLs); the seed adds only `pageHeaders: {}` and the default `footer` map.
  **Rules within the 1,000-expression cap:** the plan's per-field / per-item checks were measured far over the cap
  (two gallery images or four page headers already failed), so writes now validate **only the keys they create or
  change** (a stored value was validated when it was written), and text fields / list items are checked on one
  U+001F-joined string with regexes. Trade-offs: gallery items' `w`/`h` are not range-checked; extraFields rows must
  carry their 4 keys (extra keys not rejected) and need a title starting with a non-space (the form trims); page
  headers carry exactly 6 keys; new detail text keys reject `null` (the form writes `''`). Optional text fields are
  read inline as `(d.get(k, null) == null ? '' : d.k)` so non-strings are still rejected (review fix; a helper
  function was measured too expensive). A single write cannot carry both full lists — PR #12 saves the gallery
  and the custom fields in their own updates.
  The assistant grounds detail text, custom fields, contacts and links only for `detailsEnabled` items (an unpublished
  draft never reaches it), respects `showContacts` / `showSocials` (+ the socials section) also for the items' existing
  phones and links, and never sees image data.
- **Consequences:** production `settings/features` needs `seed_firestore.js --fill-missing` (or one admin save) to
  carry the new maps — missing means defaults, so nothing breaks meanwhile. Rules measurements and the margins are in
  `05-firebase.md`.
- **PR #12 (admin studio):** fields carry a `FieldGroup` (`basic` open; `details`, `media`, `contacts` collapsible
  cards with `maintainState: true`, auto-opened on a validation error); each collection's own phone / link field moves
  into *Contacts* (no duplicate keys). The editor saves in up to three writes (`splitSavePayload`: other fields →
  `gallery` → `extraFields`); a failed later write keeps the earlier ones (a retry sends only the rest) and deletes
  only the uploads nothing saved references. `FeaturesScreen` likewise writes `pageHeaders` on its own
  (`featuresSaveWrites`) — the whole doc plus 8 page headers in one write was measured over the cap. Writes merge with
  `mergeFields` (map fields replaced, so a reset page header is removed). Not atomic by design: an interrupted save
  leaves a valid document with part of the edit, shown as still unsaved in the form.
- **PR #13 (public pages):** 7 flat detail routes inside the shell (`DetailKind` in `domain/item_detail.dart`);
  `ItemDetailPage` resolves the item from the list stream (no extra read) and gates it purely (`detailStateFor`:
  unavailable unless visible + `detailsEnabled`, clinics also active; priests also need their status section),
  with `setDocumentRouteMeta` (indexable only when available). Cards stay unchanged while `detailsEnabled` is off;
  when on, a labelled Details link + a pointer-only card tap (`DetailTapArea`, no nested screen-reader button) and
  no zoom on the small avatar. `showContacts` / `showSocials` (+ socials section) gate the card buttons too, so an
  item's contact/link switches hide them everywhere (the activity link is now hidden while socials are off).
  The phone Back arrow is parent-aware (`parentRouteOf`); milestones go back to Home, where their cards are.
  Page header overrides replace the built-in title/subtitle **only in the language they are written in**; intro
  notes use `context.pick`. The footer renders the FR-G-04 options (phones need `contactInfo`, socials `socials`);
  no site-wide "last updated" date (nothing tracks one).

## ADR-021 — Detail pages are opt-out; the detail page always shows the item's own info (PR #14)
- **Context:** after PR #13 an admin filled the family meeting's details, extra field, gallery and WhatsApp, but
  tapping its card did nothing: `detailsEnabled` defaulted to `false` and the editor saves only changed fields, so
  the switch was never written (live read, 2 Nov 2026). Every card on the site was inert until an admin found a
  switch in a collapsed group.
- **Research:** NN/g — a card is a short entry point to further details on a separate page, and the whole card is
  usually the click target (nngroup.com/articles/cards-component); Material 3 — on compact screens selecting a
  list item opens a page with the details (m3.material.io/components/lists/guidelines, list-detail canonical
  layout: one pane below 600 dp); accessible-card patterns — big hit area, chevron/visible link affordance, single
  labelled link for screen readers, inner buttons stay operable (dap.berkeley.edu accessible card patterns,
  developer.chrome.com card guidance); Google Calendar template links take `ctz` + `recur=RRULE:…`
  (interactiondesignfoundation.github.io/add-event-to-calendar-docs).
- **Decision:** missing `detailsEnabled` = **on** (model, admin `missingBool`/`newBool` true, admin badge/link);
  only an explicit `false` hides the page and the card link. Firestore rules unchanged (type check only). The page
  always carries the item's own info as labelled key facts, then summary, long text, custom fields, gallery,
  contacts, links; quick actions add to calendar (weekly items), directions (on-site items, `contactInfo` on) and
  share (copy canonical link); "More in this section" from the same list (no extra reads). Cards stay uncluttered —
  details live on the page.
- **Consequences:** every visible item is a shareable, indexable page; the assistant grounds detail text for every
  item that has some unless switched off; existing explicit `false` values keep hiding pages. Admins who saved
  `showDetailImages: false` keep photos hidden on that page (their choice).

## ADR-022 (revised 3 Nov 2026; accepted, merged with PR #15) — "Golden hour" visual identity (branch `design/coptic-identity`)

- **Context:** the team found the UI generic ("AI-slop") and not business-ready. A first draft ("Iconostasis": flat
  plaster wall, Naskh/Marcellus, 4 px radii, oxblood `#7B2216`) was reviewed and **replaced**: the team wanted the site
  to look like the parish's own posters (`work/design/poster_refs/`).
- **Decision (proposed):** poster identity — church in golden-hour clouds (Gemini-painted art, decorative only),
  heavy maroon **Lalezar** titles with a small red **Aref Ruqaa** accent word, subtitle ribbons, translucent warm
  panels (20 px radius, soft shadow), saints in gold halos over the Nile, IBM Plex Sans Arabic body; default primary
  preset `burgundy` = poster maroon `#6E1C1C`; grouped nav (Home · About · Church services ▾ · Ask · Contact + "Mass
  times" CTA). Hero motion (drift, light rays) and a muted clouds video loop (`video_player`) behind the admin switch
  **`settings/features.heroMotion`** (bool, default on; rules accept only a bool); visitors' reduced-motion and
  save-data settings always win. Fonts and art are bundled assets (no runtime fetch).
- **Layout pass (3 Nov 2026):** `ResponsiveGrid` is 1/2/3 columns (phone/tablet/desktop) on its own width, full width
  and start-aligned in RTL; content max width 1200; `Space` tokens; cards size to their content and optional fields
  collapse with their gaps (`TimeRangeText` renders nothing without a time). Tests at 320/390/1440 px × 1×/2× text.
- **Status:** approved by the team on 3 Nov 2026 ("The UI looks amazing") and squash-merged as PR #15; direction
  doc `docs/design/direction.md`.
- **Seamless hero (PR #15 final round):** phone screenshots showed hard rectangular edges in the hero (a vertical
  line on the right, a horizontal line near the buttons, a lighter box behind the title, a line where the hero ends).
  Causes: the gold haze was two non-tileable texture tiles side by side at 70 % height (moving vertical seam +
  horizontal bottom edge); `TextScrim` was a circular `RadialGradient` clipped to its rectangular text box (still
  ~45 % alpha at the box's top/bottom edge); the bottom fade ended at 95 % cream on a textured backdrop. Fix: every
  stage layer is `StackFit.expand` over the whole hero (outside the 1200 px cap); the haze is a mirrored strip
  (A · mirror(A) · A, drift 2 widths per minute — seamless and loop-exact) under a vertical alpha ramp; rays have a
  blur mask; `TextScrim` paints an elliptical radial glow that bleeds 56/40 px past the text and reaches 0 alpha
  inside its own bounds; the stage dissolves to **transparent** at the bottom (`BottomFeather`, `ShaderMask` dstIn: a
  smoothstep ramp from 62 % to 100 % of the height — a linear ramp's slope break reads as a line — and the last 2 px
  trimmed, because on the web the partially covered last device row escaped the mask as a thin dark line) so the
  page backdrop shows through. The haze strip is aligned to the physical left (`Alignment.topLeft`): start-aligned in
  RTL it hung off the right edge and left an empty band (a moving vertical edge). Same widgets serve inner page headers
  and the patrons band (band title padding raised so its glow ends before the band edge).
- **Hero video (PR #15 final round):** source `A_clouds_church_loop.mp4` trimmed to seconds 3–10 (the first 3 s
  morph the church) with ffmpeg, then a 1 s frame-matched crossfade folded into the end so the loop restarts on the
  next frame of the clip (6 s, muted, no audio track): `assets/video/hero_clouds.mp4` 1280×720 (~310 KB) for
  tablets/desktops and `hero_clouds_tall.mp4` 404×720 centre crop on the church (~110 KB) for phones; posters are
  their first frames (`assets/art/hero_poster{,_tall}.webp`), precached and shown until the video plays. On the web
  the loop is a native `<video muted playsinline loop>` (`HtmlElementView.fromTagName`, `hero_video_web.dart`) so
  phones autoplay it and its bottom can take the same feather as a CSS mask (a platform view cannot be masked by a
  `ShaderMask`); it fades in (CSS transition) on the `playing` event, so there is no black frame or jump. Android/iOS
  use `video_player` (`hero_video_io.dart`). Ken Burns runs only on the still painting (the video keeps registered
  with its poster). Still gated by `heroMotion` (default on), reduced motion and save-data; paused off-screen.

## ADR-018 amendment (3 Nov 2026, PR #15) — new parish seal

- The church supplied a new seal (white disc, gold double ring, Coptic lettering, the church with two towers,
  «بطريركية الأقباط الأرثوذكس بالإسكندرية», the church name, «العصافرة قبلي ش ٤٥»). The master
  `assets/branding/seal_source.webp` is now the **round seal on transparency** (1024 px, lossless; cropped to the
  outer ring from the 1792×2400 original). `tool/gen_branding.sh` was rewritten for a transparent round master:
  in-app `seal.png` 384 px, favicons with a light unsharp (crisp, small lettering not legible at 16–48 px by nature),
  PWA "any" icons round on transparency, Apple touch icon on white, maskable 192/512 at 78 % on maroon `#470812`,
  OG card 1200×630 (seal on maroon; also the JSON-LD `image`), Android legacy + adaptive foreground (59 %), and a new
  Android launch-screen seal (`mipmap-*/launch_image.png`, 128 dp, wired in `launch_background.xml`). On the maroon
  seal tab and drawer header the white seal sits in a thin gold ring with a soft shadow.

## ADR-023 (draft, PR #15) — Image display styles: avatar / card / banner

- **Context:** one small thumbnail for every picture made people's photos, event pictures and saint icons look the
  same and cropped them; admins asked to show a whole picture or a portrait.
- **Decision:** three styles (`lib/domain/image_style.dart`, `ImageStyles`): `avatar` (round, gold halo ring, leads the
  title row), `card` (large cover on top of the card, whole picture visible — `BoxFit.contain` over a blurred sepia
  copy; portrait 4:5 for saints, 4:3 otherwise, height capped), `banner` (full card width, 16:7, edge to edge).
  Resolution: the item's own **`imageStyle`** → the admin's section default **`settings/features.imageStyles[collection]`**
  → built-in default (priests & departed, clinics → `avatar`; saints → portrait `card`; activities, milestones,
  meetings, alerts, seasons, facilities → `card`). Missing/invalid value = the next level. Shared widgets
  `lib/ui/widgets/styled_image.dart` (`CardCover`, `CardLead`, `HaloAvatar`, `FittedCover`, `DetailCover`) on every
  card and detail page (saint detail keeps its header halo unless the style is `banner`).
- **Data/rules:** `imageStyle` allowed on the 9 image collections (`null`/absent, `avatar`, `card`, `banner`);
  `imageStyles` on `settings/features` (map, known collections only, known styles only); new documents do not write
  an unset style and the features save omits an empty map, so saves keep working against rules that predate them.
  Emulator tests in `tool/rules_test/rules.test.mjs` (ADR-023 group). Not seeded (missing = default).
- **Admin:** item form "Image display (— = section default)" next to the image; Settings → "Image display" card with
  one default per section.
- **Invariant:** no image or images switched off → the card is exactly as before (golden rule #9).

## ADR-024 (PR #16) — Verse of the day on the home page

- **Context:** the church wanted a short daily scripture on the home page. Golden rule #1 forbids invented content, so
  verse text must never be typed from memory.
- **Decision:** bundle `assets/verses/daily_verses.json`: **366** verses of the public-domain Arabic **Van Dyck
  (Smith-Van Dyke, 1865)** Bible, copied byte-for-byte by `tool/gen_daily_verses.py` from eBible.org's
  `https://ebible.org/Scriptures/arb-vd_vpl.zip` ("Public Domain", Syrian Mission / American Bible Society), zip
  pinned by SHA-256 `070404da…cd68a`. References are picked in `tool/daily_verse_refs.txt` (well-known verses; texts
  over 420 characters skipped; first 366 kept, then a fixed shuffle so books mix through the year). Each entry has
  `textAr`, `refAr` (Arabic book name + Arabic-Indic digits, «يوحنا ٣: ١٦»), `refEn` ("John 3:16") and `ref` (source code).
- **Rotation:** `cairoDayOfYear(now)` (pure Dart, `lib/domain/daily_verse.dart`) = day of the year of the
  **Africa/Cairo** calendar date (via `CairoTime`), so the verse changes at Cairo midnight (22:00 UTC in winter,
  21:00 UTC in summer), never at UTC or device midnight. Day N shows entry N−1 (wraps if the list is shorter; day 366
  only in leap years).
- **Admin:** on/off is a public section, **`sections.dailyVerse`** (golden rule #6; Codex review on PR #16 — a
  separate `enabled` flag would not follow the section toggles), missing = on, seeded `true`. Mode and fixed verse:
  `settings/features.dailyVerse` map `{mode: 'daily'|'fixed', textAr ≤500, refAr ≤60}`; missing map/keys = daily. A fixed verse with empty text falls back to the rotation (the admin form also
  requires text in fixed mode). Written only once it differs from the default or is already stored (saves keep
  working against older rules, like `heroMotion`). The map is not seeded (missing = default).
- **Rules:** `sectionKeys()` gains `dailyVerse`; `validFeatures` allows `dailyVerse`, validated by `validDailyVerse` only when it changes (known keys only,
  bool, mode in the two values, strings joined + regex for lengths). Emulator group "Verse of the day".
- **UI:** `DailyVerseCard` right under the hero (not an orderable home block: that would change `homeOrder` rules);
  WarmPanel, Ruqaa accent «كلمة الله», Lalezar title in the theme primary, verse in Plex bold on ink, reference in
  `goldText` inside «». All text ≥ 4.5:1 on the panel even over the gold backdrop (test). The English UI shows the
  English reference; the verse stays Arabic.

### ADR-024 amendment (PR #17) — the verse of the day lives in the hero

- The hero's fixed verse (`settings/church.verseAr/En/verseRef*`) is replaced by the verse of the day (daily rotation
  or the admin's fixed verse) in the same panel and typography (`HeroVerse`); the separate `DailyVerseCard` under the
  hero is removed so the verse appears once. `sections.dailyVerse` shows / hides the hero verse. The church verse
  fields stay in the model and admin form (and the assistant grounding) but are no longer rendered publicly.

## ADR-025 (PR #17) — Occasion themes

- **Context:** the church wanted the site to follow the church year — sombre black for Holy Week (أسبوع الآلام),
  festive for the Resurrection (القيامة), and presets for the Nativity, fasts and Marian feasts — with the Golden hour
  maroon `#6E1C1C` staying the default, and everything editable from /admin. Text had to stay readable everywhere.
- **Decision:** a theme is a full **palette** (`ThemePalette`, 10 colours: primary, onPrimary, onPrimaryAccent,
  background, surface, surfaceAlt, ink, muted, goldText, script), not just an accent. Presets: `goldenHour`
  (default), `holyWeek` (dark), `resurrection`, `nativity`, `epiphany`, `fasting`, `marian`, plus the accent-only
  `navy/green/brown/purple` kept from before. `burgundy` (stored in live data and the seed) reads as `goldenHour`.
  Golden hour's `goldText` was deepened `#7A5410 → #6F4C0E` to reach 4.5:1 on the darkest cloud-texture pixel.
- **Readability model:** `ThemePalette.checks` lists every text role on every ground the widgets paint: panels and
  cards (surface at 92 % over black and over white, surfaceAlt), the scene (background + the cloud texture's darkest /
  lightest pixel at 28 %, 12 % on dark scenes), the hero / header scrim (background at 80 % over black and white — any
  picture or YouTube frame), and the primary bars (primary and its deep end). Body text needs 4.5:1, large headings
  on the scrim 3:1 (primary is held to 4.5 there too because a text button sits on it). `normalized()` pushes
  surfaces out of the mid-grey band and nudges each text colour toward black or white just enough; it runs on admin
  save and again at render, so even a hand-edited document stays readable. Tests: every preset passes untouched; 400
  random palettes pass after normalisation; a widget walk measures every rendered paragraph against its painted
  ground on the public pages for every preset (all routes for Holy Week and the Resurrection).
- **Scheduling:** `occasions.auto` off = the selected theme always applies (manual override). On: first admin range
  covering the **Cairo** date, then (with `easter`) Holy Week = Palm Sunday → Holy Saturday and the Resurrection =
  Easter Sunday + `resurrectionDays` − 1 (default 7, up to the 50 days), else the selected theme. Coptic Easter =
  Meeus' Julian computus + the Julian–Gregorian gap (`orthodoxEaster`), tested against 2001–2030 and for 1900–2099
  (always a Sunday, 4 Apr–8 May). The switch happens at Cairo midnight (tested in EET and EEST).
- **Rules budget:** ranges and colours are stored as strings (one regex each) in slot maps; colours in their own
  field `themeColors`. A first save with maps-of-maps exceeded the 1,000-expression cap in the emulator.
- **Admin dashboard** keeps the Golden hour palette (wrapped in its own `Theme`).

## ADR-026 (PR #17) — Hero video library from YouTube links

- **Context:** the church wanted to choose hero videos without uploads (Spark plan: no Storage, no video bytes in
  Firestore).
- **Decision:** `settings/features.heroVideos` holds up to 12 named YouTube links (slots `v1…v12`), the active slot
  (`''` = the bundled `hero_clouds*.mp4`, kept as default and fallback, ~110 KB phone loop) and an optional slot per
  theme. Links are validated in the app (`youtubeVideoId`: youtube.com watch/embed/shorts/live, youtu.be,
  youtube-nocookie embed; 11-char id) and stored canonical; rules accept only the canonical shapes.
- **Playback:** web = a youtube-nocookie IFrame-player `<iframe>` (autoplay, mute, loop + playlist, controls 0,
  playsinline) in a CSS-masked platform view, events via the IFrame API postMessage channel ("listening" handshake;
  `onStateChange`/`infoDelivery` playing → fade in; `onError`/`onAutoplayBlocked`/12 s timeout → fallback); mobile =
  `youtube_player_iframe` ^6.0.2 (maintained; WebView). Same gating as the clip (reduced motion, data saver,
  `heroMotion`). Dark themes dim it with a CSS filter. Playback cannot be verified in headless tests (MotionEnv.isTest
  disables video); parsing, library logic, provider choice and rules are tested.

## ADR-027 (PR #18) — Admin-defined categories and custom pages coexist with the built-in sections

- **Context:** the church must be able to add, rename, reorder, hide or delete public categories (e.g. drop
  "Clinics", add "Youth trips"), assign items to them, and build generic pages (e.g. donations for the new church
  building) — everything from `/admin`, nothing locked. The built-in sections (liturgies, meetings, activities,
  clinics, facilities, priests, saints, milestones) each have specialised fields, schedule logic, detail routes
  (ADR-020/021), assistant grounding and seed ids.
- **Options:** (a) migrate the built-ins into one generic "category + item" model; (b) let them coexist with a new
  generic model. (a) would rewrite every list/detail page, the next-mass logic, the assistant grounding, the seed
  and the rules, and needs a live data migration (risk of data loss, Spark plan: no Functions to run it).
- **Decision: (b) coexist, no migration, no data touched.**
  - Built-in sections stay as they are: hidden / "removed" with their `settings/features.sections` switch,
    renamed with `pageHeaders` (both already existed), item order with `order`. The Custom sections admin list
    says so in a note (`CollectionDef.noteAr/noteEn`).
  - New collections: `categories/{auto-id}` (slug, names, intros, icon, default image style, `showInNav`,
    `visible`, `order`), `entries/{auto-id}` (an item with `categoryId`, title, description, optional image +
    `imageStyle`, phone, link + label, `visible`/`order`/`sample`) and `pages/{auto-id}` (slug, title, subtitle,
    hero `image`, up to 20 `blocks`, `showInNav` off by default, `visible`/`order`). Public routes
    `/section/<slug>` (`CategoryPage`, same `Card` / `ResponsiveGrid` / `CardCover` / `CardLead` image styles as
    ADR-023, item style else the category's) and `/page/<slug>` (`CustomPageView`); hidden / unknown slugs show
    "not available" with `noindex`. Categories with `showInNav` join the "Church services" menu and drawer group;
    pages with `showInNav` join the desktop bar and the "The church" drawer group, after the built-ins.
  - Deleting a category asks for confirmation and first sets `visible: false` on each of its visible items, then
    deletes the category doc; items are never deleted. An item whose category no longer exists is never shown
    publicly (its page is gone) and can be reassigned (the editor shows «قسم محذوف أو غير محدد»).
  - Two section switches (Codex review): `Sections.customSections` gates `/section/*` and the category menu
    entries, `Sections.customPages` gates `/page/*` and the page menu entries (`routeSections['/section' | '/page']`,
    prefix-aware), so all custom content can be switched off at once (rule 6 of `AGENTS.md`). Seed and rules
    `sectionKeys()` list them (on).
  - Missing collections = empty (not in the seed; the seed is not run): the public site looks exactly as before
    until an admin creates something.
- **Page blocks:** heading, paragraph, image (https link + caption), button and text link (in-app path or URL,
  with the admin's link picker), donation info (bank account, InstaPay, wallet, notes; display only, copy buttons,
  "no payment is made on this site"). Each block is stored as **one string** (7 fields joined by U+001F,
  `PageBlock.encode`): one regex per block keeps a full first save of 20 blocks within Firestore's 1,000 rule
  expressions per write (maps cost ~2× and failed in the emulator); blocks are saved in their own write
  (`separatelySavedKeys`). The admin edits them as rows (`FieldDef.encodedRows`, fields per type via `showWhen`).
- **Notices → pages:** the alert `link` (and items' links) keep their format (`optUrlOrPath`); the admin field gets
  a "Pick a page…" list (`FieldDef.linkPicker`): custom pages first, then custom categories, then the built-in
  routes (`linkTargets`), or a typed external URL. The banner "Learn more" (`AlertBanner`) already opens in-app
  paths with `context.go`.
- **Not done:** built-ins are not reorderable among custom categories in the menu (built-ins first); custom items
  have no detail page of their own (the card shows the full description); `sitemap.xml` is static and does not
  list custom sections/pages.

## ADR-028 (PR #18) — Contact categories, bookings and anonymous complaints / suggestions

- **Decision:** `settings/contact.categories` holds up to 12 slots `c1…c12`, each **one string**
  `kind␟on␟anon␟order␟labelAr␟labelEn␟subtypes` (`ContactCategory.encode`; maps with 8 subtypes each exceeded the
  rules budget for a 12-slot save). Kinds: `general`, `booking` (subtypes such as فرح / عزاء, a preferred date
  and a phone are required), `complaint`, `suggestion`. Missing doc = code defaults (`ContactSettings.defaults`,
  mirrored by `defaultContactCats()` in the rules): general inquiry, hall booking (wedding / condolence),
  complaint and suggestion (both anonymous-capable). Nothing is seeded.
- **Messages:** `category` (slot) + `kind`; bookings add `bookingType` + `preferredDate` (YYYY-MM-DD, client
  checks today or later on the Cairo calendar). The rules require the slot to exist and be on, and `kind` to match
  it. Messages without a category (the pre-PR shape) stay valid.
- **Anonymous:** only for a category whose kind is complaint / suggestion and whose admin switch allows it. The
  form hides name / phone / email, says "your name, phone and email are not stored at all, so we cannot reply",
  and swaps the PDPL notice and consent for anonymous wording (only the message text is stored). The payload and
  the rules carry **no** `name`/`phone`/`email`/booking key at all (`anonymous: true`).
- **Spam:** unchanged server throttle (one message per 10 s globally via `meta/contact_rate`, ADR-010) + client
  limiter + honeypot; size limits unchanged (message 5–1000).
- **Inbox:** a box per category (+ "Other / deleted type" and a separate anonymous box), open / done / all
  filters, booking status new → contacted → confirmed / declined, internal `adminNotes` (≤ 2000). Admins may only
  change `status` and `adminNotes`.
- **Caveat (fixed in PR #19):** deleting a type used to free its slot for the next new type, re-labelling the old
  messages. Since PR #19 categories have **stable ids that are never reused**: the defaults keep `c1…c4`, every new
  type gets `newContactCategoryId` = `c` + 10 random lower-case letters / digits (never digits only, never an id
  removed in the editor). Messages of a deleted type stay under "Other / deleted type". Rules accept any id matching
  `c[0-9a-z]{1,15}` (1–12 entries, keys read by position — `contactCatAt`); they check the format only — non-reuse
  is the editor's guarantee (no record of retired ids; only admins write).

## ADR-029 (PR #19) — The assistant on web + Android: App Check, a free model, scope and admin settings

- **Context:** Firebase AI Logic requires App Check enforcement since 2 Nov 2026; the assistant was hidden because
  the web app had no App Check key. The console now has a **reCAPTCHA Enterprise** key ("church-portal-web") and
  the web app is registered with the reCAPTCHA Enterprise provider; AI Logic enforcement is on. `gemini-2.5-flash`
  is limited to projects that used it before and shuts down on Agent Platform; the owner wants the cheapest free
  model and prefers Google's open Gemma family. Everything must be customizable from `/admin`.
- **App Check:** `selectAppCheckPlan` (`lib/data/app_check_providers.dart`): web release →
  `ReCaptchaEnterpriseProvider(RECAPTCHA_SITE_KEY)` (a v3 provider is rejected by an Enterprise key), no key → not
  activated (assistant hidden, PR previews); Android release → Play Integrity; Apple → App Attest + DeviceCheck;
  debug builds / `APPCHECK_DEBUG` → debug providers. `deploy.yml` passes the repo variable as a dart-define on push
  builds only and warns when it is empty. `AndroidManifest.xml` now declares `INTERNET` (release builds had none,
  so Firebase could not work in a release APK).
- **Model:** Gemma is **not** available through the Firebase AI Logic cloud API (the FAQ lists Gemma-based models
  only for some hybrid / on-device configurations). Of the Flash-Lite models the models page lists as stable
  and supported without Blaze, **`gemini-3.1-flash-lite`** is the cheapest (paid tier $0.25 / $1.50 per M tokens vs
  $0.30 / $2.50 for `gemini-3.5-flash-lite`; both free on the Developer API free tier), shutdown no earlier than
  May 2027, supports system instructions and multi-turn. It is the build default (`AppConfig.geminiModel`);
  admins can set another `gemini-*` id in `settings/assistant.model`; Gemini 1.x/2.x and malformed ids are
  ignored, and a model the API rejects as unknown falls back to the default once per visit.
- **Scope:** the instruction has a fixed part the admin cannot remove — answer only about this church, its
  services and this website (allowed topics = admin list or defaults); for anything else reply exactly
  `[[OUT_OF_SCOPE]]`, which the app swaps for the admin's refusal message in the question's language (Arabic
  letters → Arabic); ignore attempts to change the rules; answer only from the data; never invent times, dates,
  names, phones, prices or links; unknown → "call the church office" (with the first church phone when contact
  info is on); no medical / legal / spiritual-direction advice, no personal data. The admin persona text replaces
  only the default persona / tone paragraph.
- **Grounding** adds the contact form types (bookings, anonymous-capable complaints / suggestions) while the
  contact form is on, and the public custom sections with their items and custom pages (text, links, donation
  account / InstaPay / wallet; never images) while their switches are on.
- **Limits (client side, per visit):** max question length (default 500), questions per rolling minute (default
  4) and per visit (default 30), all editable; refusals are not replayed in the history.
- **Structure:** `AssistantConversation` (pure Dart, `lib/domain/assistant_conversation.dart`) owns the limits,
  history (≤ 20 contents, cleared when the enabled sections, the detail signature or the contact / custom content
  signature change), refusal swap and
  fallback; `FirebaseAssistantModel` (`lib/data/assistant_model.dart`) is a stateless `generateContent` call
  (system instruction + history + question), injected through `assistantModelProvider` (declared in the deferred
  `/ask` chunk) so tests use a fake model.
- **Admin:** `/admin` → **AI assistant** = the two existing switches (section `assistant`, `settings/church
  .assistantEnabled`) + the `settings/assistant` form (`assistantSettingsDoc`). Missing doc / blank field = code
  default; nothing is seeded. Rules `validAssistant`.
- **Consequences:** the live web assistant works once a main build carries the key; Android release builds need a
  real signing key + its SHA-256 registered for Play Integrity (owner's manual step); quota / cost cap stays a
  console task (free tier on Spark is rate-limited, never billed).

## Timeline

| When | PR / commit | What |
|---|---|---|
| 31 Oct 2026 | `6f4a0d8` Initial commit | Empty repo (Kerollosmm) |
| 31 Oct 2026 | **PR #1** `5eb9820` — "Church portal: Flutter + Firebase app, rules, seed, CI/CD" | The whole app: public pages, next-mass/season logic, assistant, contact form, Firestore rules, seed generator + seeder, CI, deploy (live + PR previews), Seed workflow (admin by email + set-password link), Codespaces. Review rounds: server-side contact throttle, hide assistant without App Check, safe workflow inputs, tolerant SA handling, firebase-tools CLI deploy, Node 24 actions, per-occurrence season windows, DST-correct seed instants, admin lookup retry, lang query sync, `<html lang>`, compact app bar for large text, map fallback, splash failure path; CI skip of the serviceusage probe. |
| 31 Oct 2026 | **PR #2** `c42837a` — "Content: replace sample data with verified church data" | Real name/address (Qebly)/coordinates/landline/socials/bishop/history/milestones, reconciled priests, saints, activities with links, Anba Abraam, real alerts; times stay sample with page notice; no invented doctors/phones; `--force` deletes retired ids; `docs/CONTENT_SOURCES.md`. Review: unconfirmed one-offs in assistant, partner orgs labelled, new unconfirmed priests not seeded. |
| 1 Nov 2026 | **PR #3** `fc0e0ad` — "Admin dashboard overhaul + per-section feature toggles" | `settings/features` (15 sections, home layout, hero, banner, theme), visible/order on items, responsive dashboard (overview, church info, every collection, search/filters, hide/show, drag reorder, validated forms, inbox, owner-only admins), rules for every write + emulator tests + CI job, seed `--fill-missing`/`--only` + known ids, README admin guide. Review: no flash of disabled content, live role, rules expression budget, stamps bound to request time/admin, clinic days 1–7, bannerLink format, changed-fields-only saves, reload banner. |
| 1 Nov 2026 | **PR #4** `6c52698` — docs/memory-bank | This memory bank + `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`. |
| 1 Nov 2026 | **PR #5** — "Optional images (Spark-friendly inline media)" | Optional `image` on priests/departed fathers, saints, milestones, activities, alerts, seasons; admin upload (client resize/compress → `media/{id}`), https URL or remove, alt text, preview; `ItemImage` (lazy, cached, fade-in, placeholder, tap to enlarge); `media` section toggle; `MediaRepository` + Storage stub + draft `storage.rules`; rules + emulator tests; ADR-017. |
| 1 Nov 2026 | **PR #6** — "Rebrand: church title, parish seal logo, new domain" | Full church title + short name everywhere (web title/OG/manifest/app/l10n/Android label), parish seal as logo/splash/favicons/PWA/Android icons (`tool/gen_branding.sh`), new Hosting site `maximos-domadios-church` as the live app with a 301 redirect from `asafra-church-portal.web.app`, OG/robots/sitemap on the new domain; ADR-018. |
| 1 Nov 2026 | **PR #7** `6a30772` — "PR 1: domain, AI grounding, resilience & security rules" | Review plan PR 1: `Season.replacesRegular`, upcoming special services, seasonal tie-breaks, assistant grounding, seed-fallback recovery, contact timeout UX, rules SEC-01–SEC-05, clinics section off in the seed. |
| 1 Nov 2026 | **PR #8** `bc934d3` — "PR 2: UX, WCAG 2.2 AA, navigation, admin & docs" (`fix/phase2-ux-a11y-admin`) | Review plan PR 2: `AppColors.goldText`, darker WhatsApp/Facebook fills, footer `white70`, theme presets everywhere (`primaryDarkOf`); 320 px / 200 % text fixes (`Pill`, `TitleWithBadge`, timeline `Wrap`, app-bar collapse, alert/next-mass headers); Back-to-Home arrow, 48 dp targets; two-way `?lang=` sync (BUG-07); `departedDate` (BUG-08), alert link gating (BUG-09), BiDi secondary times (BUG-10), "Today" badge (FR-E-03), map `hl` (BUG-16), `runSpacing` (BUG-15); live regions, labelled buttons/switch, reduced-motion skeleton, Move up/down (2.5.7); admin: no scroll reset on save (BUG-12), departed order base 1000 + keep media on timeout (BUG-13), re-subscribe on backend change (BUG-18), Open on site; `test/accessibility_test.dart`. |
| 2 Nov 2026 | **PR #9** `ad621cf` — "PR 3: compliance, SEO, deferred bundles & locale storage" (`feat/phase3-compliance-seo-perf`) | Review plan PR 3: PDPL privacy notice + required consent checkbox (`ContactField.consent`, FR-CT-06); static canonical + verified `Church` JSON-LD in `web/index.html` (ADR-019); `/admin` and `/ask` as deferred chunks via `DeferredLoader` (`/ask` fetched only when the assistant is on — `AssistantGate`); language choice saved in `localStorage` (`LanguageStore`, `?lang=` → saved → Arabic); `test/phase3_test.dart`. |
| 2 Nov 2026 | **PR #10** — "PR #10: post-audit polish" (`fix/pr10-post-audit-polish`) | Assistant header uses the Cairo date/weekday; dated liturgies (even with a weekday) are grounded only as current one-off services (`isDatedLiturgyCurrent`); admin chip contrast, narrow reflow, tooltips, `didUpdateWidget` re-binding on Features/Messages/Admins, stamped `setAdmin`; per-route canonical + `noindex` (`setDocumentRouteMeta`, amends ADR-019), URL fragments kept by `?lang=` sync, `/clinics` commented out of the sitemap; `validFeatures` on `keysAllowed` + `optUrlOrPath`, `storage.rules` contentType guard, `deploy-rules` needs `build`. |

| 2 Nov 2026 | **PR #11** — "Domain models, security rules, seed & AI grounding" (`feat/pr11-domain-rules-seed`) | Customization plan PR #11: `ItemDetails`/`CustomField` on the 7 detail collections, cover `image` on meetings/clinics/facilities, gallery-aware media orphan helpers, prefix-aware `sectionsForPath`/`routeEnabled`, `PageCustom` `pageHeaders` + `FooterConfig` `footer`; budget-aware, change-gated rules (ADR-020) + 14 emulator tests; seed maps; assistant grounding for milestones and detail pages. |

| 2 Nov 2026 | **PR #12** — "Admin customization studio" (`feat/pr12-admin-customization-studio`) | Customization plan PR #12: `FieldGroup` + `FieldType.imageList`; detail / photos / contacts groups on the 7 collections (cover image now on meetings/clinics/facilities, BR-11 warning on meetings' photos); gallery upload / link / alt / reorder / remove (≤ 8) with orphan clean-up; split saves (`splitSavePayload`, `featuresSaveWrites`) and `mergeFields`; Page headers + Footer cards; detail badge and item link on list rows; `ObjectKey(_stream)` on lists, messages, admins; 320 px / 200 % reflow (row actions, messages, admins, dropdowns); emulator tests of the editors' write sequences. Review fixes: extra-field rows accept a title in either language (`rowRequireAnyOf`), orphan clean-up measured from the save's first attempt (`_saveBaseline`). |

| 2 Nov 2026 | **PR #13** — "Public clickable detail pages, custom headers & upgraded footer" (`feat/pr13-public-detail-pages`) | Customization plan PR #13 (final): 7 detail sub-routes + `ItemDetailPage` (lazy zoomable cover/gallery, long text, custom-field cards, contact & social actions, dual priest gating, per-item canonical/noindex); parent-aware phone Back arrow; Details links / card tap on the 7 list cards, item contact/social switches on card buttons, optional images on meeting/clinic/facility cards; `CustomizablePageHeader` + `PageIntro` on the 8 customizable pages; FR-G-04 footer (phones, social icons, quick-link switch, note); `test/detail_pages_test.dart`. |

| 2 Nov 2026 | **PR #14** — "Detail pages that actually open" (`feat/pr14-detail-pages-default-on`) | Opt-out detail pages (missing `detailsEnabled` = on) so every card opens its page; labelled key-facts card, Google Calendar link (weekly RRULE, Cairo zone), directions, copy-link share, "More in this section", hero cover; admin switch on by default with hint, phone rows move the open-page icon under the subtitle; home directory card "Learn more" wraps at 320 px / 200 %; ADR-021; `test/detail_ux_test.dart` + PR #14 group in `test/detail_pages_test.dart`. |
| 3 Nov 2026 | **PR #15** — "Golden hour identity, image display styles, seamless hero video, new parish seal" (`design/coptic-identity`, squash-merged as `a97987c`) | Poster identity (ADR-022 revised): Lalezar + Aref Ruqaa, maroon `#6E1C1C`, ribbons, halos, Gemini art, hero motion + video behind `heroMotion`; image display styles avatar/card/banner (ADR-023) with rules + emulator tests; layout pass (1/2/3-column grid, 1200 max width, `Space` tokens, collapsing optional fields). Final round: seamless hero (full-bleed feathered layers, mirrored haze strip, radial title glow, transparent bottom dissolve), hero video trimmed to 3–10 s with a crossfaded loop, portrait crop on phones, poster crossfade (native `<video>` on web); new parish seal + regenerated icons/splash (ADR-018 amendment); painted saints served at `/art/*.webp`; `test/golden_hour_test.dart`, `test/image_style_layout_test.dart`. |
| 3 Nov 2026 | **PR #16** — "Daily Bible verse on the home screen" (`feat/daily-verse`) | 366 public-domain Arabic Van Dyck verses bundled from eBible.org (`tool/gen_daily_verses.py`, SHA-pinned), rotation by the Africa/Cairo day of year (changes at Cairo midnight), golden-hour `DailyVerseCard` under the hero with «reference», admin on/off (`sections.dailyVerse`) + daily/fixed verse (`settings/features.dailyVerse`), rules + emulator tests, seed regenerated, ADR-024, `test/daily_verse_test.dart`. |

| 3 Nov 2026 | **PR #17** — "Occasion themes, YouTube hero video library, verse of the day in the hero" (`feat/occasion-themes`; PR #16 was squash-merged as `6759f0d`) | ADR-025/026 + ADR-024 amendment: full-palette themes (Golden hour default, dark Holy Week, festive Resurrection, Nativity, Epiphany, fasts, Marian, 4 accent presets), `context.pal` everywhere public, contrast model + auto-correction + rendered-text contrast walk, Cairo-date schedule + Coptic Easter, admin theme / colour / video editors, YouTube hero (IFrame player on web, `youtube_player_iframe` on mobile) with clip fallback, hero shows the verse of the day (card removed), rules + emulator groups. |

| 3 Nov 2026 | **PR #18** — "Custom categories & pages, contact categories with bookings and anonymous messages" (`feat/categories-pages-contact`; PR #17 was squash-merged as `55e2a92`) | ADR-027/028: `categories` / `entries` / `pages` collections with `/section/<slug>` and `/page/<slug>`, menu entries, block editor (heading, paragraph, image, button, link, donation info), link picker for notices; `settings/contact` types (general, hall booking with occasions + date + phone, complaint, suggestion) with anonymous sending; inbox boxes, booking status and notes; rules + emulator groups; contrast walk over the new pages on every preset. |
| 3 Nov 2026 | **PR #19** — "Assistant on web + Android: reCAPTCHA Enterprise / Play Integrity App Check, Gemini 3.1 Flash-Lite, church-only scope, admin settings" (`feat/assistant-ai-logic`; PR #18 was squash-merged as `37a58d5`) | ADR-029: `selectAppCheckPlan` (Enterprise on web, Play Integrity on Android, debug providers in debug), `INTERNET` permission for release APKs, default model `gemini-3.1-flash-lite` (Gemma not offered by AI Logic cloud), admin-editable model with fallback, fixed scope + `[[OUT_OF_SCOPE]]` refusal swap, grounding of contact types / custom sections / custom pages, per-visit limits, `/admin` → AI assistant (`settings/assistant`, rules `validAssistant`); contact categories get stable never-reused ids (ADR-028 caveat fixed); `test/assistant_test.dart` + emulator groups. |

Append new PRs to this table.
