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
  **Caveat (noted in PR #25):** create-only means a seeded document an admin **deleted** comes back on the next
  seed run (it no longer exists, so it is created again) — e.g. the 11 placeholder clinics the owner deleted on 3 Nov 2026.
  Deleting in /admin is therefore only durable while nobody seeds that collection. To make a deletion survive
  seeding, remove the doc from `tool/gen_seed.py` **and** list its id under the collection's key in the `retired`
  dict there (the generator asserts every known id is either still seeded or retired, and writes
  `tool/retired_seed_ids.json`), then regenerate the seed.

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

## ADR-026 (PR #17) — Hero video library from YouTube links — **superseded by ADR-036 (removed in PR #25)**

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

## ADR-030 (PR #21) — Assistant replies: safe Markdown, confident data answers, general faith answers
- **Problem (live /ask, Nov 2026):** replies showed raw `*` bullets / `**bold**`, and nearly every answer ended with
  "these times are unconfirmed / ask the church".
- **Markdown:** own ~250-line renderer (`simple_markdown.dart` + `SafeMarkdown`) instead of a package — the subset is
  tiny, we control link safety (http(s), `tel:`, internal `/path` only; `javascript:`, `data:`, `//host`… stay plain
  text) and no HTML / image path exists at all. The prompt also asks for simple Markdown only.
- **Grounding:** data answers are direct with no disclaimers; `sample` markers are hidden from the model unless the
  admin turns on **Mention unconfirmed flags** (`settings/assistant.mentionUnconfirmed`, default off); invented
  church specifics stay forbidden ("not listed" → `/contact`); unrelated topics still refused. (An interim
  "answer faith questions from general knowledge" rule was replaced by ADR-031 before merge.)

## ADR-031 (PR #21) — Faith questions only from St-Takla.org; 3 questions per device per day; no default chips
- **Source:** the only source for faith / church questions outside the site data is St-Takla.org (admin
  `sourceDomains`). Checked Firebase AI Logic: Grounding with Google Search supports `gemini-3.1-flash-lite`
  (<https://firebase.google.com/docs/ai-logic/grounding-google-search>) but the Gemini Developer API **free tier
  marks it "Not available"** (paid: 5,000 free search requests / month shared across Gemini 3+, then $14 / 1,000,
  1,500 / day cap — <https://ai.google.dev/gemini-api/docs/pricing>), and a grounded result must also render
  Google's Search-suggestions HTML. The URL context tool is free but only reads URLs we pass in — it cannot search a
  site. **Chosen: the fallback** — the model answers only from the site data and replies `[[SOURCE_SEARCH]]` for
  other faith questions; the app shows `faithReplyAr/En` + `https://www.google.com/search?q=site:st-takla.org <q>` +
  `/contact`. Upgrading to Blaze could enable grounding later (filter citations by `web.title` domain — on the
  Developer API `uri` is a vertexaisearch redirect — and show the suggestions widget).
- **Daily limit:** `perDay` (default 3) per device per Africa/Cairo day replaces the per-visit default of 30
  (`perSession` ignored; the rules keep the key as legacy); per-minute limit unchanged. Counter + random 128-bit device
  id in shared_preferences (localStorage on web). **Not a security boundary:** clearing site / app data resets it.
  **No server enforcement:** AI Logic is called directly from the client, so a Firestore `assistantUsage` counter
  could not gate the model call (a modified client skips it, and new device ids are free to mint) — it would only add
  public writes. Real server-side protection = App Check (enforced) + the AI Logic per-user rate limit in the console,
  or a Cloud Function proxy later.
- **Chips:** no suggested questions by default; admin `showSuggestions` (default off) shows only the admin's list.

## ADR-032 (PR #22) — Hero: no address ribbon by default, the verse without a panel

- **Context:** the church asked to remove the brown address pill from the home hero and to show the verse of the day
  without the cream card. Git history: the address was a plain gold line under the title from PR #1 (as the
  fallback of an empty hero subtitle) and became the `TitleRibbon` pill in PR #15 (`a97987c`); the hero verse sat in a
  translucent 8 % white box on the dark maroon hero up to PR #14 and in the cream `WarmPanel` from PR #15 through PR #17
  (`55e2a92`). The typography kept is the fixed verse's from before PR #17 (Ruqaa 20/24 px, height 1.8, centred
  `« »`, reference in `goldText` 13 px bold).
- **Decision:** the hero ribbon shows only the admin's subtitle, or the address when the new
  `settings/features.heroShowAddress` switch is on (default off; rules accept only a bool; saved only once on or
  already stored, like `heroMotion`). The address stays on `/contact`, in the footer and on the map. `HeroVerse` drops
  the `WarmPanel` and sits on a radial `TextScrim` at `verseScrimAlpha = 0.88`; `ThemePalette.verseGrounds` (that scrim
  over black and white frames) joins the palette checks for `ink` and `goldText` at 4.5:1, so every preset (incl. dark
  Holy Week) passes and admin colours are auto-corrected. Because a radial glow fades towards the ends of a wide line
  (Codex review), each verse line is a `HaloText`: a 2.5 px outline of the scene colour under the glyphs plus soft
  shadows, so the ground beside every stroke is the scene colour itself; a pixel test renders it over black and white
  frames for every preset. A blurred solid core under the glow was tried and rejected: it reads as a pale band, i.e.
  the panel the church asked to remove. Daily rotation and the fixed-verse mode are unchanged.

## ADR-033 (PR #23) — Pages trust only loaded data; settings docs prove themselves; fingerprinted icon fonts

- **Context (live admin test, 3 Nov 2026):** (1) a custom category's items stayed on 3 skeleton cards; (2) a cold
  link to `/section/<slug>` or `/page/<slug>` first said «هذه الصفحة غير متاحة حاليًا» and only a reload showed it;
  (3) contact types added in the admin never reached the `/contact` picker (4 defaults only); (4) the PR #18 admin
  menu entries had no icons and the selected entry showed only a tinted label. A diagnostics build on the PR preview
  showed every Firestore listener answering from the local cache first (`fromCache: true`, the custom collections
  empty) and from the server ~1.3 s later; in the test browser the live site also showed the "bundled content" mark,
  i.e. the `settings/church` seeding check had failed there.
- **Root causes:** (1)+(2) `categories`/`entries`/`pages` went through the generic `_col`: every snapshot was
  emitted, so the first, cache-only reading (empty or stale) was taken as the answer, and an unanswered seeding
  check emitted the empty fallback at once → "not available"; nothing bounded the wait for a first reading of a
  query with no cached results, so a stalled server sync left the items list loading forever (the exact stall was
  not reproducible after the test data was deleted). (3) `settings/contact` had no `confirms`: while the seeding
  check could not answer, the guard kept `ContactSettings.defaults` and dropped the live stored list (the rules were
  fine; the emulator tests already cover random ids). (4) Hosting caches fonts 7 days and `flutter build web` writes
  the tree-shaken `MaterialIcons-Regular.otf` under the same name every build, so phones kept an older subset
  without the new glyphs (the live font has them); the nav's coloured `Container` hid the `ListTile` highlight.
- **Decision:** `settleFirst` (hold cache-only readings until the server answers, at most 8 s, then the held reading
  or a cache read; afterwards forward real changes only) + `guardSeeded(fallbackDelay: 13 s)` (deferred while a re-check is in flight) for the three custom
  collections; `confirms: !identical(v, default)` for `settings/features`, `settings/contact`, `settings/assistant`;
  the contact dropdown is re-keyed by its ids; `tool/fingerprint_icon_fonts.py` in CI and deploy; the admin nav is a
  `Material` with one colour scheme (burgundy icons, ink labels, burgundy + gold highlight when selected) and a
  distinct icon per entry. No rules, model or seed change.
- **Not changed:** the built-in sections keep emitting cache readings at once (they have a bundled copy and the
  seed fallback); App Check activation is unchanged (it is not enforced on Firestore).
## ADR-034 (PR #24) — Error tracking with Sentry, privacy first and switchable in /admin

- **Context:** crashes and failed loads on the live site / Android app were invisible (only `debugPrint`). The owner
  created a Sentry project (org `kerollos-0e`, project `church-portal`, **EU** region) and asked for error tracking
  that respects the PDPL on a public church site and, like everything else, can be switched off in `/admin`.
- **Decision:** `sentry_flutter` **10.3.0** (latest on pub.dev, needs Flutter ≥ 3.44 / Dart ≥ 3.12; repo on 3.47.9 /
  3.13.7). `main()` = `ErrorReporting.run(_start)` → `SentryFlutter.init` wrapping the whole start-up.
  - **DSN:** `--dart-define=SENTRY_DSN` wins (empty = off); release builds otherwise use the public project DSN
    constant (`AppConfig.sentryDefaultDsn`) — the agent's GitHub API has **no Actions-variables endpoint**, so a repo
    variable could not be created; a DSN is public by design. Debug / profile builds and tests without the define:
    **off**. CI passes `SENTRY_DSN` only when the repo variable exists.
  - **environment:** `production` (main deploy), `preview` (PR preview builds — kept on so previews are testable),
    `ci` (the CI build, never served), `debug` (local). **release:** `church-portal@<pubspec version>+<sha7>`.
  - **Privacy:** `sendDefaultPii: false`; `beforeSend` removes the user, server name, cookies, request body, headers
    but User-Agent, `extra`, custom contexts, query strings (request URL, `route` tag, http / navigation
    breadcrumbs) and scrubs e-mails / 7+ digit runs from messages, exception values and log breadcrumbs; tap
    (`ui.*`) breadcrumbs dropped; tags limited to `route`, `section`, `source`, `test`. Assistant errors are reported
    as `AssistantFailure` with the question redacted; quota / rate-limit / billing / safety rejections are not
    reported. Contact submit errors are reported as type + scrubbed message, never the form; `permission-denied`
    (usually the server throttle, but also any rules rejection) is tagged `source: permission-denied` (review). **No** Session Replay, screenshots, view hierarchy, release-health
    sessions, client reports, tracing (`tracesSampleRate` null — errors only, keeps us inside the free quota) or
    profiling.
  - **Admin switch:** `settings/features.errorReporting` (bool, default on; rules: bool only; seeded `true`; written
    only once off or stored; never taken from the bundled seed copy on Firestore). `deploy-live` now waits for
    `deploy-rules`, so the rules accept the new field before the app can write it (CodeRabbit). `beforeSend` awaits the switch (≤ 10 s, then the default) and drops everything while
    it is off; switching off also closes the SDK; switching back on applies from the next visit / app start. The
    web Sentry **JS** SDK (loaded by `sentry_flutter` from `browser.sentry-cdn.com`, reports window errors itself)
    gets the same switch + scrubbing via its client `beforeSend` (`sentry_js_gate_web.dart`): a Promise that awaits
    the switch and returns the event rebuilt from its JSON by `scrubEventJson`, fail closed (review: Codex / Seer).
  - Owner-only **Send test error** button in `/admin` (Sections & home page → Error reports).
- **Not done (open tasks):** web source maps and Android obfuscation symbols need a Sentry auth token; Sentry
  project privacy settings (IP storage off, server-side scrubbers) are set in the Sentry UI. No CSP exists in
  `firebase.json`; one added later must allow the Sentry CDN and `*.ingest.de.sentry.io`.
- **Consequence:** native Android crashes go through the Sentry Android SDK (its own handlers, `sendDefaultPii`
  false); a native crash cached on disk may be sent at the next start before the switch is known — acceptable,
  documented.

## ADR-035 (PR #25) — An Arabic `documentation/` folder beside the memory bank, kept current in the same PR

- **Context (4 Nov 2026):** the owner asked (in Arabic) for the memory bank to be brought up to date and for
  documentation "for me or anyone who needs to know how the app works": one explanation per feature.
- **Decision:** a top-level `documentation/` folder written in **Arabic** (simple wording; code identifiers, paths,
  collection / field names stay in English): `README.md` (index), `architecture.md`, **one file per feature**
  (what visitors see, how to control it from `/admin` with the exact labels from the code, how it works, limits) and
  `operations.md` (deploy, add an admin, seed safely, Sentry, common problems). The memory bank stays the English,
  agent-oriented long-term memory with ADRs and history; `documentation/` is the human manual and links back to it.
- **Rule:** every PR that adds / removes / changes a feature, an admin screen or switch, a workflow or an
  operational step updates the matching `documentation/` file in the same PR (AGENTS.md golden rule, `00-README.md`
  update rules, `08-dev-workflow.md` PR process).
- **Alternatives rejected:** translating the memory bank (too long and too technical for the church office, and two
  copies of the same text drift); an English manual (the owner and the church office read Arabic first).

## ADR-036 (PR #25) — Remove the YouTube hero video library; the hero plays only the bundled clip

- **Context (owner request, 4 Nov 2026 07:56 Cairo):** remove the «مكتبة فيديو الواجهة (يوتيوب)» admin card (YouTube
  links, add to the library, active / per-theme selection) and the feature behind it.
- **Decision:** the hero keeps the bundled clip (`hero_clouds.mp4` / `hero_clouds_tall.mp4`), its poster / painting
  fallback and the `heroMotion` switch. Removed: `HeroVideoEditor` and its card, `lib/domain/hero_video.dart`
  (`HeroVideoLibrary`, YouTube parsing), `lib/ui/widgets/hero_youtube*.dart`, `HeroStage.youtubeId`,
  `ActiveTheme.video`, `FeatureSettings.heroVideos`, the `heroVideos` save write, the `heroVideo*` strings and the
  `youtube_player_iframe` dependency.
- **Data and rules:** nothing is deleted from live data. A `heroVideos` map already stored in `settings/features` is
  ignored when read and never written (saves use `mergeFields`, so it stays untouched). `firestore.rules` keeps the key
  allowed and `validHeroVideos` (marked LEGACY) so such documents keep saving; the ADR-026 emulator tests stay as rule
  coverage. Removing the rule is an optional later clean-up once no live document stores the key.
- **Tests:** the hero uses the bundled clip even with a stored library (`test/golden_hour_test.dart`); the Sections &
  home page editor has no video library card and saves never write `heroVideos` (`test/occasion_admin_test.dart`); a
  stored library does not affect the theme in force (`test/occasion_theme_test.dart`).

## ADR-037 (PR #29) — PageSpeed: same hero, less main-thread work, App Check on demand, crawler files

- **Context (4 Nov 2026):** live PageSpeed Insights (Lighthouse 13.6, `main` `b7e5ed2`) scored Performance 56 mobile /
  60 desktop, Best Practices 77, Agentic browsing 2/4. Causes: the hero haze drift + 14 blurred light rays were
  repainted by CanvasKit every frame for as long as the hero was visible (desktop TBT ~22 s, long tasks over the whole
  trace); App Check activated at start-up loaded reCAPTCHA Enterprise (~700 KiB, an iframe, a token exchange that
  logged 403 / `requestStorageAccess` errors) on every public page; a 178 KB seal in the splash; Flutter's line
  breaker calls the deprecated `Intl.v8BreakIterator`; the `**` SPA rewrite answered `/llms.txt`,
  `/.well-known/ard.json` and `*.map` with `index.html`. A first attempt (PR #28, draft ADR-037) froze the ray shimmer
  and dropped the haze drift; the owner closed it unmerged — **the hero must keep its look**.
- **Decision:**
  - **Hero ambient layer on web = DOM + CSS** (`lib/ui/widgets/hero_ambient*.dart`, shared geometry in
    `HeroAmbientSpec`): the haze strip slides with a CSS transform animation; the rays are drawn once per size on a
    few canvases at evenly spaced shimmer phases and crossfaded with CSS opacity animations (`plus-lighter`); where `CanvasRenderingContext2D.filter` is missing (Safari) the static canvases get a CSS
    `blur()` with the same sigma instead (Sentry review). Same
    geometry, colours, cycles (60 s clock, shimmer x8) and theme `cssFilter`; paused off-screen. The animation runs on
    the compositor, so Flutter no longer repaints per frame. Android / tests keep the Flutter painters
    (`heroAmbientInDom == false`).
  - **App Check is lazy:** `bootstrapFirebase` no longer activates it; `ensureAppCheckActivated()` (one shared
    Future) runs on the assistant's `warmUp()` / `generate()`. `FirebaseStatus.appCheckActive` now means "App Check is
    configured for this build" (`selectAppCheckPlan(...).activate`), which still gates the assistant. If activation
    fails later, the assistant shows its normal error instead of being hidden. App Check only guards Firebase AI
    Logic (Firestore is not enforced), so nothing else changes.
  - **Static first paint** in `web/index.html`: the hero poster (`hero_poster(.tall).webp`, preloaded,
    `fetchpriority=high`) + the church name in Lalezar + a small spinner, fading out on `flutter-first-frame`; the
    failure path is unchanged. The splash no longer loads the seal; `seal.png` quantised 178 → 27 KB.
  - **`Intl.v8BreakIterator` shim** (inline script before `flutter_bootstrap.js`) on top of `Intl.Segmenter`
    (UAX #14 subset: spaces, dashes / slashes / ZWSP, CJK, mandatory newlines, never inside a grapheme). Checked
    against the native iterator on 2,157 app / doc strings: 3 differences, all in Markdown / code strings.
  - **Hosting:** rewrite only extension-less paths (`"regex": "^/[^.]*$"`) plus `/section|page/<slug>` and the 7
    item-detail prefixes with any id (dots allowed), so missing files (`/.well-known/*`, `*.map`, probes) are real
    404s; `Cross-Origin-Opener-Policy: same-origin-allow-popups` (the hero `mp4` keeps the default cache: fixed path,
    not fingerprinted).
    `web/llms.txt` (H1, page links from the sitemap). Manifest background `#FBF3E4` (= splash). Web builds in
    `ci.yml` / `deploy.yml` pass `--source-maps`.
- **Ceiling:** the site is a CanvasKit Flutter app: `main.dart.js` (~3 MB) + CanvasKit wasm must download, compile
  and run before the real page paints, so Total Blocking Time and Speed Index stay well above Lighthouse's "green"
  thresholds on the mobile profile (4x CPU throttle) whatever the page does. A green 90+ would need a different
  first-paint architecture (pre-rendered HTML for the public pages, or a non-Flutter landing page) — out of scope.
- **Tests:** `test/pagespeed_test.dart` (ray geometry = old painter formula, phase weights, DOM layer web-only,
  splash poster / name / fade, shim before bootstrap, seal size, llms.txt links ⊂ sitemap, rewrite regex + COOP).
- **Alternatives rejected:** freezing / removing hero motion (PR #28, owner said no); HTML renderer (removed from
  Flutter); dropping App Check (AI Logic enforces it).

## ADR-038 (PR #30) — Seeding proof shared by every stream; sitemap from Firestore at deploy; loading screen until real content

- **Context (4 Nov 2026):** (1) the footer said «تعرض البيانات المحفوظة مع التطبيق» ("Showing bundled content") on
  normal loads while Firestore was working. Reproduced on the live site in headless Chrome (412 × 5000, `/contact`,
  35 s): note present. A diagnostics release build (temporary `print`s in `SeedGate` / `_markFallback`, not
  committed) served locally against production showed the one-shot `settings/church` check (`get()`, 8 s timeout)
  time out at ~9.7 s and later fail with `[cloud_firestore/unavailable] Failed to get document because the client is
  offline`, while the listeners went on to deliver server data (`settings` / `features` switched to live at ~41 s
  in the slow sandbox) — but `contact` stayed on the bundled defaults for good. (2) `sitemap.xml` was static: 7 fixed
  pages, no item detail pages, custom sections or custom pages. (3) The HTML loading screen (ADR-037) faded out on
  Flutter's first frame, before `settings/church` / `settings/features` arrived, so the default layout flashed
  before the real one.
- **Root cause (1):** `guardSeeded` re-checked the seeding marker only when its stream received a *new* value. A
  stream whose live value cannot vouch for itself — a missing optional doc (`settings/contact`,
  `settings/assistant` → identical code defaults) or a legitimately empty collection — gets **exactly one** snapshot
  from Firestore (an unchanged empty result or a "fromCache → synced" change is not re-emitted without metadata
  changes). When the gate could not answer at that moment (cold start: 8 s timeout, or the SDK's transient "client is
  offline"), the stream stayed on the fallback forever, and `servingSeed` (any stream on the seed) kept the note on.
  Meanwhile the `settings/church` listener itself had already proven the marker exists, but that proof was never
  shared with the gate. (The suspected `settleFirst` / `customFallbackDelay` path of ADR-033 is one instance of the
  same class: a held empty custom list could be stranded the same way.)
- **Decision (1):** `SeedGate.markSeeded()` + `whenSeeded`: the `settings/church` live snapshot (when the document
  exists) and any successful check mark the database seeded; every `guardSeeded` stream still unconfirmed then emits
  the live value it holds back (or, with none yet, lets the next one through) and cancels a pending delayed custom
  fallback. A negative / failed read that lands after the proof cannot undo it (`check()` returns the latest state).
  Unchanged: a stream error still falls back with the note (truly bundled), one stream's non-empty data still never
  vouches for another collection, and a known-unseeded database keeps the seed until the marker appears (now picked
  up from the listener too, without waiting for another value).
- **Decision (2):** the Spark plan has no Cloud Functions, so the sitemap is generated in `deploy.yml` → `build`
  (push and same-repo PRs) after `flutter build web`: the existing `firebase-credentials` action (step
  `continue-on-error`), then `tool/build_sitemap.sh` = `tool/export_public_content.js` (firebase-admin, **`get()`
  only — never writes**) + `dart run tool/gen_sitemap.dart` (pure rules in `lib/domain/sitemap.dart`) + an XML
  check (urlset namespace, home present, same origin, no duplicates, ≤ 50,000) → `build/web/sitemap.xml`; the key is
  removed right after. Any failure prints a `::warning::` and keeps the static `web/sitemap.xml` (now marked as the
  fallback; a test keeps it equal to the fixed pages the seed leaves on). Rules = the app's own indexing: fixed
  pages by `routeEnabled` (like `FeatureGate`); `/section/<slug>` = `publicCategories` and `/page/<slug>` =
  `publicPages` while `customSections` / `customPages` are on — a page with `showInNav: false` is still listed
  because `CustomPageView` is indexable whenever the page exists (there is no separate noindex field; hidden /
  unusable / duplicate slugs are not listed); item pages for the 7 `DetailKind` prefixes when
  `routeEnabled(path)` and `detailItemOpens` (listed — clinics also active —, `detailsEnabled` not false, priests by
  the section matching their status). `entries` have no page of their own. `detailItemId` / `detailItemDetails` /
  `detailItemListed` / `detailItemOpens` moved from `item_detail_page.dart` to `lib/domain/item_detail.dart` so the
  page and the sitemap share one rule. `robots.txt` unchanged (points to `/sitemap.xml`).
- **Decision (3):** `web/index.html` keeps the loading screen (now `z-index` above the Flutter view) until the app
  dispatches `app-content-ready` (`lib/core/content_ready.dart`), sent two frames after `contentReadyProvider` =
  `firstContentArrived`: settings/church, settings/features (`featuresReadyProvider`) and the hero's verse list have
  a value or failed (live or fallback). Cap: 9 s after `flutter-first-frame`; the 30 s failure path is unchanged.
  The hero `<video>` gets its `src` and the CSS ambient layer (haze strip + ray canvases) is built only at
  `ContentReady.whenIdle` (after the signal + the 0.5 s fade + `requestIdleCallback`, ≤ 2 s; Safari 600 ms; hard cap
  12 s); the haze fades in (0.8 s) like the rays and the video already did. The poster under them stays the LCP
  element; final hero look unchanged.
- **Live-check follow-ups (same PR, second commit; live check of 4 Nov 2026 after PR #29):**
  - **(a) Footer quick link «العيادات» during load:** the footer filtered its links with `routeEnabled` only, and
    until `settings/features` arrives the defaults are "everything on", so «العيادات» (switched off live) showed and
    a click landed on the section-off page. The footer now hides `/clinics` until `featuresReadyProvider`, the
    same rule as the Services menu (`app_shell.dart`).
  - **(b) Half-empty screen after the splash** (app bar, empty logo circle, `FeatureGate` spinner, footer for
    3–5 s): that is exactly the "waiting for `settings/features`" state, and `contentReadyProvider` requires
    settings/church **and** `featuresReadyProvider`, so the loading screen now covers it (the 9 s cap only applies if
    even the seed fallback has not arrived, which the 8 s seeding check bounds).
  - **(c) Missing `/section/x`, `/page/x`, `/about/priests/<bad-id>` on skeletons for 15–24 s:** `guardSeeded`
    subscribed to the live query only *after* the seeding check (≤ 8 s), and the custom fallback delay (13 s)
    started only after that check failed. Now the live query starts at once (its values wait in `onData` for the
    gate's answer), `SeedGate.check()` also answers as soon as `whenSeeded` fires, and the 13 s custom delay counts
    from the subscription. Worst case for a missing custom page: ~13 s on a stalled connection (was 21 s+), and
    `max(query, check)` (usually 1–2 s) on a normal one; a detail page in a built-in collection: ≤ 8 s. ADR-033
    cache-first holds: the delay is still longer than `customPatience` + `customCacheRead` (+1 s) measured from the
    same moment the `settleFirst` query starts, the fallback still never fires before the gate has answered "not
    seeded / could not tell", and on a seeded database custom content never falls back to the empty list.
  - **(d) English leftovers:** images have one admin `alt` (usually Arabic); on the English site an Arabic-only alt
    now gives way to the item's English name (`imageAltFor`, `lib/domain/media.dart`; used by `ItemImage`,
    `HaloAvatar`, `FittedCover`). `TimeRangeText` shows Latin digits only in English; Arabic keeps both digit
    systems (Arabic first, Latin underneath, LTR) — the "both digit systems" rule is for Arabic readers.
  - **Not changed (owner's data / decisions):** the church name in `settings/church.nameAr` («الابيض» instead of
    «الأسود», saved via /admin) is for the owner to correct in /admin. `/main.dart.js.map` is public (built with
    `--source-maps` for PageSpeed diagnostics; exposes the Dart sources, no secrets) — owner to decide. `/contact`
    logs Google Maps `InvalidKeyMapError` (the Maps embed key / referrer setup), not fixed here.
  - **Review follow-ups (CodeRabbit):** `tool/build_sitemap.sh` export timeout 330 s (10 sequential reads × 30 s),
    sitemap copied to `$OUT.tmp` then renamed (a failed copy never leaves a truncated file); the manual deploy
    command runs the sitemap step; the service-account secret is listed as used by `build`.
- **Tests:** `test/content_guard_test.dart` (group "footer bundled content note": empty collection, missing optional
  doc, proof during an in-flight re-check, late negative read, known-unseeded → seeded, delayed custom fallback
  cancelled, working check never marks bundled), `test/sitemap_test.dart` (switches, 7 prefixes, priests by status,
  custom sections / pages incl. nav-hidden, export parsing with seed features, XML escaping, static fallback = seed,
  robots), `test/content_ready_test.dart`, `test/pagespeed_test.dart` (loading screen waits for the event, cap,
  z-index).
- **Alternatives rejected:** a longer gate timeout (only moves the race); treating any non-empty collection as proof
  (rejected in ADR-033: it vouches for nothing else); `includeMetadataChanges` on every built-in collection (more
  events and re-checks for every page, still no proof for a missing doc); a scheduled sitemap job (needs Blaze /
  Functions or another secret-bearing workflow); hiding the loading screen on a fixed delay.

## ADR-039 (PR #31) — Coptic calendar engine, liturgical day at 18:00, Coptic date strip

- **Context (owner plan «التقرير المعماري وخارطة تطوير بوابة الكنيسة للمناسبات الاستثنائية», `docs/holy-week-and-revivals-roadmap.md`,
  4 Nov 2026):** the portal changed day at civil midnight, but the Church's day starts the evening before («بصخة
  ليلة الثلاثاء» is prayed on Monday evening). No Coptic date was shown anywhere.
- **Decision:** `lib/domain/coptic_calendar.dart` (pure Dart, offline): Gregorian ↔ Coptic through the Julian Day
  Number (1 Tout 1 AM = JDN 1825030; Coptic leap year when `year % 4 == 3`, so 1 Tout 1744 = 12 Sep 2027), Arabic /
  English month names, «الأربعاء ٢٥ بابه ١٧٤٣ ش». `liturgicalDayAt(instant, mode:, fixedAt:)`: **default a fixed
  18:00** (owner, 4 Nov 2026: "keep the plan exactly"), admin-editable (`settings/features.dayStartsAt`, `00:00` =
  civil midnight); optional mode `sunset` = the actual sunset at the **church in Alexandria** (`lib/domain/sun.dart`,
  NOAA general solar position equations, church coordinates 31.260138 N, 30.01129 E, or `settings/church.lat/lng`;
  checked within 2 min of timeanddate.com). Africa/Cairo (Egypt's single time zone) is only the clock; **no time-zone
  label is shown anywhere in the UI** (owner) — the existing «توقيت القاهرة» / "Cairo time" admin labels and hints were
  removed.
- Uses: `CopticDateStrip` (top of every page by default; `copticStrip` = all / home / off) shows the liturgical day
  («ليلة الخميس …» after the start); the **verse of the day** rotates on the liturgical day
  (`resolveDailyVerse(..., day:)`); the next-service card labels a service after the start «الليلة • ليلة الخميس»
  (`TodaySettings.isEveService`). `computeNextMass` itself is unchanged (real instants). Movable feasts reuse
  `orthodoxEaster` (the Holy Week theme's computus).
- **Footer note (PR #30 left-over):** `SteadySeedNote` shows «تعرض البيانات المحفوظة مع التطبيق» only once
  `servingSeed` has stayed true for 4 s on live Firestore (at once in seed mode), so a stream briefly on the seed
  during a cold start (`/page/<slug>`) no longer flashes it.
- Tests: `test/coptic_calendar_test.dart` (known dates from api.katameros.app: 1 Tout 1743 = 11 Sep 2026, 29 Kiahk
  1743 = 7 Jan 2027, 28 Kiahk 1744 = 7 Jan 2028, 1 Tout 1744 = 12 Sep 2027; 1900–2100 round trip; cut-over incl.
  EEST; sunsets), `test/today_widgets_test.dart`.

## ADR-040 (PR #31) — Top event of the day (church event > Katameros > computed feasts) and the live banner, at no Firestore cost

- **Owner constraints (4 Nov 2026):** Spark plan (no Cloud Functions, no paid proxy); keep Firebase free quotas: no new
  always-on listeners, no Firestore reads per visitor for the Katameros data (a static Hosting JSON), new settings
  inside existing settings docs, no polling. The Katameros fetch runs in a **scheduled GitHub Action**, not in the
  client (owner reversed a direct-call idea; for the record the API is MIT open source, answers
  `Access-Control-Allow-Origin: *` and documents no rate limit).
- **Hierarchy (`resolveTopEvent`, `lib/domain/today.dart`):** (1) an admin church event covering today and not yet
  ended (on the eve, after the day's start: one covering the liturgical day) — title, times, speaker, topic, note,
  link; (2) otherwise, when `commemoration` is on, the **Katameros** feast title / Synaxarium entries of the
  liturgical day; (3) otherwise the **computed feast list** (`lib/domain/coptic_feasts.dart`: Nayrouz, Cross,
  Nativity on 7 Jan, Theophany 11 Touba, Annunciation 29 Baramhat, Entry into Egypt, Transfiguration, Assumption,
  fasts' first days, and from Easter: Nineveh, Great Lent, Lazarus Saturday, Palm Sunday, Holy Week days, Easter,
  Thomas Sunday, Ascension, Pentecost, Apostles' fast). `topEvent` off hides the card.
- **Storage:** all in **`settings/features`** (already streamed on every visit): `copticStrip`, `dayStartMode`,
  `dayStartsAt`, `topEvent`, `commemoration`, `liveEnabled`, `liveUrl`, `liveLabelAr/En`, `liveEndsAt`, and
  `dayEvents` (≤ 20 strings, `date␟endDate␟start␟end␟titleAr␟titleEn␟speakerAr␟speakerEn␟topicAr␟topicEn␟noteAr␟noteEn␟link`,
  one regex each in the rules — `validDayEvent`). Parsed into `FeatureSettings.today` / `.dayEvents`, **never written
  by `FeatureSettings.toMap()`**; edited in /admin → **«اليوم والبث المباشر» / Today & live stream** (generic
  `DocDef` form on `settings/features`, which writes only the keys it changed). No new collection, no new listener.
- **Katameros → `/data/today.json`:** `tool/fetch_synaxarium.js` (Node 22, built-ins only) fetches
  `https://api.katameros.app/readings/gregorian/dd-MM-yyyy?languageId=3|2` for the Cairo days yesterday … +7 (18 small
  GETs), keeps the feast title, Coptic date and Synaxarium titles (≈ 3 KB). `.github/workflows/synaxarium.yml` runs it
  at 16:10 and 22:10 UTC (18:10 / 00:10 in winter, 19:10 / 01:10 in summer, local) and `tool/publish_hosting_file.js`
  publishes the one file **without rebuilding**: Hosting REST API v1beta1 — clone the live version (excluding the
  file), `populateFiles` + upload the gzip, finalize, release. Concurrency group `hosting-live` is shared with
  `deploy.yml`'s `deploy-live`, so a clone can never roll back a fresh deploy; `deploy.yml`'s build also writes the
  file (fallback: the live copy); only when both Katameros and the live site fail is the file missing from that
  release, until the next scheduled publish (visitors keep their stored copy / the computed feast list). The fetcher
  retries each request once, writes a day only with both languages, and keeps the previously published entry for a
  day that still fails (PR #31 review). Each publish adds a Hosting version (files are
  de-duplicated); the owner can cap kept versions in the Firebase console (Hosting → release storage settings).
- **Client (`lib/data/synaxarium_source.dart`):** after the page is complete and idle (`ContentReady.whenIdle`), one
  same-origin GET of `/data/today.json` **only when the copy stored on the device (shared_preferences / localStorage)
  has no entry for the liturgical day** — so about one ~3 KB request per device per week at most (the file covers 8
  days), none in seed mode. Any failure → stored copy → computed feasts. Credit line «المصدر: القطمارس (katameros.app)».
- **Live banner (`LiveStreamBanner`):** red bar at the top of every page while `liveEnabled` and an http(s)
  `liveUrl` (YouTube / Facebook / any) and before `liveEndsAt`; pulsing dot (static under reduced motion); one tap
  opens the stream; default text «بث مباشر الآن من الكنيسة», admin text optional. Re-evaluated by the existing 30 s
  clock (`nowProvider`), so the automatic switch-off needs no polling.
- **Cost per visit (Firestore):** reads **+0**, listeners **+0**, writes **+0** (everything rides on the existing
  `settings/features` listener); an admin save of the Today screen = 1 write. Hosting: ≤ 1 × ~3 KB GET per device
  per day (usually per week). GitHub Actions: 2 short runs a day.
- Rules: `validFeatures` allow-list + checks (`copticStrip` ∈ all/home/off, `dayStartMode` ∈ fixed/sunset,
  `dayStartsAt` HH:mm, bools, `liveUrl` http(s) ≤ 500, labels ≤ 120, `liveEndsAt` timestamp/null, `dayEvents` ≤ 20
  valid strings) — `tool/rules_test` "ADR-039 / ADR-040" group.

## ADR-041 (PR #32) — Programme details on services, meetings and seasons: speaker, topic, choir, venue, audience, Drive PDF link

- **Context (owner plan §2.2, §2.3, §2.5, `docs/holy-week-and-revivals-roadmap.md`):** revival nights need the
  preacher, sermon title and choir; Holy Week prayers run in parallel in several halls (main church, lower hall,
  services building) for different age groups; the Pascha booklet / speakers list should be one tap away.
- **Decision:** one shared, all-optional field set `ProgramInfo` (`lib/domain/program.dart`) on `Liturgy`, `Meeting`
  and `Season`: `speakerAr/En` (≤ 200), `topicAr/En` (≤ 300), `choirAr/En` (≤ 200), `venue` / `audience` (keys of
  admin lists), `attachmentUrl` (**https link only — Google Drive or any page; nothing is uploaded, owner 4 Nov 2026**)
  + `attachmentLabelAr/En` (≤ 80). Missing keys = nothing shown, so existing cards are unchanged.
- **Venues / audiences** are admin lists in `settings/features.venues` / `.audiences` (≤ 12 strings each,
  `key␟labelAr␟labelEn`; missing / empty = defaults الكنيسة الكبرى / القاعة السفلية / مبنى الخدمات and عام / شباب /
  أطفال), edited in the new /admin screen «إعدادات المواسم» / "Season settings" (generic form, writes only changed
  keys). No new document, collection or listener: `settings/features` is already streamed. Items store the KEY, so a
  renamed hall updates everywhere.
  A key missing from the admin list still resolves through the built-in defaults (`venue()` / `audience()` fall back,
  `ProgramOptions.withUsed` keeps it in chips and in the item's dropdown), so items saved with `main` / `youth` keep
  their label after the admin replaces the list (Sentry review on PR #32).
- **Parallel prayers:** `parallelServices()` (`lib/domain/schedule.dart`) — same date (or weekday), overlapping times
  (no end = one minute), different venue (or free-text place) — adds «وفي نفس الوقت: القاعة السفلية (شباب)» to each
  card — on every list of /mass-schedule (season services, additive revivals, one-off special services and the
  regular weekday tabs; Codex review on PR #32); the seasonal lists get audience filter chips when two or more
  audiences are used (a service without an audience is for everyone). The chips live in the seasonal view only, so
  switching views clears the filter (Sentry review on PR #32), and a chosen audience applies only while its chip is
  shown; a service with no audience or an unknown audience key shows under every chip (`audienceMatches`, Sentry
  review on PR #32). CodeRabbit round on PR #32: one parallel map per view (services of two seasons can overlap); a venue key and
  its own Arabic name typed as free text are the same place (`parallelServices(list, opts)` keys venues by label);
  English-only places compare with English-only places; an end at or before the start crosses midnight (as
  `_occurrence`); the next-service card shows the line too, from that day's real occurrences (`parallelOccurrences`, so a suppressed or out-of-season service is never named — Sentry); an unknown venue key falls back to the free-text place.
  Admin: a repeated venue / audience key is refused on the later row (`FieldDef.rowUniqueKey`, `validateRowUnique`,
  error `duplicateKey`); the programme pill counts a chosen venue / audience. Rules: `attachmentUrl` path up to 500
  characters with an overall 500 cap, no whitespace (tab / newline) in host or path.
- **UI:** `ProgramDetails` widget (venue / audience pills, speaker / topic / choir lines, PDF button) on the liturgy
  card, the next-service card, the season header on /mass-schedule, the meeting card; meeting detail pages list them
  as facts. Admin: a collapsible «البرنامج: المتكلم والمكان والفئة وملف PDF» group (`FieldGroup.program`) on the
  three collections, with run-time venue / audience dropdowns.
- **Rules:** `programKeys()` added to the three allow-lists; `validProgram(d, changed)` checks all eleven on ONE
  joined string (one regex) only when one changes; `ownFieldsUnchanged` accepts programme-only meeting edits;
  `validProgramOptions` checks each list with one `join` + regex. Worst case (meeting with full detail page + every
  programme key) stays under the 1,000-expression cap (emulator group "ADR-041").
- Firebase cost per visit: +0 reads, +0 listeners. Tests: `test/program_test.dart`, rules group "ADR-041".

## ADR-042 (PR #33) — Season presets: one reversible «تجهيز الموسم» action, season verse sets, assistant season limit and topics, hero v2

- **Context (owner plan §2.6, §3, §4 SOP; `docs/holy-week-and-revivals-roadmap.md` gap 6):** before Holy Week the
  owner flips five or six switches by hand (weekly schedule replaced, meetings and clinics hidden, calm hero, no
  wedding bookings, live link, booklet) and must remember to flip them all back; the assistant's 3 questions a day run
  out at once in busy seasons and it offered sections that were switched off; "verse of the day" ignored the season.
- **Decision — season preset (`lib/domain/season_preset.dart`, /admin «تجهيز الموسم» `SeasonPresetScreen`):** pick a
  season, tick up to 7 options (`replaceRegular`, `hideMeetings`, `hideClinics`, `heroMotionOff`, `weddingOff`,
  `live`, `pdf`; defaults per season kind — Holy Week ticks the first five, Pascha / Nativity only `replaceRegular`,
  revivals none), confirm a dialog that lists every change. `planApply` writes the changes AND the values they replace
  into `settings/features.seasonPreset` `{seasonId, seasonKey, appliedAt, endsAt, options, previous}` and activates the
  season; «استرجاع الإعدادات السابقة» (`planRestore`, confirmed) writes `previous` back and clears the preset. Each is
  ONE batched write (`AdminBackend.saveDocs`) of `settings/features` + `seasons/{id}` (a deleted season is never
  recreated). `sections` is written whole (validSections), from the switches read just before.
- **Auto-revert at the season end without a write or a Cloud Function:** `FeatureSettings.effectiveAt(instant)` gives
  visitors the `previous` values of the switches the preset changed once `endsAt` has passed; `featuresProvider`
  watches the clock through a bool, so it rebuilds once at the end. The live link already stops at `liveEndsAt` =
  season end, and the season stops by its own dates. The stored values change only when the admin presses restore
  (the screen says the season is over and visitors already see the normal site). A season without an end date never
  reverts on its own (the screen warns).
- **Wedding switch:** `settings/features.weddingBookingOff` hides the `wedding` subtype of booking categories on the
  contact form and in the assistant's contact context (`ContactSettings.withoutWedding`); condolences stay. A booking
  category whose only choice was the wedding is hidden while the switch is on, so an unspecified hall booking can't be
  sent instead (Codex review on PR #33).
- **Season verse sets (`lib/domain/season_verses.dart`):** `settings/features.seasonVerses` (≤ 40 rows
  `seasonKey␟textAr␟refAr`, edited in «إعدادات المواسم»). While a season with verses is active (the latest-starting
  one when several), the home verse rotates through its set by liturgical day; a fixed admin verse still wins; no set
  = the general list. The home verse reads the seasons stream only when sets exist (the next-service card already
  opens it).
- **Assistant:** `perDaySeason` in `settings/assistant` (1–100, default 6) applies while an exceptional season is
  active (`holy_week`, `pascha`, `nativity`, `revival_maximus`, `revival_moses`; not `summer`) via
  `withSeasonLimit` (a season never lowers a higher ordinary `perDay` — Sentry review on PR #33); allowed-topic lines (defaults and the admin's) are dropped when a section group they name is
  all off (`topicSectionWords` / `topicsFor`; history and milestones are separate groups, so «history and
  milestones» goes when either is off — Codex review on PR #33); the prompt names switched-off sections ("do not offer") and the current season
  first ("use that season's schedule"); the answer cache key uses the filtered topics.
- **Hero v2:** the owner-approved Gemini clip as muted 9 s loops whose last second cross-fades into the first (no
  seam): `hero_clouds.mp4` 1280×720 (≈ 241 KB, was 308 KB), `hero_clouds_tall.mp4` 432×768 (≈ 117 KB); posters are the
  first frames (`hero_poster.webp` 1280×720, `hero_poster_tall.webp` 432×768; `web/index.html` reserves 432×768); stills
  `hero_wide*` / `hero_tall` regraded to match. Faststart (moov before mdat), no audio track.
- **Rules:** `validFeatures` allows `seasonVerses` (`validSeasonVerses`: one `join` + regex), `seasonPreset`
  (`validSeasonPreset`: key lists, timestamps, bools, the four strings checked as one joined string) and
  `weddingBookingOff` (bool); `validAssistant` allows `perDaySeason` 1–100. Emulator group "ADR-042" (apply / restore
  batch, bad presets, verse rows, limit range).
- **Cost:** visitors +0 reads, +0 listeners in the default layout (three more keys in the already-streamed
  `settings/features`; the seasons stream is already open on home for the next-service card and on /ask). Exception
  (CodeRabbit review on PR #33): while season verses exist and the next-service card is hidden (or the schedule is
  off), the home verse opens the seasons listener itself (+1 listener, ≈ 6 docs). Admin screen: 2 listeners while
  open (`seasons` ≈ 6 docs + 1 doc). Apply = 1 transaction (2 document reads + 2 writes) that re-plans from the
  current documents, so a switch saved meanwhile by another admin is kept, a preset applied meanwhile is never
  overwritten and a season deleted meanwhile is not recreated; restore = 1 transaction (2 reads + ≤ 2 writes);
  auto-revert = 0 writes. Admin screen review fixes: an ended season can't be applied (its `active` would stay on), the
  live link is cleared when another season is picked, links over 500 characters are refused before the dialog, and a
  load error is shown instead of a spinner. The home verse waits for the seasons while season verses exist (no general
  verse flash); /ask waits up to 5 s for the seasons before the daily-limit check. The preset keeps the season end it
  was applied with (visitors need no seasons listener for the auto-revert); when the admin later moves the season's
  end, the applied card says so and «نقل الرجوع التلقائي إلى النهاية الجديدة» moves `seasonPreset.endsAt` (and the
  live end the preset set) in one transaction (`planSyncEnd`, Sentry review on PR #33). After the end, the switches
  the preset covered follow the preset's previous values until «استرجاع» (by design: the screen says so). Hero video bytes −67 KB on
  tablets / desktops, +5 KB on phones.
- Tests: `test/season_preset_test.dart` (preset domain, auto-revert, verse sets, assistant limit / topics / prompt,
  wedding switch, admin screen apply / restore / validation / deleted season, poster sizes vs `index.html`, video
  duration / faststart / no audio / byte budgets), rules group "ADR-042".

## ADR-043 (PR #37) — Occasion sub-themes follow the church season; no violet anywhere; Holy Week simulation fixes

- **Context (Holy Week simulation, 4 Nov 2026, `work/sim-holy-week/report.md`):** the screenshots showed violet
  where no theme asked for it. Cause: widgets that read `Theme.of(context).colorScheme.primary` / containers instead of
  the palette, so Material 3's seeded tones (and the default violet scheme of a bare `MaterialApp`) leaked through;
  the fasts palette itself was violet (`#4A235A`) and so was the `purple` accent preset. The theme also never followed
  the season documents: Holy Week turned dark only on the computed Coptic Easter dates or an admin range, so an
  off-date Holy Week (or a fast / Marian season) kept the normal theme. The simulation also found B1 (next-service
  card skipped Holy Week prayers stored as `other`), B2 (dangling «—» in the "happening now" line), B3 (no venue /
  audience in the assistant's service lines), B4 (the seed's undated Holy Week templates mixed into an owner's dated
  Holy Week), B5 (two seasons with the same name in the preset picker) and the `kids` / `children` audience key.
- **Decision — palettes (`ThemePresets.palettes`, `lib/domain/occasion_theme.dart`):** Holy Week = black cloth
  `#0C0B0A`, charcoal `#1A1817` panels, ashen-silver `#C8C2BA` accent, ash-white ink, crimson `#7A1016` on silver and
  `#E07468` script on black, the gold dimmed to ashen parchment (`#C9BCA6`) — no gold, no violet. Fasts = ash
  `#F0EEEA` / stone `#E4E0D8` with a deep oxblood-umber `#4F2420` accent and oxblood `#7A2621` script. The legacy
  `purple` key stays valid in stored documents and the rules but reads as the same oxblood accent and is hidden from
  the admin pickers (`ThemePresets.pickable`). Golden hour, Resurrection, Nativity, Epiphany, Marian, navy / green /
  brown unchanged.
- **Every widget reads palette roles:** `context.pal` gained the scene accents (`SceneAccents.of(key, palette)`:
  ornament, bar / barDeep / onBar / onBarAccent / barEdge for title bands and filled buttons, ribbon, sepia, halo,
  notice, alert, success, live, cross, shadow tint), and `buildTheme` fills **every** Material scheme role (containers,
  tertiary, surface tints…) from the palette, so a stray Material default can't drift to violet. A test bans
  `Color(0x…)`, `Colors.*` and `AppColors.*` in `lib/ui` outside marked exemptions and scans each preset's scheme for
  violet hues.
- **The theme follows the active season (`occasions.followSeason`, default on; `occasions.seasonThemes`):** each
  season key maps to a preset or `none` (defaults: holy_week → holyWeek, pascha → resurrection, nativity → nativity,
  epiphany → epiphany, marian → marian, fast → fasting; revivals and summer → none). Only differences from the
  defaults are stored. **Precedence** (`OccasionConfig.resolve`): an admin range (with `auto`) > the active season's
  theme (with `followSeason`; when several are active the first in `SeasonThemes.seasonKeys` order wins — Holy Week
  over a fast, a feast over a revival) > the Coptic Easter dates (with `auto` + `easter`) > the selected theme. The
  admin «ثيم الموقع والمناسبات» card shows «الثيم يتبع الموسم الكنسي الجاري» and the «ثيم كل موسم» rows; the "in force
  today" line names the source «حسب الموسم الكنسي الجاري». New season keys `epiphany`, `marian`, `fast` (season form,
  services, verse sets, preset; rules lists).
- **Season preset (ADR-042) item «ثيم الموسم»:** an 8th option that sets `theme` to the season key's theme and keeps the
  old value in `previous.theme` (restore / auto-revert give it back). Offered only for a key that brings a theme and
  ticked by default only when `followSeason` is off (with it on the theme already follows the season; the hint says
  so). The preset now also stores the season's `startsAt`, so until the seasons list has loaded the theme can follow
  the applied preset's season from the first paint (`activeSeasonKeysProvider`).
- **Holy Week fixes:** B1 — while a season that replaces the regular schedule is active, every service of that season
  counts for the next-service card whatever its type, and the card is titled «الصلاة القادمة» (`computeNextMass`).
  B2 — "happening now" uses the free-text place, else the venue's name, and drops the dash when neither
  (`serviceWithPlace`). B3 — the assistant's service lines carry venue and audience names. **B4 handled narrowly
  (deviation from the report's suggestion):** the report suggested ignoring every undated seasonal service once a
  season has any dated one. We drop an undated (weekday) service only **on the days** where a schedule-replacing season
  has dated services of its own (`seasonHasDatedServicesOn`; season lists via `liturgyInSeason`), because the seed's
  Holy Week 2027 is templates only and a partly-entered programme would otherwise lose its other days; additive
  seasons (revivals) keep their nightly services on a dated feast. So the templates of weekdays the owner has not
  entered yet still show (marked «بيانات تجريبية») until he hides them or enters those days. B5 — season names in the
  preset picker carry the year. Audience alias: `kids` and `children` share one label, chip and filter.
- **Rules:** `validOccasions` allows `followSeason` (bool) and `seasonThemes` (season keys → theme keys or `none`),
  `validSeasonPreset` allows `startsAt`, the `theme` option (≤ 8 options, no duplicates) and `previous.theme`; the season
  key lists add `epiphany`, `marian`, `fast`. **Expression budget:** the new checks pushed the ADR-025 "twelve new
  slots in one write" case past Firestore's 1,000-expression limit. Fix: all slot shapes are checked by ONE regex over
  the joined schedule values (with a split count that refuses a value carrying the separator); per changed slot only
  start ≤ end remains; `seasonThemes` is checked only when present and changed, its values as one joined regex.
  Twelve new slots plus a full season map now fit one write (emulator test). Emulator group "ADR-043".
- **Cost (seasons listener):** the theme sits at the app root, so with `followSeason` on (the default) every visit now
  holds the `seasons` listener for its whole length (+1 listener, ≈ 5–8 small docs, re-sent only when a season doc
  changes). Home, /mass-schedule and /ask already held it (next-service card, assistant), so the increase is on the
  other pages and on visits that never open home. While it loads, the theme follows `settings/features.seasonPreset`
  (already streamed: +0). Switching «الثيم يتبع الموسم» off removes the listener from pages that did not hold it.
  Otherwise +0 reads: two more keys in the already-streamed `settings/features`.
- **Review fixes (Sentry on PR #37):** selected chips get a stronger edge (Holy Week's crimson `barEdge`, else the
  ornament, 1.6 px) because on dark scenes the band colour alone was close to the unselected surface; after the
  season end a preset whose previous theme was empty gives visitors the default theme, as «استرجاع» writes it.
- Tests: `test/occasion_subthemes_test.dart` (palettes, no violet in any scheme, no hard-coded colours in `lib/ui`,
  precedence, season map, legacy `purple`, preset theme item / restore / auto-revert, provider fallback to the preset),
  `test/holy_week_fixes_test.dart` (B1–B5, alias), rules group "ADR-043". Before / after renders of Holy Week, fasting,
  golden hour, resurrection and nativity at 390 px Arabic were checked by eye (no violet pixels after).

## ADR-044 (PR #35) — Liturgical web loading screen and a top utility bar (Coptic date + live badge) on the palette

(PR #35 first called itself ADR-043; PR #37 merged first with that number, so this is ADR-044.)

- **Context:**
  1. The ADR-037 first paint (a static copy of the hero: poster + church name + spinner) did not read as a church
     loading screen, and the owner wanted a calmer, liturgical identity while Flutter and the first Firestore data load.
  2. The Coptic date strip (ADR-039) sat inside the body column under the app bar and crowded the home hero title.
  3. While the church streams, visitors should see a small, persistent live indicator on every page.
  4. ADR-043 (PR #37) requires every UI colour to come from the occasion palette (test bans hard-coded colours in
     `lib/ui`), so Holy Week turns the whole shell charcoal.
- **Decision:**
  1. **Loading screen (`web/index.html`):** cream `#FBF3E4` (= `manifest.json` `background_color`), the parish seal
     (`assets/assets/branding/seal.png` — the same 27 KB file `ChurchSeal` loads, so it is downloaded once; decorative
     `alt=""` because the name follows), church name in Lalezar maroon `#6E1C1C`, a 220×4 px gold track with a shimmer
     bar. Pulse and shimmer animate `transform` only, the final fade `opacity` (both composited); a static drop-shadow. A visually hidden `role="status"`
     «جارٍ التحميل…» keeps the loading announcement; `splashFailed()` replaces the track with the reload message.
     Hero posters stay preloaded (and referenced by a hidden `<img>`) so the Flutter hero paints from cache. Dismissal
     unchanged (ADR-038: `app-content-ready`, ≤ 9 s after the first frame), 0.6 s fade, then removed; reduced motion
     stops both animations. The static HTML cannot know the occasion theme (cream on every theme).
  2. **Top utility bar (`TopUtilityBar` in `today_widgets.dart`, alias `CopticDateStrip`):** above the `AppBar` inside
     the shell's `PreferredSize`; title-band roles from the palette (`barGradient`, `onBar`, `onBarAccent`,
     `barEdge` / `ornamentLine`); 32 px at 100 % text, grows to 44 px with text capped at 1.6× (`heightFor`) instead
     of clipping; the date is `Expanded` and the live badge keeps its own width (≤ 150 px, ellipsis) — Sentry review.
     Live badge (`topBarLiveBadge`): theme `live` / `onLive`, 7 px pulse dot, admin live label or «مباشر» / "Live"
     (new l10n `liveBadge`), tap opens the stream. The bar shows when the date is shown on this page
     (`copticStrip`) or while live.
  3. **AppShell:** strip removed from the body column; the status-bar inset above the bar is `pal.bar`; the seal tab
     moves down by the bar height; the shell watches the clock via `nowProvider.select(liveBadgeOn)` so it rebuilds
     only when the bar appears / disappears. `LiveStreamBanner` stays under the app bar on every page.
  5. **Live on Home vs other pages (owner decision, 5 Nov):** on Home (`/`) only the red `LiveStreamBanner` (with its
     «شاهد البث» button) shows; the top-bar badge hides there while the banner shows. Every other page shows the badge
     (plus the banner). The badge is a button for touch, keyboard (focusable `InkWell`, Enter / Space) and screen
     readers (label «<live label> — شاهد البث», tap action) and opens `liveUrl` exactly like the banner.
     `TodaySettings.liveBadgeOn(now, location)` = `liveOn(now) && !(liveBadgeHideOnHome && location == '/')`, used by
     both `TopUtilityBar` and `AppShell` (no empty bar on Home when the date is off). Admin switch in «اليوم والبث
     المباشر»: «إخفاء شارة البث في الرئيسية عند ظهور الشريط» = `settings/features.liveBadgeHideOnHome` (bool, missing =
     on; off = Home shows both). Rules: the key is allowed and checked with `optBool` inside the existing live gate
     (`changed.hasAny([... 'liveBadgeHideOnHome'])`), +2 expressions only when a live key changes. Budget check found a
     latent limit (already on main): 20 church events with end dates plus any other changed Today key in **one** write
     exceed the 1,000 expressions, so the editor's save would fail. Fix: `dayEvents` joins `separatelySavedKeys`
     (`splitSavePayload`: the other Today keys first, then the events in their own write); the emulator test saves the
     whole form that way and shows the single write fails.
  4. **Review fixes on merge (5 Nov):** hard-coded `#3B0A0A` / gold / white / red replaced by palette roles (would
     fail ADR-043's test and stay burgundy on Holy Week); `HaloText` outline back to 2.5 px (the 3.0 px change worked
     around a Holy Week contrast failure that ADR-043's palette already fixes; tests pass at 2.5); the
     `SynaxariumSource` fallback to the live URL and the seed-mode fetch on web were removed — the live site sends no
     `Access-Control-Allow-Origin`, so a browser on another origin can never read it (and preview channels already
     serve their own `/data/today.json`); `Icon-192.png` (57 KB, preloaded) replaced by the shared 27 KB seal.
     Sentry review on `5398d91`: with the bar shown, the AppBar's `systemOverlayStyle` region sits below the status
     bar, so the icons over the dark band were left to the platform default — the band now carries its own
     `AnnotatedRegion<SystemUiOverlayStyle>` (`statusBarStyleOn(pal.bar)`: light icons on a dark band; native / PWA).
- **Cost:** +0 Firestore reads, +0 listeners, +0 writes, no new collection (reuses `todaySettingsProvider` and
  `nowProvider`; the badge switch is one more key in `settings/features`). First
  paint: −the visible poster (LCP is now the name / seal, painted with the first frame of HTML), seal shared with the app.
- **Tests:** `test/pagespeed_test.dart` (seal path / alt / size, no `Icon-192`, status text, only composited
  properties in keyframes, manifest colour), `test/today_widgets_test.dart` (32 px, badge tap, 320 px / long label,
  200 % text grows to 44 px, palette roles + contrast on Golden hour and Holy Week, date width next to the badge,
  AppShell placement and seal offset, landscape insets; Home shows only the banner, other pages show the badge, badge
  tap / Tab+Enter / semantics open the stream, switch off shows both, no empty bar on Home with the date off),
  `tool/rules_test/rules.test.mjs` (`liveBadgeHideOnHome` bool accepted / non-bool rejected; whole Today form in one write).

## ADR-045 (PR #38) — Simulation fixes: every active season's service on the next-service card, programme while «يُقام الآن», top event falls back to tonight's programme service, assistant grounds programme / events / live / paused weddings, seed templates never mix into an owner's season

- **Context:** three local simulations (`work/sim-holy-week`, the ADR-043 re-run, `work/sim-revival`, 4–5 Nov 2026, Firestore
  emulator + the real app) left these failures on `e197da9`:
  1. **B1** the next-service card skipped an *additive* revival night (`vespers` / `other`): `computeNextMass.counts`
     took `types = {'mass'}` plus services of schedule-*replacing* seasons only, so at 18:00 / 18:30 on the revival
     evening it showed tomorrow's 06:30 mass under «جدول موسمي مُفعّل: نهضة…».
  2. **B2** «يُقام الآن» rendered only «name — place»; speaker, topic, choir and the PDF button vanished exactly while
     the service runs (18:30–21:30).
  3. **B3** the assistant had no speaker / topic / choir / PDF per service, no church events of the day
     (`dayEvents`) and no live link: "who speaks at the revival tonight?" could not be grounded.
  4. **B4** with `weddingBookingOff` the wedding subtype was dropped silently from the assistant's contact section.
  5. **B5** undated seed templates (`rev-max-1…7`, `hw-day-*` / `hw-eve-*`, all `sample: true`) attached to every
     season with their key; ADR-043's per-day rule applied to replacing seasons only and kept templates of days the
     owner had not entered yet.
  6. **Spec gap (owner):** the Home top event should show tonight's revival with speaker, topic and a PDF button; it read
     only `dayEvents`, and a day event's Drive link opened from «اعرف المزيد» with no label.
- **Decision:**
  1. `computeNextMass`: a service counts when its type is in `types` **or** it belongs to any **active** season
     (additive included), whatever its type; `occurrencesForDay` already merges additive seasons with the regular
     schedule (morning masses stay). The card title is «الصلاة القادمة» when a replacing season is active or the
     service shown is not a mass. This reverses ADR-043's "additive: only masses count".
  2. The happening-now box renders `ProgramDetails` (speaker, topic, choir, audience, PDF; the venue pill only when
     the line shows a free-text place instead of the venue).
  3. `_liturgyLine` appends `speaker`, `topic`, `choir` and `<label or "programme PDF">: <url>`. New prompt sections:
     «Live stream now» (label + `liveUrl`, only while `today.liveOn(now)`) and «Church events (today and the next 7
     days)» from `dayEvents` (only while the `topEvent` card is on; an in-app link to a switched-off section is left out).
  4. `_contactForm`: with `weddingBookingOff` and a visible booking category, one explicit line — wedding (فرح) hall
     bookings are not accepted this season; the other subtypes (عزاء) stay open via /contact.
  5. Seed templates (`undatedSuppressedOn`, `seasonHasRealServices`, `liturgyInSeason`), both season types:
     (a) an undated **`sample: true`** service is not part of a season that has **any non-sample service** (dated in
     its window, or undated of its key); (b) any undated service gives way on a day where the season has a dated
     **non-sample** service — any such service for a replacing season, an **overlapping** one for an additive season
     (a real nightly revival service still runs on its dated feast-morning liturgy). Seasons made only of samples
     (the bundled seed, all of 2027) are unchanged.
  6. Top event hierarchy: admin church event > **today's / tonight's programme service** (new step: the first
     not-ended occurrence of an active season with a speaker or topic, civil today plus yesterday's still running;
     kicker «الليلة في الكنيسة» / «اليوم في الكنيسة»; time + `ProgramDetails` with its labelled PDF button) > Katameros >
     computed feasts. Admin switch «عند عدم وجود حدث: اعرض خدمة اليوم / الليلة من برنامج الموسم» =
     `settings/features.topEventServices` (bool, missing = on). Day events get three optional trailing fields
     `attachmentUrl` (https), `attachmentLabelAr`, `attachmentLabelEn` (≤ 80) and their own button (`topEventPdf`).
  7. Assistant limits: `perMinute` (default 4) stays — it only stops bursts; its admin hint now explains it applies
     together with the daily / season limit (4 a minute + 6 a day = wait a minute after the 4th quick question).
     `AssistantPage` reads `nowProvider` (real time in production) for the season limit and the instruction.
  8. **Review fixes (CodeRabbit on PR #38):** a dated service that starts before its season (morning service on an
     18:00-start day) no longer suppresses that day's weekday services; the wedding-pause line is written even when the
     booking category had only the wedding choice; the assistant page's history key also covers the live link, church
     events and service programmes (`assistantProgrammeSignature`); a sample programme service in the top event shows
     «مواعيد تقريبية»; the day-event row cap is 4,200 characters and the PDF link has no whitespace, host parts ≤ 100 + 100
     and path ≤ 290 (≤ 500 in total, the editor's limit); hints say the fallback needs the next-service card on Home and
     that `commemoration` off still lets programme services show. Declined: a minimum-build gate for `dayEvents` (an
     admin tab from before this PR would rewrite events as 13 fields — every admin gets the new build on reload, and no
     PDF field exists on live yet).
  Not changed (documented designs, reports' "spec mismatch"): a live banner switched on by hand without `liveEndsAt`
  outlives the season; stored switches stay until «استرجاع»; the wedding choice is a subtype of «حجز قاعة».
- **Rules:** `topEventServices` joins the Today gate (`optBool`, +1 expression only when a Today key changes);
  `validDayEvent`'s single regex gains an optional `(␟https-url␟label≤80␟label≤80)?` tail (still one expression per
  event; a 13-field string from before stays valid). 20 events with PDFs and 80-character labels fit one write (test).
- **Cost:** +0 reads, +0 listeners, +0 writes, no new collection. The top-event step reads `liturgiesProvider` /
  `seasonsProvider` only while Home shows the next-service card (which already holds both), else it is skipped.
- **Tests:** `test/season_programme_fixes_test.dart` (B1 domain + card, B2 box, B3 lines / events / live, B4 line,
  B5 additive / replacing / seed-only / real seed / overlap, top-event fallback / precedence / switch / no programme,
  encoded 13 / 16 fields, top-event and day-event PDF buttons); `holy_week_fixes_test.dart` (additive case updated);
  rules group "ADR-045". Simulations re-run from scratch on the merge commit: `work/fix-sims/report.md`.

## ADR-046 (PR #39) — Live user test fixes: top event waits for the stored features, English title before boot, App Check lazy again, no public sample marks, Coptic date fallback, pope-visit images on Hosting

- **Context:** the live user test of 5 Nov 2026 (`work/live-findings/rca.md`, main `af8c917`) found:
  1. the top-event card showed once on a cold load and vanished (the seeding check timed out, `guardSeeded` served
     the bundled `seed.features` — no today keys, so `topEvent` / `commemoration` read true — and the stored doc with
     `topEvent: false` replaced it 4 s later);
  2. `/?lang=en` kept the Arabic `<title>` and `lang="ar"` for 6–9 s, until `MaterialApp` built;
  3. after one visit to `/ask`, every later page load (Home, /contact) loaded reCAPTCHA Enterprise (~700 KiB) and called
     the App Check exchange: the FlutterFire App Check web plugin saves `FlutterFire-[DEFAULT]-recaptchaType` /
     `…-recaptchaSiteKey` in `localStorage` and re-activates App Check at `Firebase.initializeApp`
     (`firebase_app_check_web-0.3.1+3/lib/firebase_app_check_web.dart:41-82`), defeating ADR-037;
  4. the /about header read «تعرّف على عن الكنيسة» (accent `accent_about` + title «عن الكنيسة»);
  5. «بيانات تجريبية» badges and the yellow «مواعيد تقريبية» banner on every page — live has 47/47 liturgies, 4 priests
     and 4 facilities with `sample: true`; the owner does not want them at launch;
  6. `/data/today.json` had `coptic: ""` for 2026-11-08 (Katameros answered `copticDate: null`);
  7. `milestones/pope-visit` hotlinks 4 images from `copticorthodox.church` (CanvasKit fetch fails CORS, the `<img>`
     fallback shows them, with a console error and a double request).
- **Decision:**
  1. `featuresLiveProvider` / `featuresLive()` (`lib/state/providers.dart`): true once `featuresStreamProvider` holds a
     value that is **not `identical`** to `repo.seed.features` (the test `errorReportingSwitch` already uses), or the
     stream failed; always true off Firestore (seed mode). The bundled copy itself is accepted after
     `featuresSeedPatience` (30 s; Seer on PR #39): `guardSeeded` turns a failed stream or an unreachable database into
     that copy, so offline with no cache the card still returns with its defaults (the flicker had the stored doc ~12 s
     after the seed copy). `topEventProvider` returns null until it is true, so the
     card (and its programme-service step) never renders from the seed copy within that window. Cost of the trade:
     on a slow cold load the card can only appear late (at worst 30 s after the seed copy, with its defaults). The other features-driven blocks keep ADR-038's behaviour (seed
     defaults first) — they match the stored values on live today, and holding the splash longer was not wanted.
     **Latent bug found on the way:** `SeedData.settings` / `.features` were getters that parsed a new object on every
     read, so every `identical(v, seed.X)` test (`confirms` of settings/church and settings/features since PR #23,
     `errorReportingSwitch` since ADR-034) could never match the bundled copy. They are now `late final` (parsed once);
     with a stored doc on live nothing changes, and a *missing* doc is again treated as "not proven" as those ADRs meant.
  2. `web/index.html`: inline `<script id="boot-prefs">` right after `<title>` applies `LocaleNotifier.initialLocale`'s
     rule (`?lang=en|ar` → saved `church_portal_lang` → Arabic); English sets `<html lang="en">` and the English title
     at once. Flutter still owns both afterwards (`setDocumentLanguage`, `onGenerateTitle`).
  3. The same script drops every `FlutterFire-*-recaptcha*` key from `localStorage` and `sessionStorage` before
     `flutter_bootstrap.js` loads, so App Check is activated again only by the assistant (`ensureAppCheckActivated`,
     still enforced for AI Logic). Checked with headless Chrome: after visiting /ask, a reload of Home and of /contact
     loads no reCAPTCHA script and makes no `exchangeRecaptchaEnterpriseToken` call.
  4. `accent_about` = «كنيستنا» / "Our church".
  5. Public UI: `SampleBadge`, `PendingConfirmationNote`, `TitleWithBadge` and the `sampleData` / `timesPending` /
     `timesPendingHint` strings are removed; the next-service card and the top event no longer print «مواعيد تقريبية».
     **Kept:** the `sample` field in the data, rules, seed and admin («غير مؤكد» chip, filter, switch), the suppression of
     sample templates (ADR-045), the placeholder-doctor wording on /clinics and the assistant's `[UNCONFIRMED]` grounding
     (`mentionUnconfirmed`).
  6. `tool/fetch_synaxarium.js`: `copticDateOf()` ports `CopticDate.fromGregorian` (JDN, 1 Tout 1 AM = JDN 1825030);
     a null / empty `copticDate` becomes the computed `D/M/YYYY`. The script now exports it and only runs `main()`
     when executed directly.
  7. Pope-visit images: the main image and the three `copticorthodox.church` gallery images are served from Hosting as
     `web/media/milestones/pope-visit-{9712,9703,9744,9780}.webp` (1280 × 853, WebP q78, metadata stripped,
     205–230 KB each; same-origin, so no CORS). **Never Firebase Storage** (Spark plan rule). After merge + deploy, only
     `image.url` and `gallery[0..2].url` of that doc are rewritten on live (owner-authorised; before / after values in
     `work/live-fixes/status.md`). The `media.elwatannews.com` gallery image and the `st-takla.org` saint galleries are
     unchanged (no CORS error seen).
- **Review fixes (PR #39):** Seer / CodeRabbit — the seed copy is accepted after `featuresSeedPatience` (30 s) so a failed
  stream or an offline visit without cache still gets the card (declined the heavier "distinct error value in
  `_guard`" variant: the patience covers both cases without touching the generic guard); `SeedData.features` is never the
  shared `FeatureSettings.defaults` (an empty stored doc parses to it); the boot script reads the **last** `?lang=` like
  Dart's `Uri.queryParameters`.
- **Not changed:** the hero Ken Burns motion (approved standing rule; rca #5 is a tool artefact); live `sample` flags
  (owner data in /admin); the Antibiotic team name (owner data).
- **Cost:** +0 Firestore reads, +0 listeners, +0 writes per visit, no new collection or rule. Hosting: +4 static files
  (~864 KB in the repo), fetched only on the milestone card / page (cached a week). Visitors who used /ask save ~700 KiB
  of reCAPTCHA and one App Check exchange on every later page load. The one-off live fix is 1 document write.
- **Tests:** `test/live_test_findings_test.dart` (featuresLive rule, top event null on the seed copy, the boot script run
  under node for language and storage clean-up, `accent_about`, no sample marks on the liturgy / next-service cards and
  no banned widgets in `lib/ui` outside admin, Coptic date script vs Dart for 731 days incl. 2026-11-08, media files);
  `season_programme_fixes_test.dart` (a sample programme service shows no «times pending» note).

## ADR-047 (PR #40) — English text for the hero verse: bundled WEB (British Edition), optional English for the admin's fixed and season verses

- **Context:** live test of 5 Nov 2026 (`work/live-findings/rca.md` #2): on `/?lang=en` the hero verse body was always
  Arabic. There was no English verse text anywhere: `daily_verses.json` had `ref, refAr, refEn, textAr`, `Verse` had no
  `textEn`, `HeroVerse` drew `textAr` RTL in both languages (under the *English* reference — mixed), and the fixed verse
  (`DailyVerseConfig`) and season verses (`seasonVerses`) were Arabic-only.
- **Decision:**
  1. `Verse.textEn` (+ `Verse.display(english:)`): the English site shows `“textEn”` LTR (Ruqaa 18/22 px, line height
     1.5) with `refEn` (else the Arabic reference); a verse **without** English shows the Arabic text with the **Arabic**
     reference, so an English reference never sits under Arabic text. The Arabic site is unchanged. The shown English
     text starts with a capital letter (`capitalizeVerseStart`, after any leading quote): 28 bundled WEB verses start
     mid-sentence ("let's hold fast…"); the stored text (asset, admin field) is unchanged (owner request on PR #40).
  2. `tool/gen_daily_verses.py` also reads the **World English Bible British Edition** from eBible.org
     (`eng-webbe_vpl.zip`, SHA-256 `018b2ac4…3423a`, "not copyrighted … Public Domain"; the WEB with "the LORD"
     instead of "Yahweh", chosen for a Coptic Orthodox readership — the owner asked for "WEB, else KJV") and writes
     `textEn` byte-for-byte for the same 366 references. The selection is still made from the Arabic only: every
     `ref` / `refAr` / `refEn` / `textAr` and so every day's verse is identical to before (checked). Asset 116 → 160 KB
     (one bundled file, gzip on Hosting; no runtime request added).
  3. Admin, inside the existing `settings/features` doc (no new collection, no listener): `dailyVerse` gains optional
     `textEn` (≤ 500) / `refEn` (≤ 60), written only when set (`toMap`), with two optional fields in the fixed-verse
     card; `seasonVerses` rows gain an optional `␟textEn␟refEn` tail (two optional sub-fields in «آيات المواسم»).
     `FieldDef.encodedOptionalTail` (+ `encodeRowFields`) leaves an all-empty tail out, so rows without English keep
     the old 3-field shape (still valid under the old rules); other encoded lists (day events) are untouched.
  4. Rules: `validDailyVerse` allows `textEn` / `refEn` (strings, same lengths, one joined regex);
     `validSeasonVerses`' single regex gains `(\x1f[^\x1f\x1e]{0,500}\x1f[^\x1f\x1e]{0,60})?` per row (40 full rows fit
     one write — emulator test).
- **Cost:** +0 Firestore reads / listeners / writes per visit; an admin save is the same single write. +44 KB in the
  bundled verse asset (loaded once, cached).
- **Tests:** `test/verse_english_test.dart` (asset English + metadata + SHA pin, no Arabic or "Yahweh" in English, old
  lists still parse, `display` rules, fixed verse `fromMap` / `toMap` / resolve, season tail parse + encode, rules
  text, hero in EN / AR / fixed with and without English); rules group "ADR-047".

## ADR-048 — English documentation suite and comprehensive project README overhaul

- **Context:** The original human manual in `documentation/` (31 feature files, `architecture.md`, and `operations.md`) was written solely in Arabic. Concurrently, the root `README.md` was outdated and lacked coverage of critical features introduced across PR #10 through PR #40 (top utility bar, live badge, liturgical web loading screen, dynamic occasion themes, 1-click season presets, programme details, custom section/page builders, Gemini AI assistant, and Sentry error monitoring). International developers, contributors, and church staff needed complete, first-class English documentation.
- **Decision:**
  1. Establish the English documentation suite under `documentation/en/` with three core documents:
     - `documentation/en/README.md`: English documentation portal and overview.
     - `documentation/en/architecture.md`: Comprehensive technical architecture manual (Flutter layers, Riverpod 3, Firestore models, security rules, Spark plan media strategy, and PageSpeed engineering).
     - `documentation/en/operations.md`: Operational and deployment runbook (GitHub Actions CI/CD, preview channels, secrets, admin provisioning, safe seeding rules, Sentry telemetry, and troubleshooting).
     - `documentation/en/features.md`: Unified master reference for all 31 features, specifying visitor experiences, exact `/admin` labels and switches, and technical limits.
  2. Overhaul the root `README.md` into an authoritative, professional English entry point featuring technology stack badges/icons (Flutter, Dart, Firebase, Cloud Firestore, Gemini API, Sentry, GitHub Actions), mermaid architecture diagrams, feature matrix, admin guide, and resilience workflows.
  3. Update `documentation/README.md`, `docs/memory-bank/00-README.md`, and `AGENTS.md` to maintain bilingual cross-references.
- **Consequences:** English-speaking developers and church stakeholders have full parity with the Arabic documentation. Zero changes to runtime Dart code, rules, or database schemas.

## ADR-049 (PR #42) — Season card timing: parallel services in «يُقام الآن», overnight services, readable seasonal switch, day-to-night handover, admin time / date pickers

- **Context:** Phase 1 of the seasons simulation (`work/seasons-sim/phase1/report.md`, Holy Thursday 29 Apr 2027 18:30
  on the emulator) found D1: at 18:30 the «يُقام الآن» box showed the main church's Evening Pascha only — Youth Pascha
  (lower hall) and Children's Pascha (services building), both running since 18:30, appeared nowhere on the card
  (`computeNextMass` kept the first running occurrence, `happening ??= o`; `NextMassCard` built «وفي نفس الوقت» only
  for the next service). C1: the /mass-schedule seasonal switch read as OFF on Holy Week (ash thumb on an
  ornament-at-50 % track, grey on grey). The owner also asked to audit overnight services (end ≤ start) and the
  additive day-to-night handover, minute by minute.
- **Decision:**
  1. **Parallel now.** `NextMassResult.runningNow` keeps EVERY counted service in progress (yesterday's overnight ones
     first, then today's in start order); `happeningNow` is its first, as before. `NextMassResult.alsoRunning(opts)`
     = `parallelOccurrences(happeningNow, runningNow)`: the running services in ANOTHER venue / hall (ADR-041 rule:
     same-venue ones and ones without a place are not named). The «يُقام الآن» box shows them on the same
     «وفي نفس الوقت: [القاعة] ([الفئة])» line (`ProgramDetails.parallelText`, `Icons.call_split_rounded`) as the next
     service. At 18:30: «وفي نفس الوقت: القاعة السفلية (شباب)، مبنى الخدمات (أطفال)». No layout change otherwise.
     `alsoRunning` compares places only (every `runningNow` entry is running; a service without an end time runs its
     default 120 minutes), not the 1-minute overlap rule (Sentry / CodeRabbit on PR #42).
  2. **Overnight.** Audit of `schedule.dart`, `computeNextMass`, `programmeServiceAt` (top event),
     `isDatedLiturgyCurrent`, `DayEvent.endedAt`, the card labels, the 18:00 liturgical-day shift and both Egypt DST
     changes: occurrences already roll an end ≤ start into the next day, so an overnight service is never finished
     before it starts and stays «يُقام الآن» after midnight as the previous day's record (`dayOffset` −1) — tests now
     pin it (Easter night 22:30–03:30, Kiahk 21:00–05:30 → 05:30–07:30 liturgy, Apocalypse night Fri 23:00 → Sat
     06:00 on the DST start day, Thursday 22:30–03:30 across DST start (4 real hours) and DST end (6 real hours)).
     Two real gaps were fixed: (a) **parallel services across midnight** were never compared (`parallelServices`
     matched the same date / weekday only; the card compared the next service with its own day only): services on
     adjacent days (dated: ±1 day; weekly: ±1 weekday, Sunday ↔ Monday wraps) now compare on one clock, and the card
     uses `occurrencesAround` (the day before, the day, the day after); one-off dates compare real Cairo instants
     (`CairoTime.at`), so a wall time skipped by the spring DST change cannot fake an overlap (CodeRabbit), and the
     lists agree with the card on the DST start day (tested); (b) **the assistant** listed
     "10:30 PM – 03:30 AM" with nothing saying it ends the next morning — the line now adds
     "(ends the next morning, after midnight)", so at 00:30 the model does not read the service as over.
  3. **Seasonal switch.** Palette roles only (ADR-043), on `OccasionColors`: ON = filled `primary` track with the
     `onPrimaryAccent` thumb (gold on the maroon posters, crimson on Holy Week's ash), OFF = `surfaceAlt` track with a
     `muted` outline and thumb. Each nudged by `ensureContrast` to ≥ 3:1 (`kNonTextContrast`, WCAG 1.4.11) on the card
     grounds and the thumb on its track, so admin palette edits cannot break it. Applied to the /mass-schedule
     «المواسم والأعياد الكنسية» switch only (the /clinics «متاح اليوم» switch keeps its success colour). Before: the
     ON track was 1.4–2.1:1 on the card in every theme.
  4. **Additive handover.** Minute-by-minute test of a summer revival (EEST, additive): mass 07:00–09:00 → at 09:00
     the revival is «الصلاة القادمة» («الليلة • ليلة الخميس», after the 18:00 shift) → 19:00 «يُقام الآن» → 21:30
     the next day's mass at once, «القداس القادم» «غدًا • الخميس»; the revival never removes the regular morning
     mass. This already worked on `main`; it is now pinned against an independent oracle (2 days × 1,440 minutes).
  5. **Admin time / date pickers** (owner, added to this PR). Every `FieldType.time`, `date` and `dateTime` field of
     the generic form (`DocEditor._textField`, top-level and inside rows: liturgy `date` / `start` / `end`, meeting and
     clinic `start` / `end`, alert and season `startsAt` / `endsAt`, «اليوم والبث المباشر» `dayStartsAt`,
     `liveEndsAt` and the church-event rows `date` / `endDate` / `start` / `end`) is read-only with a trailing clock /
     calendar icon (a tap on the field opens it too). Time: `showTimePicker` as a 12-hour AM/PM picker (owner change: easier for
     admins; Arabic shows ص/م; `MediaQuery alwaysUse24HourFormat: false`), saved strictly zero-padded 24-hour `HH:mm`
     (`formatPickedTime`: 6:05 AM → `06:05`, 12:00 AM → `00:00`, 12:00 PM → `12:00`, 11:59 PM → `23:59`). Under the
     read-only field the helper shows the friendly 12-hour reading in the app's style (`formatTimeArabic` /
     `formatTimeLatin`: «٠٦:٣٠ م» / "06:30 PM"; a date-time adds the date: "26 Apr 2027, 06:30 PM"). The chosen ص/م is filled with `primary` (the theme's
     containers match the dialog surface, so the default left both periods looking unselected). Date: `showDatePicker`, saved
     `YYYY-MM-DD` (`formatPickedDate`). Date-time: date then time, `YYYY-MM-DD HH:mm` Cairo wall time. Stored types are
     unchanged: `date` / `dateTime` still parse to the same Timestamp instant (`parseFieldValue`), row dates stay text.
     The picker opens on the current value (a legacy unpadded `9:00` or Arabic digits still load,
     `parseFieldTime` / `parseFieldDateTime`); an optional field gets a clear (×) button. No Firestore shape or rules
     change. Left as they are: `looseDate` (priests' ordination dates allow `YYYY` or `YYYY-MM`, which a date picker
     cannot express) and the occasion-theme date ranges (already on `showDatePicker` since ADR-025). No admin form
     has a time or date in a plain text field.
- **Not changed (by design, noted):** in an additive season, a seasonal `mass` on a day still supersedes that day's
  regular masses (ADR-045 feast-liturgy rule), e.g. a Kiahk Sunday 05:30 liturgy would hide a regular Sunday mass;
  the owner can ask for an overlap-only rule later. **Superseded by ADR-050** (overlap only, `replacesDay` for feasts).
- **Cost:** +0 Firestore reads, +0 listeners, +0 writes: the card already holds liturgies and seasons; the extra work
  is pure Dart on data in memory (two more days of occurrences for the next service's parallel line).
- **Tests:** `test/season_card_timing_test.dart` (24: parallel now 18:30 / 19:30 / 20:30 / 22:30, same-hall and no-place
  rules; Easter night minute by minute Sat 18:00 → Sun 08:00, 00:30 top event and one-off list, assistant line, Kiahk
  minute by minute, Apocalypse night, DST start / end, cross-midnight parallels (dated, weekly wrap, card); revival
  handover minute by minute vs an oracle and at the handover points; widgets: the now box line at 18:30 Holy Week,
  00:30 «يُقام الآن», 09:00 / 19:00 / 21:30 handover; switch contrast in every theme and the Holy Week switch roles).
  `test/admin_pickers_test.dart` (formatters: padding, 00:00, 23:59, prefill parsing; liturgy form read-only fields,
  12-hour AM/PM picker (AM/PM and ص/م present, 6:05 AM / 11:59 PM / 12:00 AM / 12:00 PM → `06:05` / `23:59` / `00:00` /
  `12:00`, the 12-hour reading), prefill, date, clear, Arabic RTL; season `startsAt` date + 6:30 PM → `2027-04-26 18:30`, same instant; «اليوم» `dayStartsAt`
  and church-event rows), `test/helpers/admin_pickers.dart`; the clinic save test in `admin_test.dart` now fills times
  through the picker. Phase 1 harness re-run on the branch: `work/seasons-sim/fixes1/status.md`.

## ADR-050 (PR #45) — Seasons v2 fixes A: additive seasons hide only overlapping masses (`replacesDay` for feasts), samples never beat real services, assistant label = schedule, now-box end time, seed placeholder text, pope-visit image on Hosting, hero season tint

- **Context:** the seasons v2 simulation, phases 1–7 on the emulator (`work/seasons-v2/ISSUES.md`, phase reports) found:
  (1) B6-1 / P3 item 1 / P7 O2 — in an additive season ONE seasonal `mass` hid EVERY regular mass that day
  (`occurrencesForDay.superseded()`, no time check): the 12:00 fasting liturgy hid the real 06:30 mass, a Kiahk
  05:30 liturgy hid the Sunday 08:00 masses, the Lent 12:00 / 13:00 liturgies hid the Tuesday 07:00 mass — while
  /mass-schedule and the prompt still listed them; (2) P2 B1 — the seed's DATED sample `pascha-day` survived beside the
  owner's real Easter programme (the overnight liturgy is dated the evening before) and, being a seasonal `mass`, hid
  the real 07:00 Sunday mass; at 03:31 the card handed over to the sample; (3) P3 B2 — a sample of ANOTHER active
  season (the seed's St Moses revival night, `order: 2`) outranked the owner's real revival at the same start (the
  real one was reduced to «وفي نفس الوقت: …», its speaker / topic lost); (8) the prompt said «[ADDITIVE — regular
  morning masses continue]» on days the card hid them; (15) the now box showed no end time; (16) seed text
  «— في انتظار تأكيد الكنيسة.» on public pages and in the prompt; (17) unmarked seed samples; (18) the pope-visit
  gallery[3] image on `media.elwatannews.com` fails CORS in CanvasKit; (19) the hero stayed golden in the Marian
  theme; (20) the parallel line uses «، » not «•».
- **Decision:**
  1. **Overlap-only in additive seasons** (`schedule.dart` `occurrencesForDay`): a regular `mass` is superseded only
     by a seasonal `mass` that overlaps it in time (the rule vespers / praise already had), or by a seasonal service
     marked **`replacesDay`** on that day. `replacesDay` is a new optional bool on the liturgy doc (default false;
     admin checkbox «يحل محل قداسات اليوم المعتادة (قداس العيد)» in the liturgy form, with a hint) for a feast liturgy
     that cancels every regular mass of its day; regular vespers / praise still follow the overlap rule. A season with
     `replacesRegular: true` is unchanged (owner's choice; replaces whatever the `sample` flags).
  2. **Samples never take a real service's place:** (a) `undatedSuppressedOn` / `liturgyInSeason`: once a season has
     any real service (`seasonHasRealServices`), ALL its `sample: true` services give way, dated ones too (was undated
     only); (b) a seasonal sample supersedes a regular service only if that one is a sample too (`mayReplace`);
     (c) a seasonal sample gives way to a real seasonal service of ANY active season that overlaps it; (d) sort =
     start, then real before sample, then `order` (`compareOccurrences`). Seasons made only of samples (the bundled
     seed) are unchanged.
  3. **One function everywhere:** `regularSupersededOn(liturgies, seasons, day)` = the regular services
     `occurrencesForDay` leaves out that day. /mass-schedule's weekly tab marks them «لا يُقام اليوم» (pill, `muted`
     role) on today's weekday; the assistant prompt gains "## Services today and tomorrow (exactly as the website shows
     them)" from `occurrencesForDay` plus a "NOT held (the season replaces them)" line, and each additive season's label
     is computed: «[ADDITIVE — regular services continue]» or «[ADDITIVE — some regular services are NOT held today, see
     …]»; a `replacesDay` service is tagged «[REPLACES the day's regular masses]»; the general rule text describes the
     overlap rule.
  4. **Now box end time:** «حتى ٠٣:٣٠ ص» / "Until 03:30 AM" under the «يُقام الآن» line, from the occurrence end
     (overnight = next morning; no end = the 120-minute default the card counts), 12-hour ص/م like the rest of the app
     (`formatTimeArabic` / `formatTimeLatin`), `goldText` role.
  5. **Seed placeholder text (16):** `lib/domain/pending_text.dart` `stripPendingPlaceholders` drops a bracketed aside or
     a sentence holding «في انتظار تأكيد» / «لم يُؤكَّد» / «غير مؤكد» / "pending (church) confirmation" / "not confirmed"
     (matched without tashkeel; a link inside the sentence goes with it), but never an affiliation caveat («لم يُؤكَّد
     أنه تابع للكنيسة», "not confirmed as a church ministry": a fact visitors need, kept; the seed's two activities
     no longer say "partner", only that the church's page follows them — CodeRabbit on PR #45);
     applied on read to `descAr/En` (activities, facilities, milestones) and `bioAr/En` (priests, saints) in
     `models.dart`, so public pages and the prompt treat it as empty; the admin still edits the stored text (raw maps).
     `tool/gen_seed.py` / `seed.json` no longer carry the phrases (`sample: true` stays). Live documents were NOT
     written (owner list below).
  6. **Samples (17):** covered by 2; the Holy Week / Pascha dated samples stay in the seed for seed-only installs.
  7. **Pope-visit image (18):** `web/media/milestones/pope-visit-gallery5.webp` (the elwatannews picture fetched
     server-side, 779×439, WebP q82, 57 KB). The live field change is prepared, NOT applied:
     `work/fixall/live-gallery3.json` (`milestones/pope-visit.gallery[3].url` → the Hosting URL; 1 write).
  8. **Hero season tint (19):** `OccasionColors.heroTint` — a top-down gradient from the theme's `primary` (22 %) to its
     `background` (14 %) to transparent (stops 0 / 0.5 / 0.92; a gentle wash: the painting stays clearly visible, text contrast unchanged), on the occasion themes only (none on Golden hour, its
     accent presets, or dark themes, whose art is already dimmed). `HeroStage(tint:)` paints it as ONE extra still
     layer above the others (feathered at the bottom); Ken Burns, the haze and the rays (Flutter and the CSS
     `HeroAmbientLayer`) are untouched. Admin switch `settings/features.heroSeasonTint` (default on) «لون الموسم على
     صورة الواجهة» in the theme card.
  9. **Separator (20):** «، » kept — the correct Arabic list comma («•» already separates day and time in the pills);
     documented in `parallelSummary`.
- **Cost (Firebase):** +0 reads, +0 listeners, +0 polling, no new collection. `replacesDay` lives in the liturgy docs
  and `heroSeasonTint` in `settings/features`, both already streamed; everything else is pure Dart on data in memory
  (two days of `occurrencesForDay` for the prompt). Writes: only the owner's own edits (1 write per liturgy tick or
  switch). Rules: `validLiturgy` + `replacesDay` in the key list and `optBool` (≈3 expressions); `validFeatures`
  + `heroSeasonTint` (only evaluated when changed); the worst-case write tests still pass (< 1,000 expressions).
- **Live data for the owner (read-only list, from the seed / known data — nothing was written):**
  (a) placeholder text, now hidden on display but still stored if live kept the seed text: `facilities/nursery`,
  `facilities/employment`, `facilities/library` (`descAr`, `descEn`); `priests/bigol`, `priests/saleeb`,
  `priests/barnaba` (`bioAr`, `bioEn`; ADR-046 notes live has its own priests, these may not exist);
  `activities/davids-tones`, `activities/hymns-school` (`descAr`, `descEn`): drop «شريك/شريكة» / "partner" if live
  still says it (the affiliation caveat stays and is shown);
  (b) seed samples: `liturgies/hw-palm`, `hw-thursday`, `hw-friday`, `hw-saturday`, `pascha-eve`, `pascha-day` (dated),
  and the undated templates `hw-day-*`, `hw-eve-*`, `rev-max-*`, `rev-moses-*`: they now give way automatically once
  their season has a real service and beside a real service of any season, but still show in a season with none —
  enter the real programme or hide them; (c) `milestones/pope-visit.gallery[3].url` (`work/fixall/live-gallery3.json`).
- **Tests:** `test/season_schedule_overlap_test.dart` (phase repros: P2 03:31 → real 07:00, sample gone from lists and
  prompt, seed-only unchanged; P3 15:01 / 18:45 real revival with speaker beats the St Moses sample, real-before-sample
  sort; P3 06:30 mass stays with a 12:00 seasonal mass; P6 07:31 → Sunday 08:00; P7 Tue 07:00 stays with Lent 12:00 /
  13:00; `replacesDay` hides the day's masses but not vespers, not when sample, read from Firestore, admin field;
  prompt labels and "Services today and tomorrow"; now box «حتى ٠٣:٣٠ ص», "Until 03:00 PM", no-end default; /mass-schedule
  «لا يُقام اليوم»; placeholder stripping, models, seed and prompt clean; WebP ≤ 200 KB; hero tint per theme, layer
  and switch); `test/domain_test.dart` label updated; rules: `replacesDay` and `heroSeasonTint` bool-only, visitors
  denied. Screenshots: `work/fixall/A/png/`.
- **CodeRabbit on PR #45 (fixed):** a full-override season still replaces the regulars when its only service that day
  is a sample hidden by another season's real one; `seasonHasRealServices` counts only a real service that can take
  place (a start time; dated: starting inside the window); the prompt's season label is read against the combined
  schedule, and "Services today and tomorrow" lists a service of the evening before still running past midnight as
  «[ONGOING …, until …]» while it is still on (tomorrow: «[CONTINUES …]»; Sentry on PR #45); /mass-schedule marks a superseded dated special service «لا يُقام اليوم» too;
  `effectiveAt` keeps `heroSeasonTint` after a preset expires; placeholder matching ignores tashkeel and keeps links
  whole; affiliation caveats kept (above). Not changed: a seasonal mass of the evening before overlapping a regular
  mass after midnight (no regular mass runs then); the features editor's stale-snapshot merge (shared by every
  default-valued switch since ADR-022); hiding unconfirmed facilities / priests (owner's ADR-046 choice).

## ADR-051 (PR #44) — Season keys of their own, admin exceptional-quota list, church calendar in the assistant, feast-night replace dates, tonight's live end, Holy Week day names, EN live label

- **Context:** the seasons v2 simulation (phases 1–7, `work/seasons-v2/ISSUES.md`) used the nearest existing key for
  the Apostles' fast, Kiahk and Great Lent (`fast`) and for Nayrouz / the Cross (`pascha`), and found: no Coptic date
  or feast in the assistant prompt (4); the 6-a-day quota missing Great Lent, Kiahk and the Marian seasons (5); a Latin
  «(6)» in the Arabic limit message (6); the /ask greeting offering hidden clinics / meetings (7); the preset's live
  banner lasting until the season end (10); no way for one additive season to replace the regular schedule on the feast
  night only (11); fast presets keeping weddings (12); no Holy Week day names (13); the Arabic live label on English
  pages (14). Issues 1–3, 8, 15–20 are PR-A (ADR-050).
- **Decision:**
  1. **Season keys (9).** `lib/domain/season_keys.dart` (`SeasonKeys.all`) is the one list read by the season / liturgy
     forms, season verses, the season → theme map, the preset and the assistant; firestore.rules has
     `seasonKeyList()` (a test compares them). New keys: `apostles` (صوم الآباء الرسل), `nayrouz` (النيروز وعيد الصليب),
     `kiahk` (شهر كيهك), `great_lent` (الصوم الكبير المقدس). **Nayrouz covers the Feast of the Cross**: the Nayrouz
     season (its festive tune) runs from 1 Tout to the Cross on 17 Tout, both festive red; one key keeps the rules'
     regexes and the admin list short — a separate `cross` key can be added later if the church keeps them apart.
     `fast` stays valid (older documents; the Nativity fast before Kiahk, Nineveh), its label now says "general".
     Themes (palette roles only, no violet): `great_lent` / `apostles` / `kiahk` → `fasting` (ash, stone, oxblood),
     `nayrouz` → `resurrection` (festive red); all remappable in «ثيم الموقع والمناسبات». Theme priority:
     holy_week, pascha, nativity, epiphany, nayrouz, marian, great_lent, apostles, kiahk, fast, revivals, summer. A
     fasting key without verses of its own uses the `fast` verse set (`SeasonVerses.versesFor`).
  2. **Exceptional quota (5).** `settings/assistant.exceptionalSeasons` (list of season keys; missing = the code
     default; empty = no season raises the limit), edited as chips («المواسم الاستثنائية») in /admin → المساعد الذكي
     (new generic `FieldType.choices`). Default: holy_week, pascha, nativity, revival_maximus, revival_moses,
     **great_lent, kiahk, marian** — the busy seasons with many visitor questions (long services, revival nights,
     Kiahk praises); the general `fast`, `apostles`, `nayrouz`, `epiphany`, `summer` stay ordinary (admin can tick them).
     `perDaySeason` (default 6) and `perDay` stay admin numbers; a season never lowers `perDay`.
  3. **Church calendar line (4).** `churchCalendarLine()` adds to the system instruction: the liturgical day exactly as
     the top bar shows it (Coptic date, the admin's day start — 18:00 by default or sunset — Holy Week names) and the
     feast of that day from the Katameros day the home page already loaded (`ref.exists(synaxariumProvider)`, no new
     read) plus the computed feast list. The instruction is built for every question, so it follows the 18:00 rollover
     with no refresh of its own.
  4. **Arabic digits (6).** The limit / too-long messages pass `localDigits` → «(٦)» on Arabic pages.
  5. **/ask greeting and chips (7).** The built-in welcome (`askIntroText`) names only switched-on sections (liturgy
     times, clinics, meetings, contacts); suggested-question chips about a hidden section are dropped with the same
     `topicSections` rule as the allowed topics. The admin's own welcome text is shown as written.
  6. **Tonight's live end (10).** The preset's live option sets `liveEndsAt` = `presetLiveEnd()`: the end of the season's
     last visible evening service (start ≥ 12:00) on its first evening (today, or the season's first day when applied
     ahead) + 30 min (overnight = next morning); a service running since last night (applied at 00:30 in an all-night
     praise) gives its own end + 30; 23:59 that day when there is none or all ended; never after the season end. An
     unedited default is worked out again at confirmation from the fresh season and clock; «تطبيق» waits for the
     services; «نقل الرجوع التلقائي» now only pulls the live end in to a shortened season end, never later (CodeRabbit
     on PR #44). The screen shows it
     («ينتهي شريط البث: …») with an edit button (date + time picker); «اليوم والبث المباشر» still edits it later. The
     preset's own auto-revert stays the season end. The screen reads `liturgies` when a season is picked (snapshots for 8 s, then closed).
  7. **Feast-night replace dates (11).** `seasons/{id}.replaceDates`: up to 10 civil Cairo dates `YYYY-MM-DD` (the rules
     and the reader refuse impossible dates such as 2027-02-31 or 29 Feb outside leap years; the picker stops at
     2099, the rules' 20xx). On those
     days an additive season replaces the regular services starting inside its window (`Season.replacesOn`, used by
     `occurrencesForDay` and `undatedSuppressedOn`); other days stay additive; ignored when `replacesRegular`. Admin:
     date chips in the season form (new `FieldType.dateList`), shown read-only on «تجهيز الموسم»; the assistant prompt
     lists them per season.
  8. **Fast presets (12).** `PresetRequest.defaultsFor`: `fast`, `great_lent`, `apostles`, `kiahk` tick «إخفاء حجز
     الأفراح» by default (the Nativity fast uses `fast` / `kiahk`). Holy Week unchanged; feasts, revivals, Marian,
     Nayrouz unchanged.
  9. **Holy Week day names (13).** `holyWeekDayName()` from `orthodoxEaster`: أحد الشعانين، اثنين / ثلاثاء / أربعاء
     البصخة، خميس العهد، الجمعة العظيمة، سبت النور (Palm Sunday, Holy Monday–Wednesday, Covenant Thursday, Good Friday,
     Joyous Saturday) replace the weekday in `LiturgicalDay.label` — top bar «ليلة الجمعة العظيمة ٢٢ برموده ١٧٤٣ ش»
     after the rollover, and the prompt's calendar line. Computed from the date (no season needed).
  10. **EN live label (14).** `liveLabelEn` already existed in `settings/features` and «اليوم والبث المباشر»; the
     banner and badge used `pick(ar, en)`, which fell back to the Arabic text. Now `TodaySettings.liveLabelFor`:
     English pages show `liveLabelEn` or the generic "Live now from the church" / "Live", never the Arabic; the admin
     field's hint says so.
- **Rules:** `seasonKeyList()` used by `validSeason`, `validLiturgy`, `validSeasonPreset`, `validSeasonThemes` (13 keys,
  values regex `{0,12}`); the season-verse regex knows the new keys; `validReplaceDates` (≤ 10, unique, one regex over
  the joined list + split count); `validAssistant.exceptionalSeasons` (list ≤ 13, `hasOnly(seasonKeyList())`).
  Expression budget: a full 13-key theme map + 12 schedule slots in one write, and a season at maximum (programme,
  image style, 10 replace dates) both pass in the emulator.
- **Firebase cost:** +0 collections, +0 public listeners, +0 visitor reads or writes. New fields live in existing docs
  (`settings/assistant`, `seasons/{id}`). The assistant uses the already-loaded Katameros day (Hosting JSON, not
  Firestore) only when present. Admin only: one read of `liturgies` (~60 docs; a cached then a server snapshot) when a season is picked on «تجهيز
  الموسم», listener closed after 8 s. Spark plan unaffected.
- **Tests:** `test/season_keys_assistant_test.dart` (key list vs rules / admin / verses / themes / labels; theme map;
  verse fallback; quota defaults and admin list; Holy Week names and labels; calendar line incl. rollover, Katameros,
  sunset; prompt line; replace-date prompt line; greeting / chips filter; fast preset defaults; `presetLiveEnd` cases;
  `planApply` live end; `replaceDates` on `occurrencesForDay`; live label per language),
  `test/season_keys_assistant_widgets_test.dart` (top bar Holy Week AR / EN; EN banner / badge label; admin quota chips
  and replace-date chips; preset screen: Great Lent weddings off, tonight's live end, replace dates, one batch),
  `test/assistant_test.dart` (Arabic «(٦)», greeting / chips with clinics + meetings off); rules tests "ADR-051".

## ADR-052 (PR #46) — Church milestones on the About page («محطات الكنيسة»)

- **Context:** The owner asked (6 Nov 2026) «ضيف محطات الكنيسه في صفحه عن الكنيسه». The milestones (`milestones`
  collection, section `milestones`) were listed only by the Home block «قصتنا» (`HomeBlocks.milestones`, private
  `_MilestoneCard` in `home_page.dart`); their detail pages already live under `/about/milestones/<id>`, but Back
  went Home.
- **Decision:**
  1. **One shared card.** `_MilestoneCard` moved to `lib/ui/widgets/milestone_card.dart` as `MilestoneCard` (same
     cover / lead image, year in local digits, title, text, «التفاصيل» link). Home and About render the same widget;
     the Home block is otherwise unchanged (cards keyed `homeMilestone-<id>`).
  2. **About section.** `/about` shows «محطات الكنيسة» / "Church milestones" (`SectionTitle`, key
     `about-milestones`, cards keyed `aboutCard-<id>`, `ResponsiveGrid`) right after the history & altars and before
     the patron saints, ordered by `order` as on Home, from the existing `milestonesProvider` (no new listener or
     collection).
  3. **Switch.** New `settings/features.aboutMilestones` (bool, default **on**; `FeatureSettings.aboutMilestones`,
     `showAboutMilestones` = section `milestones` on AND the switch). /admin → «الأقسام والصفحة الرئيسية» →
     «تشغيل وإيقاف الأقسام»: an indented switch «إظهارها أيضًا في «عن الكنيسة»» under «محطات تاريخية (قصتنا)»
     (`ValueKey('features-aboutMilestones')`, disabled while the section is off). The Home block keeps its own
     home-layout switch. Saved only once off or already stored (`featuresSaveWrites`), so saves keep working against
     rules that predate the key; rules: key allowed, and `d.get('aboutMilestones', true) is bool` checked in ONE
     gate with the other hero bools (`changed.hasAny([...])`): a separate clause pushed the worst-case page-headers
     save (all 8 pages, max lengths) over the 1,000-expression cap. After merging main (ADR-050 `heroSeasonTint`)
     the two hero gates (`heroMotion` + `heroSeasonTint`, `heroShowAddress` + `aboutMilestones`) still went over,
     so all four share one gate; the worst case passes again.
  4. **Back / breadcrumb.** `DetailKind.parentPath` became `parentPathIn(FeatureSettings)`: a milestone's parent is
     `/about` while the About page lists it (`showAboutMilestones` and `/about` enabled), else Home as before.
     `parentRouteOf(location, features)` (phone Back arrow) and the detail page's «رجوع إلى …» use it.
  5. Milestones alone do not keep `/about` alive (`routeSections['/about']` unchanged: history, saints, priests,
     departed priests); with all four off the page is unavailable and milestone Back goes Home.
- **Cost:** +0 writes; +0 new listeners. The About page watches the same app-wide `milestonesProvider` (not
  autoDispose) as Home: Home → About reuses the open listener (+0 reads). Landing directly on /about opens the one
  `milestones` listener Home would have opened (one read per milestone doc, 4 today), once per session.
- **Tests:** `test/about_milestones_test.dart` (shown after the altars and before the saints in Home order, AR title,
  hidden with the switch off / the section off, Home block unchanged and independent of it, model / save / rules
  text, admin switch saves and is disabled with the section off); `test/detail_pages_test.dart` (milestone Back →
  About, → Home with the switch / section / About off); rules group "ADR-052".

## ADR-053 (PR #47) — Full-override seasons replace the regular schedule on every day of their window, cross-season samples leave the season lists, a later parallel service is named with its time

- **Context:** the seasons v2 round-2 simulation (`work/seasons-v2/r2/phase1–7/report.md`, code at `d15a225`) found
  one regression and three smaller items. **N1 (P1, FAIL):** ADR-050 hides every sample of a season that has a real
  service, *before* the replacement step; on Holy Week days where the owner entered nothing (Good Friday) the season
  then had no candidate service, was never added to `replacing`, and the regular weekly masses came back — home card
  «غدًا • الجمعة — القداس الإلهي الأول (باكر)», /mass-schedule, `computeNextMass` and the prompt's "Tomorrow" list.
  Deleting the seed sample docs would cause the same. **P3 (low):** an undated sample of one season (`rev-moses-3`,
  Wed 18:30) stayed in the /mass-schedule seasonal section and the prompt's weekly "Holy seasons" list beside another
  active season's real service at that hour, while the day views hid it. **P2 O-a:** at 03:31 on Easter morning the
  card's 06:00 mass read «وفي نفس الوقت: الكنيسة الكبرى (عام)» for a mass starting at 07:00. **P7 O3:** the seasonal
  switch subtitle did not mention fasts.
- **Decision:**
  1. **Window replacement (N1, option a).** In `occurrencesForDay`, every active season with `replacesRegular` and
     both `startsAt` and `endsAt` is in `replacing` from the start: it supersedes every regular service *starting
     inside its window* (`isSeasonActiveAt(s, o.start)`), whether or not it has a service that day and whatever the
     samples. Holy Week, Pascha and Nativity windows are exact, which is the owner's meaning of «صلوات الموسم تحل محل
     الجدول الأسبوعي». Kept: morning services before an 18:00 start; an **open-ended** full-override season (no start
     or no end) still replaces only on its service days (it would otherwise erase the weekly schedule for good);
     additive seasons (overlap rule, `replacesDay`) and `replaceDates` (feast night, decided on that day's services)
     unchanged. Card, /mass-schedule («لا يُقام اليوم» via `regularSupersededOn`), `computeNextMass` and the prompt
     ("Services today and tomorrow" + "NOT held" line) read the same function; the prompt's "Holy seasons" legend now
     says a [REPLACES regular schedule] season replaces every regular service between its dates, even on a day with
     no season service listed. Consequence for the owner: a 50-day season must stay additive (it was in the sims).
  2. **Cross-season samples in the lists (P3).** `liturgyInSeason(l, s, all, [seasons])` / `seasonalSchedule(...,
     {context})`: a `sample` is left out when a real service of another active season overlaps it (same rule as the
     day views: `_sampleHiddenByOtherSeason`, the other service must really occur in its own season) — a dated sample
     on its day; an undated one when that holds on **every** day of its weekday inside its window (on a week without
     such a real service it is still held, so it stays listed). /mass-schedule's additive view passes all seasons as
     `context`. Cheap path unchanged when no other active season has a real service.
  3. **Later parallel service (P2 O-a).** `parallelOccurrencesOf` (occurrences; `parallelOccurrences` maps it). The
     next-service card keeps «وفي نفس الوقت: …» for services starting with (or before, still running) the card's
     service and adds one line per service starting later while it runs: «وبعدها ٠٧:٠٠ ص: القداس الإلهي (صباح
     الأحد) — الكنيسة الكبرى (عام)» / "Then at 07:00 AM: …" (`parallelThen` l10n, `parallelThenLine`, 12-hour ص/م as
     elsewhere). The «يُقام الآن» box (all running now) and the /mass-schedule list cards (weekly templates, ADR-041)
     keep their wording.
  4. **Switch subtitle (P7 O3).** `holySeasonsHint`: «عرض مواعيد أسبوع الآلام والأعياد والأصوام والنهضات الروحية» /
     "Show Holy Week, feast, fast and revival times".
- **Review (CodeRabbit on PR #47):** the prompt's "Holy seasons" list also names a bounded full-override season with no
  service listed («No season services are listed yet: regular services are NOT held between these dates») and labels
  an open-ended one «[REPLACES regular schedule on its service days]» (the legend explains both); the list scan counts
  a weekday only when the occurrence starts inside the season's window, and a window longer than the 400-day scan
  keeps the sample listed. Not changed: cross-season hiding for **open-ended** seasons in the lists (no finite set of
  days to check; the day views still hide such a sample).
- **Rules:** unchanged. **Data:** no field, no write; seed unchanged.
- **Firebase cost:** +0 reads, +0 writes, +0 listeners (pure client logic on the already-loaded liturgies / seasons).
- **Tests:** `test/season_replace_window_test.dart` (Good Friday with the seed sample and with the sample docs
  deleted: no regular masses, `regularSupersededOn`, next after Thu 23:00 = Sunday after the window; Holy Thursday,
  Saturday before / after 18:00; prompt "Tomorrow … no services listed" + NOT held; Nativity and Pascha-from-18:00
  windows; open-ended full override and additive seasons unchanged; card and /mass-schedule widgets; P3 list / prompt /
  dated sample / `context` / sample-only; parallel "then" line AR + EN + no same-time line; switch subtitle).
  Updated: `domain_test.dart` (a full-override day without its own service is now replaced; additive variant keeps
  it), `season_card_timing_test.dart` (the 50 Days additive in the overnight minute-by-minute test; the next-date
  parallel service now reads «وبعدها ١٢:٠٠ ص: …»). The ADR-050 P3/P6/P7 additive repros pass unchanged.

## ADR-054 (PR #48) — Season lists polish: sample exception days, past seasons hidden, Arabic day counts, long-replace warning, no repeated now-box service, balanced season pill

- **Context:** the seasons v2 round-3 simulation (`work/seasons-v2/r3/phase1–7/report.md`, code at `aa544ab`) left
  one PARTIAL and five low observations. **P3 item 9 (PARTIAL):** the undated sample `rev-moses-3` (Wed 18:30) stays
  listed in the /mass-schedule seasonal section and the prompt's weekly "Holy seasons" list beside the owner's
  revival dated only Wed 23 Jun at the same hour — correct by ADR-053 (it is really held on Wed 30 Jun) but with no
  hint that it is not held on 23 Jun. **O-1:** the card read «بعد ٢ أيام». **O-2:** /mass-schedule (and the prompt)
  listed seasons already over (Nativity and the January revival on Good Friday). **O-3 (risk):** the Pascha preset
  default ticks «صلوات الموسم تحل محل الجدول الأسبوعي»; on the 50-day window that cancels every regular mass for 50
  days (ADR-053). **P7 12:30:** with the main fasting liturgy in the «يُقام الآن» box, the next card (youth liturgy
  13:00) repeated it as «وفي نفس الوقت: الكنيسة الكبرى (عام)». **P5 O-d:** the season chip «جدول موسمي مُفعّل: عيد
  النيروز (رأس السنة القبطية ١٧٤٤ ش)» wrapped leaving «ش)» alone.
- **Decision:**
  1. **Exception days (item 9).** `seasonListExceptions(l, s, all, {seasons, from})` (`schedule.dart`) returns the
     days of the window on which an undated `sample` kept by `liturgyInSeason` is hidden behind another active
     season's real service (`_otherSeasonServiceHiding`, the same rule as `_sampleHiddenByOtherSeason` / the day
     views), with that service; days before `from` (today) are skipped. /mass-schedule (seasonal view and the
     additive "active now" section) shows a muted pill «لا يُقام ٢٣ يونيو» / "Not held 23 Jun" (`notHeldOn`, key
     `notHeldOn`, `formatDayMonth`) on that card; the prompt line gets "(not on 2027-06-23: replaced by <name>)".
     Hidden on every matching day = dropped, as in ADR-053.
  2. **Arabic day counts (O-1).** `context.inDays(n)`: 1 «غدًا», 2 «بعد يومين», 3–10 «بعد ٣ أيام», 11+ «بعد ١١ يومًا»
     (Arabic-Indic digits); English unchanged ("In n days"). `context.dayCount(n)` for counts in sentences.
  3. **Past seasons (O-2).** `seasonalSchedule(..., {now})` leaves out a season whose `endsAt` is before the start of
     the Cairo day of `now` (`seasonEndedBeforeToday`; a season ending later today stays until midnight; it still
     counts as `context`). /mass-schedule's seasonal view and the prompt's "Holy seasons" pass `now`.
  4. **Long replace warning (O-3).** `presetReplaceDays(season, options, now)`: when the preset ticks
     replaceRegular, or the season already replaces, and the window (from the later of its start and now) is longer
     than 3 days, the apply dialog shows an alert box «تنبيه: هذا الموسم سيُلغي كل القداسات المعتادة لمدة ٥١ يومًا؛
     لن يظهر أي قداس من الجدول الأسبوعي حتى نهايته. لإبقاء القداسات المعتادة أزِل علامة «صلوات الموسم تحل محل
     الجدول الأسبوعي».» / EN (key `presetReplaceLongWarn`); when the season doc itself already replaces, the text says
     to turn off «يستبدل الجدول العادي» in «المواسم» (`presetReplaceLongWarnStored`). No warning without a start or an
     end (such a season replaces only on its service days). The apply transaction re-checks the warning against the
     fresh season and refuses (`PresetConflict(replaceChanged)`, «تغيّرت تواريخ الموسم…») when it changed. Stored
     preset defaults are unchanged (the owner decides).
  5. **No repeat (P7 12:30).** `NextMassResult.shownInNowBox(o, opts)`: the next card's «وفي نفس الوقت» / «وبعدها»
     lines leave out an occurrence already named in the now box (`happeningNow` or one of `alsoRunning`); other
     parallel services stay.
  6. **Balanced season pill (P5 O-d).** `Pill(balanced: true)` → `BalancedText`: when the label wraps it takes the
     narrowest width that keeps the same number of lines, so the last line is never a lone word; one line = plain
     `Text` (no stretching). Used by the active-season chip; owner text untouched (no digit or name change).
- **Review (CodeRabbit on PR #48):** stored-replace warning variant, apply-time re-check, no warning without a start,
  full-duration compare, day-count phrases in the string catalog, exception scan from today, the «لا يُقام» pill wraps
  freely, a balanced pill never accepts a width that truncates past `maxLines`. Not changed: exception days for an
  **open-ended** season (no finite window; ADR-053 keeps open-ended seasons out of the cross-season list check) and a
  warning for open-ended replacement (it replaces only on its service days).
- **Rules:** unchanged. **Data:** no field, no write; seed unchanged.
- **Firebase cost:** +0 reads, +0 writes, +0 listeners (client logic on the already-loaded liturgies / seasons; the
  re-check reads the season doc the apply transaction already reads).
- **Tests:** `test/season_lists_polish_test.dart` (exception day + prompt + both /mass-schedule views, AR/EN; Arabic
  counts; past seasons in lists / prompt / page; `presetReplaceDays` + the dialog AR/EN, unticked = no warning; the
  12:30 repro + a third service still named; balanced pill). Screenshots `work/fixall/D/png/` (390 px AR).

## ADR-055 (PR #49) — Seasonal list empty state («لا توجد مواسم حالية» + next season)

- **Context:** the seasons v2 round-4 simulation showed an empty screen on /mass-schedule with the «المواسم والأعياد
  الكنسية» switch on while no season was in effect (all ended — hidden since ADR-054 — or none started yet): only the
  generic «لا توجد بيانات حاليًا», or nothing useful. Owner approved a friendly empty state (6 Nov 2026 16:17).
- **Decision:**
  1. When the seasonal view is on and `activeSeasonsAt(seasons, now)` is empty, the page shows `EmptyState`
     (key `noCurrentSeasons`, icon `event_available_rounded`) «لا توجد مواسم حالية» / "No current seasons".
  2. `nextUpcomingSeason(seasons, now)` (`schedule.dart`, pure): the enabled (`active`) season with the earliest
     `startsAt` after now; disabled, started, ended and undated seasons are skipped. When there is one, a second line
     (`EmptyState.detail`, key `emptyStateDetail`, palette `primary`, bold) reads «الموسم القادم: صوم الميلاد — يبدأ ٢٥
     نوفمبر» / "Next season: Nativity Fast — starts 25 Nov" (`formatDayMonth`, Arabic-Indic digits; `formatDate` with the
     year when the start is in another Cairo year). Strings `noCurrentSeasons`, `nextSeasonLine` in `l10n.dart`.
  3. An upcoming season that already has services stays listed below the notice (unchanged since ADR-054); with no
     listed season the notice replaces the generic empty state. A season in effect now: no notice. An active season
     without services keeps the generic «لا توجد بيانات حاليًا».
  4. **Not admin-configurable (choice):** a settings field would touch model + admin schema + rules + seed (golden
     rule 3) for two short sentences; fixed i18n strings (AR + EN) are enough. Can move into `settings/features`
     later if the owner wants other wording.
- **Theme:** palette roles only (`muted`, `primary`); no hard-coded colour (the `lib/ui` colour test stays green).
- **Rules:** unchanged. **Data:** no field, no write; seed unchanged.
- **Firebase cost:** +0 reads, +0 writes, +0 listeners (uses the seasons the page already watches).
- **Tests:** `test/season_empty_state_test.dart` (`nextUpcomingSeason`; AR + EN with and without an upcoming season;
  no seasons; next season in another year carries its year; upcoming season with services listed under the notice;
  a current season shows no notice). Screenshot `work/fixall/wtE-empty-state.png` (390 px AR).

## ADR-056 (docs PR) — Phase 2 architecture: notifications & mobile apps (plan only)

- **Context:** owner request 6 Nov 2026 17:29–17:47 (Arabic): notifications for what each visitor wants (verse, season
  starts, feasts, occasions / mass reminders, announcements) on web, Android and iPhone; admin web-only manages types,
  texts, times, lead times, scheduled one-offs and deep links; users opt in per type; Android = APK from the site (no
  Play Store), iPhone = installed PWA (no App Store); local notifications on the phone where possible; an install
  prompt on the web with OS detection; responsive; small size; complete UX per feature; a handoff-ready plan; feature
  PRs as a stacked chain merged only after the whole chain is approved.
- **Decision (details in [`docs/plans/phase2/`](../plans/phase2/README.md)):**
  1. **Delivery:** Android schedules verse / seasons / feasts / occasions **locally** (`flutter_local_notifications`,
     14-day horizon, inexact alarms, no exact-alarm permission) from data it already loads; admin announcements and
     every web notification go through **FCM topics** (`app_announcements_<lang>`, `web_<type>_<lang>`), sent by a
     scheduled **GitHub Actions** job (`push-sender.yml`, every 15 min, honest 15–30 min latency) — no Cloud
     Functions (Spark).
  2. **Config:** new top-level keys of the existing `settings/features` doc (install banner fields, `push` default
     off, `pushVapidKey`, `pushTypes`, `notifyTypes`, `notifySchedule`, `pushSent`), admin-only writes, +0 visitor
     reads / listeners. Device-only user choices (types, quiet hours, inbox, token).
  3. **Web push:** lazy `push_client.js` + `firebase-messaging-sw.js` at a private scope (nothing on page load;
     messaging JS ignored at boot via `flutterfire_ignore_scripts`); browsers subscribe through a create-only
     `push_queue` (throttled) drained by the sender with the Instance ID API (token-list fallback documented);
     iPhone only as an installed PWA on iOS 16.4+.
  4. **APK:** split-per-abi (arm64 + arm32), R8, obfuscation, admin compiled out (`kIsWeb`), assistant opens the web
     `/ask`, published on **GitHub Releases** (Hosting egress on Spark too small), update prompt via
     `installApkBuild`; release signing from GitHub secrets (owner creates and backs up the keystore). Android
     developer verification (global in 2027) must be completed before it reaches Egypt.
  5. **Process:** stacked chain PR 0 (plans) → A (ADR-057) → B (ADR-058) → C (ADR-059) → D (ADR-060) → E (ADR-061);
     each draft, reviewed (@coderabbitai, @sentry, ≤ 2 rounds), CI green, not merged; after owner approval merged
     bottom-up with squash, merging `main` into the next branch (no rebase, no force-push) — `HANDOFF.md` §5.6.
- **Cost:** A, B, E +0; C ≤ 96 reads + ~10 writes/day (sender); D 2 writes per web opt-in + sender read/delete.
- **Rules / data / seed:** unchanged in this PR (docs only).

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
| 3 Nov 2026 | **PR #20** — "Assistant: ground the first question on live data (mass times & all sections), App Check warm-up, one retry" (`fix/assistant-grounding-load`; PR #19 was squash-merged as `d2d1ee2`) | Root cause: Riverpod 3 pauses unlistened providers, and `/ask` only `ref.read` the content providers, so on a direct visit the content never arrived and the prompt had empty sections. Fix: `_watchGrounding()` watches every grounding provider (section-gated for milestones / contact / custom); `AssistantModel.warmUp()` pre-mints the App Check token; one automatic retry of a failed / empty model call, not for quota / rate-limit / bad-request errors (`isRetryableAssistantError`, CodeRabbit). Widget tests assert the first prompt holds the mass schedule, meetings, activities, services, priests, saints, milestones, contacts, clinics, custom sections and custom pages (donations), plus the contact form heading; the individual contact types are asserted by the prompt-builder unit tests. |
| 3 Nov 2026 | **PR #21** — "Assistant: safe Markdown, confident data answers, St-Takla-only faith source, 3 questions / device / day, no default chips" (`fix/assistant-markdown`; PR #20 was squash-merged as `8dd2680`) | ADR-030/031: `SafeMarkdown` renderer (no literal asterisks, safe links only, RTL by content, selection kept); prompt rewrite (no disclaimers on data answers, `mentionUnconfirmed` switch default off, faith questions outside the data → `[[SOURCE_SEARCH]]` → faith reply + `site:st-takla.org` search + `/contact`, "not listed → /contact", simple Markdown only); `perDay` device limit (shared_preferences), `showSuggestions` default off, `sourceDomains`, `faithReplyAr/En`; `validAssistant` + emulator cases; `test/safe_markdown_test.dart`, `test/assistant_test.dart`. |
| 3 Nov 2026 | **PR #22** — "Hero: no address pill by default, verse of the day without the panel" (`fix/hero-verse-address`; PR #21 was squash-merged as `79c7d9c`) | ADR-032: hero ribbon = admin subtitle, or the address only with the new `heroShowAddress` admin switch (default off; rules + emulator test); `HeroVerse` without `WarmPanel`, old fixed-verse typography on a 0.88 text scrim; `verseGrounds` in the palette contrast checks for every preset incl. Holy Week; widget tests (no panel, no address by default, switch on, subtitle wins). |
| 3 Nov 2026 | **PR #23** — "Custom sections, cold deep links and contact types: wait for live data; admin menu icons" (`fix/custom-content-loading`; PR #22 was squash-merged as `a29beaa`) | ADR-033: `settleFirst` + `fallbackDelay` for categories / entries / pages (no premature «غير متاحة», no endless placeholders), `confirms` for the settings docs (admin contact types reach `/contact`), re-keyed contact dropdown, fingerprinted icon fonts (`tool/fingerprint_icon_fonts.py` in ci/deploy), admin nav `Material` + consistent selected colours, assistant icon `smart_toy_outlined`; `test/live_loading_test.dart`. |

| 3 Nov 2026 | **PR #24** — "Sentry error tracking (web + Android), privacy first, admin switch" (`feat/sentry-error-tracking`; PR #23 was squash-merged as `93db6c7`) | ADR-034: `sentry_flutter` 10.3.0, `ErrorReporting.run` around start-up, DSN define / public default, environments `production` / `preview` / `ci` / `debug`, release `church-portal@version+sha7`, `scrubEvent` / `scrubBreadcrumb` / JS gate, captures in `guardSeeded`, assistant (`AssistantFailure`, redacted) and contact submit, `settings/features.errorReporting` switch (rules + emulator test + seed), owner-only Send test error; `test/error_reporting_test.dart`. |
| 4 Nov 2026 | **PR #26** — "App bar: no Clinics shortcut (owner request)" (`fix/appbar-no-clinics`; PR #24 was squash-merged as `d60261d`) | Owner request: the public app bar never shows the Clinics (`local_hospital_rounded`) action, at any width or section state; **Mass times** is the only highlight button. It used the same `sections.clinics` switch (`routeEnabled('/clinics')`, phones only) — live `sections.clinics` was `true` when checked. Clinics stay in the drawer / Services menu, Home directory and footer quick links; route, page, admin unchanged. `test/feature_gate_test.dart` group guards the bar. |

| 4 Nov 2026 | **PR #25** — "Docs: memory bank up to date + Arabic feature documentation" (`docs/feature-documentation`; PR #26 was squash-merged as `8886d08` first and merged into this branch) | ADR-035: memory bank re-checked against `d60261d` (assistant limits / suggestions / unconfirmed flags in `05-firebase.md`, clinics placeholders deleted 3 Nov + section off 4 Nov, create-only seeding re-creates deleted docs, bundled fonts, Sentry account facts, open tasks); new `documentation/` (Arabic): index, architecture, one file per feature, operations; README / AGENTS / CLAUDE link it with the same-PR rule. **ADR-036:** YouTube hero video library removed (admin card, `hero_video.dart`, `hero_youtube*.dart`, `youtube_player_iframe`; legacy `heroVideos` kept in rules, live data untouched). |
| 4 Nov 2026 | **PR #29** — "PageSpeed: same hero, CSS ambient layer on web, lazy App Check, static first paint, crawler files" (`perf/pagespeed-green`; PR #27 was squash-merged as `b7e5ed2`, PR #28 closed unmerged) | ADR-037: hero haze + ray shimmer as a CSS-animated DOM layer on web (`hero_ambient*.dart`, `HeroAmbientSpec`), App Check activated on the assistant's first use (`ensureAppCheckActivated`), static hero poster + church name splash, `Intl.v8BreakIterator` → `Intl.Segmenter` shim, seal 178 → 27 KB, Hosting regex rewrites (real 404s for missing files, dotted slugs / ids still load) + COOP, `web/llms.txt`, `--source-maps`; `test/pagespeed_test.dart`. |

| 4 Nov 2026 | **PR #30** — "Footer bundled-data note, sitemap from Firestore, loading screen until real content" (`fix/footer-sitemap-loading`; PR #29 was squash-merged as `5a6a44c`) | ADR-038: `SeedGate.markSeeded` / `whenSeeded` (the `settings/church` listener proves seeding for every stream; empty collections / missing optional docs no longer strand the footer note), `sitemap.xml` generated read-only from Firestore in `deploy.yml` (`tool/export_public_content.js`, `tool/gen_sitemap.dart`, `lib/domain/sitemap.dart`, static fallback), loading screen kept until `app-content-ready` (9 s cap), hero video / CSS motion started at page idle; `test/sitemap_test.dart`, `test/content_ready_test.dart`, new groups in `content_guard_test.dart` / `pagespeed_test.dart`. Second commit (live-check follow-ups): footer hides «العيادات» until the switches load, live query started before the seeding check + custom fallback delay counted from the subscription (missing custom / detail pages settle in ≤ ~13 s instead of 15–24 s), English image alts and Latin-only times in English, `test/live_check_followups_test.dart`; CodeRabbit fixes to `tool/build_sitemap.sh` and the docs. |

| 4 Nov 2026 | **PR #31** — "Coptic calendar, top event of the day, live banner" (`feat/coptic-calendar-today-live`, on `905cd04` = PR #30 + the owner's roadmap doc) | ADR-039 / ADR-040: `coptic_calendar.dart`, `sun.dart`, `coptic_feasts.dart`, `today.dart`, `synaxarium_source.dart`, `today_widgets.dart` (strip, live banner, top event card), liturgical-day verse and eve labels, /admin «اليوم والبث المباشر», `synaxarium.yml` + `tool/fetch_synaxarium.js` + `tool/publish_hosting_file.js`, footer note debounce (`SteadySeedNote`), time-zone labels removed from the UI; tests `coptic_calendar_test.dart`, `today_widgets_test.dart`, rules group. |

| 4 Nov 2026 | **PR #32** — "Programme details: speaker, topic, choir, venue, audience, Drive PDF link" (`feat/programme-fields`) | ADR-041: `program.dart` (`ProgramInfo`, `ProgramOptions`), `parallelServices`, `ProgramDetails` widget, audience chips on the seasonal schedule, meeting detail facts, admin programme group + «إعدادات المواسم» (venues / audiences), rules `programKeys` / `validProgram` / `validProgramOptions`; `test/program_test.dart`, rules group. |
| 4 Nov 2026 | **PR #33** — "Season presets, season verses, assistant season limit, hero v2" (`feat/season-presets`) | ADR-042: `season_preset.dart` + /admin «تجهيز الموسم» (apply / restore in one transaction, auto-revert at the season end without a write), `season_verses.dart` + «آيات المواسم» in «إعدادات المواسم», assistant `perDaySeason` / section-aware topics / current season in the prompt, `weddingBookingOff`, hero v2 9 s loops + posters, `AdminBackend.saveDocs` / `saveDocsFresh`; `test/season_preset_test.dart`, rules group. |
| 5 Nov 2026 | **PR #38** — "Simulation fixes: season services on the next-service card, programme while running, top event from tonight's programme, assistant grounding" (`fix/season-programme-sim-bugs`) | ADR-045: next-service card counts every active season's service (additive revivals too) and titles non-mass services «الصلاة القادمة»; «يُقام الآن» keeps the programme; top event falls back to today's / tonight's programme service (`topEventServices`, default on) and day events get their own labelled PDF (`attachmentUrl` / labels); assistant grounds speaker / topic / choir / PDF, church events, the live link and says wedding bookings are paused; seed `sample` templates never mix into a season with real services (both season types; additive: overlap per day); `perMinute` hint; rules: `topEventServices`, day-event regex tail. +0 reads / listeners. |
| 5 Nov 2026 | **PR #37** — "Occasion sub-themes follow the season; no violet; Holy Week fixes" (`fix/occasion-themes-holy-week`) | ADR-043: Holy Week charcoal / ashen silver / crimson, fasts ash / stone / oxblood, legacy `purple` → oxblood (hidden), every widget on palette roles + scene accents and the Material scheme filled from the palette (test bans hard-coded colours), theme follows the active season (`occasions.followSeason` + `seasonThemes`; admin range > season > Easter > selected), preset item «ثيم الموسم» + `startsAt`, season keys epiphany / marian / fast, Holy Week sim fixes B1–B5 (B4 per day) + `kids` alias, rules budget restructure (joined-regex slot check), +1 seasons listener app-wide while following the season. |
| 5 Nov 2026 | **PR #36** — "Admin: reset the settings form when switching between Today and Season settings" (`seer/fix/admin-season-settings-switch-crash`, opened by Sentry Seer; PR #37 was squash-merged as `644ce8c` and merged into this branch) | Bug fix for Sentry CHURCH-PORTAL-9: both menu entries edit `settings/features` with different fields; the dashboard reused one unkeyed `ChurchInfoScreen` and `didUpdateWidget` compared only `doc.path`, so «إعدادات المواسم» read Today's `DocEditor` state and crashed on `_rows['venues']!`. Fix: per-section `ValueKey`s + rebuild when the `DocDef` changes. Regression tests: screen-level swap and a dashboard navigation test (both fail on `main` without the fix). No data, rules or listener change; no ADR (bug fix). |
| 5 Nov 2026 | **PR #35** — "Liturgical web loading screen, top utility bar with live badge, app shell cleanup" (`feat/redesign-splash-top-bar`; PR #37 (`644ce8c`) and PR #36 (`98dc546`) were squash-merged and merged into this branch) | ADR-044 (renumbered from ADR-043): cream loading screen with the app's 27 KB seal, Lalezar name and a composited gold track (`web/index.html`); `TopUtilityBar` (alias `CopticDateStrip`) above the app bar on the palette's title band with the Coptic date and a `live`-coloured badge (`topBarLiveBadge`), grows with text; seal tab offset by the bar height; while live Home shows only the red banner and other pages the tappable badge (admin switch `liveBadgeHideOnHome`, default on); merge fixes: palette roles instead of hard-coded colours, `HaloText` back to 2.5 px, synaxarium live-URL fallback removed (no CORS on live); tests `pagespeed_test.dart`, `today_widgets_test.dart`. Not merged until the owner approves the visuals. |
| 5 Nov 2026 | **PR #39** — "Live user test fixes" (`fix/live-test-findings`) | ADR-046: top event only on the stored `settings/features` (`featuresLiveProvider`, no seed flash); boot script in `web/index.html` sets the English title / `lang` and drops FlutterFire's saved reCAPTCHA provider (App Check on /ask only again); `accent_about` «كنيستنا»; sample badges / banner / «times pending» removed from the public UI (`sample` kept in data and admin); `fetch_synaxarium.js` computes a missing Coptic date; pope-visit images as Hosting WebP files. +0 reads / listeners / writes. |

| 5 Nov 2026 | **PR #40** — "English verse of the day" (`feat/verse-english`) | ADR-047: `Verse.textEn` + `display(english:)` (English text LTR, else Arabic with the Arabic reference); `gen_daily_verses.py` adds the public-domain WEB British Edition (SHA-pinned) for the same 366 verses; optional `textEn` / `refEn` for the fixed verse and a `␟textEn␟refEn` tail for season verses in `settings/features` (`encodedOptionalTail`); rules `validDailyVerse` / `validSeasonVerses`. +0 reads / listeners. |
| 5 Nov 2026 | **Docs PR** — "English documentation suite & README overhaul" (`docs/english-readme-and-documentation`) | ADR-048: English documentation suite (`documentation/en/README.md`, `architecture.md`, `operations.md`, `features.md`), modernized root `README.md` with tech stack badges, framework icons, and architecture diagrams; cross-references in `documentation/README.md`, `AGENTS.md`, and `docs/memory-bank/00-README.md`. |
| 5 Nov 2026 | **PR #42** — "Season card timing" (`fix/season-card-timing`) | ADR-049: «يُقام الآن» names the services running now in other halls (`runningNow`, `alsoRunning`); overnight services audited and pinned (Easter night, Kiahk, Apocalypse, DST), parallel services compared across midnight (`occurrencesAround`), assistant says an overnight service ends the next morning; /mass-schedule seasonal switch from palette roles at ≥ 3:1 in every theme; additive day-to-night handover tested minute by minute; admin time / date pickers (12-hour AM/PM picker with a 12-hour reading, stored 24-hour `HH:mm`, `YYYY-MM-DD`, stored types unchanged). +0 reads. |
| 5 Nov 2026 | **Docs PR** — "README screenshots" (`docs/readme-screenshots`) | Docs only, no ADR: `screens/` now holds 4 shots: Home, Mass schedule and Ask (live site, Arabic, 390 px @2x) plus the admin dashboard overview (1280 px, real `AdminDashboard` rendered from the local Firestore-emulator export, no live sign-in); the 8 broken desktop shots from PR #41 removed; README "Visual Showcase" is one row of public shots plus an "Admin dashboard" shot. No code change. |
| 5 Nov 2026 | **PR #45** — "Seasons v2 fixes A: season schedule overlap" (`fix/season-schedule-overlap`) | ADR-050: additive seasons hide only overlapping regular masses, `liturgies.replacesDay` (admin checkbox) for a feast liturgy; samples (dated too) give way once their season has real services, never supersede / outrank a real service of any season, real before sample; `regularSupersededOn` → /mass-schedule «لا يُقام اليوم» + prompt "Services today and tomorrow" and computed season labels; now box «حتى …»; seed placeholder text stripped on read and from the seed; `web/media/milestones/pope-visit-gallery5.webp` (live field change prepared, not applied); hero season tint (`heroSeasonTint`); «،» kept. +0 reads. |
| 6 Nov 2026 | **PR #44** — "Season keys, exceptional quota, church calendar in the assistant" (`feat/season-keys-assistant`) | ADR-051: season keys `apostles`, `nayrouz` (+ the Cross), `kiahk`, `great_lent` (`SeasonKeys.all` = rules `seasonKeyList()`; fasting / festive palettes); `settings/assistant.exceptionalSeasons` chips (default + Great Lent, Kiahk, Marian); prompt «Church calendar» line (Coptic date + feast, loaded Katameros only); Arabic digits in the limit message; /ask greeting and chips skip hidden sections; preset live end = tonight's last service + 30 min (editable); `seasons.replaceDates` feast-night override (date chips); fast presets untick weddings; Holy Week day names in the top bar; EN pages use `liveLabelEn` or a generic label. +0 visitor reads / listeners. |
| 6 Nov 2026 | **PR #46** — "Church milestones on the About page" (`feat/about-milestones`) | ADR-052: shared `MilestoneCard` (`lib/ui/widgets/milestone_card.dart`) for Home «قصتنا» and a new «محطات الكنيسة» section on `/about` after the history & altars; `settings/features.aboutMilestones` (default on) with an indented admin switch under the milestones section; milestone detail Back → About while listed there; rules key + bool check. +0 writes / new listeners; direct /about landing opens the existing milestones listener. |
| 6 Nov 2026 | **PR #47** — "Season replace window, cross-season samples in lists, later parallel line" (`fix/season-replace-window`) | ADR-053: a full-override season with exact dates replaces every regular service in its window, also on days without its own service (Good Friday no longer shows the weekly Divine Liturgy; holds with the seed samples deleted); season lists / prompt weekly list drop a sample hidden behind another active season's real service on every matching weekday; next-service card names a later parallel service with its time («وبعدها ٠٧:٠٠ ص: …»); switch subtitle mentions fasts. +0 reads / writes / listeners. |
| 6 Nov 2026 | **PR #48** — "Season lists polish" (`fix/season-lists-polish`) | ADR-054: a listed undated sample states the days another season's real service replaces it («لا يُقام ٢٣ يونيو», prompt "(not on …: replaced by …)"); seasons ended before today leave /mass-schedule and the prompt; «بعد يومين» / «بعد ١١ يومًا»; preset dialog warns when a season replaces the weekly schedule for more than 3 days (defaults unchanged); the next card never repeats a service named in the «يُقام الآن» box; balanced season chip. +0 reads / writes / listeners. |
| 6 Nov 2026 | **PR #49** — "Seasonal list empty state" (`fix/season-empty-state`) | ADR-055: /mass-schedule seasonal view with no season in effect shows «لا توجد مواسم حالية» / "No current seasons" and, when an enabled season starts later, «الموسم القادم: صوم الميلاد — يبدأ ٢٥ نوفمبر» (`nextUpcomingSeason`, `EmptyState.detail`); fixed i18n strings (not admin-configurable). +0 reads / writes / listeners. |

Append new PRs to this table.
| 6 Nov 2026 | **Phase 2 plans** (`docs/phase2-plans`, docs only) | ADR-056: `docs/plans/phase2/` — README (architecture, data contract, cost, decisions), HANDOFF (workflow, stacked chain, merge procedure), STATUS (checklists), PR A–E plans, LAUNCH-AND-OPERATIONS (consoles, keystore, user guidance, privacy, device tests, rollback, monitoring, runbook, launch day). No code. |
