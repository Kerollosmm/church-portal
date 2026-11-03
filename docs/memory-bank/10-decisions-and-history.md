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

## ADR-022 (revised 3 Nov 2026; draft, preview only) — "Golden hour" visual identity (branch `design/coptic-identity`, PR #15, not merged)

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
- **Status:** draft PR #15 with preview channel `pr-15`; direction doc `docs/design/direction.md`; board
  `work/design/poster/`. Needs the team's approval before merge (the burgundy preset value changes to `#6E1C1C`).

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
| 3 Nov 2026 | **PR #15 (draft)** — "Design preview: Golden hour identity" (`design/coptic-identity`) | Poster identity (ADR-022 revised): Lalezar + Aref Ruqaa, maroon `#6E1C1C`, ribbons, halos, Gemini art, hero motion + video behind `heroMotion`; image display styles avatar/card/banner (ADR-023) with rules + emulator tests; layout pass (1/2/3-column grid, 1200 max width, `Space` tokens, collapsing optional fields); `test/golden_hour_test.dart`, `test/image_style_layout_test.dart`. Not merged. |

Append new PRs to this table.
