# 06 — Features & business rules

All public pages live under `lib/ui/pages/`, are wrapped by `AppShell` + `FeatureGate` (see `03-architecture.md`) and
render with `PageBody` (+ `Footer`). Content comes from Riverpod providers (hidden items already removed, sorted by
`order`).

## Public pages

### `/` Home — `home_page.dart` `HomePage`
- **Hero** (`_Hero`, always first, branch `design/coptic-identity`): parchment ground; start column = kicker
  «كنيسة قبطية أرثوذكسية», title (`heroTitleAr/En` or the church name, display face), place line (`heroSubtitleAr/En`
  or the address), verse with a gold start rule, CTAs **Mass times** (primary) + **About the church** (outlined; Contact
  if About is off) — each only if its route is enabled. End column = the **arcade**: the first two `saints` in
  gold-leaf `ArchFrame`s (the admin `heroImageUrl` takes the large arch), tapping opens the saint page; no image /
  saints or images off → arches hold the drawn Coptic cross. A plaster "ledge" closes the hero.
- **Patrons teaser** (`_PatronsTeaser`, key `home-patrons`): placed before the first of milestones/directory/map
  (not yet an admin-orderable block: that needs a `settings/features` rules change, PR-18 of the UX plan). Two saint
  cards (small arch, name, 3 lines of the life, «التفاصيل»), hidden when `saints` or `/about` is off.
- Then the **home blocks** in `features.visibleHomeBlocks` order (admin-reorderable/hideable):
  | Block | Widget | Needs section |
  |---|---|---|
  | `banner` | `_AnnouncementBanner` (admin text + optional "Learn more"; an in-app link to a switched-off section is dropped) | `bannerEnabled` + text |
  | `alerts` | `AlertBanner` (2 highest, "show all N" toggle; an in-app link to a switched-off section shows no "Learn more", BUG-09) | alerts |
  | `nextMass` | `NextMassCard` | schedule |
  | `quickContacts` | `_QuickContacts` (first 3 phones, call + WhatsApp for mobiles) | contactInfo |
  | `milestones` | "Our story" `_MilestoneCard` grid (icon by `icon`, year in local digits) | milestones |
  | `directory` | `DirectoryCard` grid from `_directory` (mass, clinics, education, activities, services, about, contact) + "Ask the church" when visible; cards for disabled routes are skipped | — |
  | `map` | `ChurchMap` (iframe + Open in Maps + Directions) | contactInfo |
  On wide screens (≥ 900 px) adjacent `nextMass` + `quickContacts` share a row.

### `/about` — `about_page.dart` `AboutPage`
- History card (bishop line + `historyAr/En`) and **altars** grid (main altar gets a gold cross) — section `history`.
- Patron saints cards (name, feast pills Coptic + Gregorian, bio) — section `saints`.
- Priests (`PriestCard`: avatar/photo, name (`nameEn` in English if set), rank «قمص/قس», ordination date, hegumen
  date, repose date «تاريخ النياحة / Departed» (`departedDate`, BUG-08), bio, `SampleBadge`) — section `priests` (status ≠ departed); departed fathers on a cream card — section
  `departedPriests` (shown only if any).

### `/mass-schedule` — `mass_schedule_page.dart` `MassSchedulePage`
- `AlertBanner`, `PendingConfirmationNote` if any liturgy is `sample`, `NextMassCard`.
- **Holy Seasons** switch (`holySeasons`): defaults to **on** the first time seasons load only while a season that
  **replaces** the regular schedule is active (`activeSeasonsAt(seasons, now).any((s) => s.replacesRegular)`), so an
  additive evening revival keeps the weekly tabs; once the visitor flips it, their choice wins.
- Weekly view: `ChoiceChip` tabs **Friday | Sunday | Wednesday | Saturday | Other days** (`ScheduleTab`,
  `scheduleTabWeekdays`: other = Mon/Tue/Thu); today's Cairo weekday tab is preselected.
  `regularLiturgiesForTab` = regular (no `seasonKey`, no `date`), weekday in tab, **excluding vespers/praise**;
  then a separate **Vespers & praise** section (`vespersAndPraise(all, now: now)`: weekly ones always, one-off dated
  ones from today's Cairo date on, or until their end when they run past midnight).
- **Active additive seasons** (PR 1): while an additive season (revival) is in effect, the weekly view opens and
  lists that season's services (evening services, feast liturgy) at the top, with an "Active now" pill. The weekly
  tabs remain the recurring timetable; the next-liturgy card applies the day's actual overrides (e.g. the feast
  liturgy instead of Thursday's mass on 1 July).
- **Upcoming special services** («صلوات ومناسبات خاصة قادمة», `specialServices`, PR 1): above the weekly tabs whenever
  `upcomingSpecialLiturgies(all, now)` is non-empty — dated liturgies with no `seasonKey`, not vespers/praise, from
  today's Cairo date on (a previous-day one stays while it is still running past midnight), sorted by date, start,
  order (e.g. New Year's Eve, a 40th-day memorial). Before PR 1 such
  services reached `NextMassCard` and the assistant but never `/mass-schedule` (BUG-02).
- Seasonal view: `seasonalSchedule(seasons, liturgies)` → **active seasons only** (`s.active`), each with the liturgies
  of its key; a dated liturgy is attached only when its Cairo day overlaps the season's `[startsAt, endsAt]` (so 2027
  and 2028 docs sharing a key never cross-attach); equal start times tie-break by `order` (BUG-03). Seasons in effect
  now are listed first, then the rest by `startsAt`; title + date range + "Active now" pill +
  `LiturgyCard(showDate: true)`.
- `LiturgyCard`: name, both digit systems (`TimeRangeText`), place, audience, weekday/date, `SampleBadge`.

### `/church-education` — `education_page.dart` `EducationPage`
- Meetings sorted by `stageOrder` (angels → elderly), then `order`, then start; grouped into
  **مدارس الأحد** (angels, primary, preparatory, secondary), **الشباب والجامعة والخريجون** (youth, university,
  graduates), **اجتماعات خاصة** (family, men, women, elderly), plus "Other stages" for unknown stage keys.
- Timeline item: a `Wrap` of stage pill (`stageLabels`), «اليوم / Today» pill when `m.weekday` is today's Cairo
  weekday (FR-E-03) and `SampleBadge` (wraps at 320 px instead of overflowing, BUG-11); name, weekday (goldText),
  both-digit time, hall, notes, Facebook/WhatsApp buttons (screen-reader label names the meeting).
- `PendingConfirmationNote` when any meeting is `sample`.

### `/church-activities` — `activities_page.dart` `ActivitiesPage`
- Cards sorted by `_categoryOrder` (service, choir, hymns, youth, servants, media, drama, scouts, deacons, bible,
  summer, sports, exhibitions; unknown last), stable within a category (admin order kept). Icon per category
  (`activityIcon`). Schedule, ages, "Open page" link (YouTube/Facebook styled), call + WhatsApp (mobiles only).

### `/clinics` (`?specialty=<key>`) — `clinics_page.dart` `ClinicsPage`
- Specialty chips from active clinics (`clinicSpecialties`, first-seen order) + "All"; the URL param pre-selects
  (and `didUpdateWidget` follows URL changes). "Available today" switch.
- `filterClinics`: active only, by specialty; **open today first**, then admin `order`, then specialty, then doctor.
- `ClinicCard`: specialty pill, "Available today" pill (`isClinicAvailableToday`: Cairo ISO weekday ∈ `days`),
  doctor, degree, days, time, **Call • Book** (`tel:`) and **WhatsApp** (`https://wa.me/20…?text=<booking message>`).
  When a clinic has **neither** booking phone nor WhatsApp, a **«الاتصال بمكتب الكنيسة / Call church office»**
  button calls the first church phone (`settings/church.phones`), only while section `contactInfo` is on (PR 1, J2).
  In English, a placeholder (`sample`) doctor name «… — يُعلن لاحقًا» is shown as "<specialtyEn> doctor — to be
  announced" (`ClinicCard.isPlaceholderDoctor` + l10n `doctorTba`); the stored Arabic name is unchanged (BUG-17).
- The seed ships section `clinics` **off** (PR 1): enable it in /admin → Sections only once the church office
  confirms the clinics.
- Subtitle `clinicsIntro` asks visitors to confirm with the church; `PendingConfirmationNote` if any clinic is sample.
- Link to `/public-services` when that section is on.

### `/public-services` — `public_services_page.dart` `PublicServicesPage`
- Clinics shortcut card (if clinics on) + facilities grid (`facilityIcon` by type, description, hours, call button).

### `/contact` — `contact_page.dart` `ContactPage`
- `_InfoColumn`: phones (`PhoneRow`, call + WhatsApp for `isMobile`) and address/transport (section `contactInfo`);
  social buttons — WhatsApp channel, WhatsApp chat, Facebook, YouTube, Instagram, each only if set (section
  `socials`). `ContactForm` (section `contactForm`). Map at the bottom (contactInfo). Info and form side by side
  on ≥ 900 px.

### `/ask` — `assistant_page.dart` `AssistantPage`
Chat UI with intro bubble, 3 suggestion chips, 500-char input, disclaimer «إجابات آلية قد تحتوي أخطاء». Shows
"assistant not available" when `assistantVisibleProvider` is false. Details in `05-firebase.md`.

### Item detail pages (PR #13, ADR-020) — `item_detail_page.dart` `ItemDetailPage`
- Routes: `/church-education/:id`, `/church-activities/:id`, `/clinics/:id`, `/public-services/:id`,
  `/about/priests/:id`, `/about/saints/:id`, `/about/milestones/:id` (shareable; `detailPathFor(kind, id)`).
- **Every visible item has one** (PR #14, ADR-021: opt-out — a missing `detailsEnabled` means on); an explicit
  `detailsEnabled: false` — or hidden / unknown id / inactive
  clinic — «هذه الصفحة غير متاحة حاليًا» + «العودة إلى …» (noindex). A departed father needs `departedPriests`, a
  serving one `priests` (else `SectionUnavailable`, noindex). Available pages are indexable with their canonical URL.
- Layout (320 px × 200 % safe, RTL/LTR): «العودة إلى <القسم>» link; `PageHeader` with the item title (clinics:
  specialty, doctor as subtitle; priests: rank); pills (stage / available today / rank + departed) and
  `SampleBadge` + `PendingConfirmationNote` when `sample`; hero cover (column width, 120–320 px, PR #14) and gallery
  thumbnails (104 px) **only when `showImages && showDetailImages`** — tapping any opens the zoomable
  `showImageViewer`; **«المعلومات الأساسية / Key information»** card (`Key('detailFacts')`, PR #14: labelled rows —
  icon, small label, value — Day / Time / Place / Notes for meetings, Schedule / Ages for activities, Doctor /
  Qualification / Days / Time for clinics, Hours for services, Ordained / Hegumen since / Departed for priests,
  Feast / Gregorian date for saints, Year for milestones; empty rows dropped); **quick actions** (`detailActions`,
  PR #14): «أضف إلى التقويم» (`detailAddToCalendar`, meetings with a weekday + start and clinics with days + start:
  Google Calendar template link, weekly `RRULE`, next occurrence, `ctz=Africa/Cairo`, location = church name +
  address, details = page URL — `weeklyCalendarUrl`), «الاتجاهات (GPS)» to the church (`detailDirections`, on-site
  items — meetings, activities, clinics, services — while `contactInfo` is on), «مشاركة الرابط» (`detailShare`,
  every page: copies `absoluteDetailUrl` — canonical origin, `?lang=en` in English — and shows «تم نسخ الرابط»); summary
  (desc/bio); long text `detailsAr/En` as `SelectableText` (line height 1.8); custom fields (`extraFields`) as cream
  cards in a `ResponsiveGrid` (title primary bold, value body text, `context.pick`).
- **Contact & registration** (when `showContacts`): Call `<phone>` (primary phone: `contactPhone`, clinics
  `bookingPhone`, facilities `phone`), WhatsApp chat (`whatsapp`; activities: also a mobile `contactPhone`, like
  their card; clinics pre-fill the booking message), clinics with neither fall back to «اتصل بمكتب الكنيسة» while
  `contactInfo` is on; the `contactNoteAr/En` box.
- **Links & pages** (when `showSocials && Sections.socials`): WhatsApp group/channel (`whatsappUrl`), Facebook,
  YouTube, Instagram, external/registration button (`externalUrl`, activities' `link`) labelled
  `externalLabelAr/En` or «افتح الصفحة». Every action has `actionSemanticLabel(action, itemTitle)`.
- No extra Firestore read for the item: it comes from the list stream. Gallery inline bytes (`media/{id}`) load only
  here; an inline cover loads on the listing card too (`CardImageLead` / `ItemImage` → `MediaImageView`) and is
  then served from `MediaCache` here.
- **«من نفس القسم / More in this section»** (`Key('detailRelated')`, PR #14): up to 3 other publicly listed items of
  the same collection, same group first (meetings: stage group; activities: category; priests: serving/departed),
  each a full-width row (`relatedLink-<id>`, ≥ 48 dp, chevron) to its page. Read from the same list stream.

### Card ↔ detail integration (PR #13)
- Since PR #14 every card has its page by default. `detailsEnabled: false` ⇒ that card has no link and no card
  tap (images still enlarge on tap).
- On (default) ⇒ a «التفاصيل ›» link (`DetailsLink`, `ValueKey('detailsLink-<id>')`, announced «التفاصيل — <title>»), the card
  surface opens the page (`DetailTapArea`: pointer-only `GestureDetector`, inner buttons keep their taps, no nested
  screen-reader button), and the small avatar no longer opens the viewer (`enlargeOnTap: false`; zoom lives on the
  detail page). Applies to meetings, activities, clinics, facilities, priests, saints and milestones ("Our story").
- Card buttons follow the item switches too: clinic call/WhatsApp/office fallback, activity phone and facility phone
  need `showContacts`; meeting Facebook/WhatsApp and the activity link need `showSocials && Sections.socials`
  (the activity link was previously shown even with socials off).
- Optional `image` now also on meeting and clinic cards (beside the title, `CardImageLead`) and facility cards (in
  place of the type icon); no image ⇒ identical card.

### Custom page headers & intro notes (PR #13)
- `CustomizablePageHeader(pageKey:)` on about, schedule, education, activities, clinics, services, contact and ask
  (incl. the "assistant unavailable" view): the admin's title / subtitle **for the current language** replace the
  built-in ones (an empty or other-language-only override keeps the built-in text). `PageIntro(pageKey:)`
  (`Key('pageIntro')`) at the top of the page shows `context.pick(introAr, introEn)` in a cream note card; nothing
  when both are empty.

### `/admin` — see `07-admin-dashboard.md`.

### Optional images (PR #5) — `ItemImage` / `MediaImageView` (`lib/ui/widgets/item_image.dart`)
- Where: priest + departed-father avatars (`PriestCard`, `/about`; legacy https `photoUrl` as fallback), patron
  saints (avatar beside the name), milestone avatars ("Our story" on `/`), activity thumbnails
  (`/church-activities`, replaces the category icon), alert thumbnails (`AlertBanner`, replaces the megaphone icon),
  season / revival picture beside the date range (seasonal view of `/mass-schedule`).
- **No image ⇒ the exact current look** (`ItemImage` returns its placeholder: person icon, category icon, milestone
  icon, megaphone, or nothing for saints/seasons). Same when the admin switches **Images** (`Sections.media`) off —
  `FeatureSettings.showImages`; nothing is fetched then.
- `url`/`storage` images: `Image.network` with `webHtmlElementStrategy: fallback` (hosts without CORS still show on
  the web). `inline` images: `MediaRepository.load(mediaId)` → `media/{id}` read lazily per card, cached in
  `MediaCache.instance` (in-memory LRU, 60 entries, failures retried). Fade-in (300 ms), placeholder while loading and
  on any error, semantic label = `alt` or the item's name, fixed square / circle sizes (no layout shift).
- Tap an image ⇒ `showImageViewer` dialog (pinch/scroll zoom, close button).
- The assistant never sees image data (cover `image`, `gallery` URLs, media ids or alt text — PR #11 test).

### Shared UI behaviours
- `SampleBadge` («بيانات تجريبية / Sample data») on any `sample: true` item; `PendingConfirmationNote`
  («مواعيد تقريبية — في انتظار تأكيد الكنيسة») on schedule, meetings and clinics pages.
- `AsyncSection` handles loading skeletons, empty and error (+ retry by invalidating the provider).
- Footer (FR-G-04, PR #13): church name, address (if contactInfo on), clickable church phone numbers
  (`Key('footerPhone-<number>')`, `footer.showPhones` and contactInfo on), official social icon buttons (48 dp,
  tooltips; `Key('footerSocial-whatsappChannel|whatsapp|facebook|youtube|instagram')`, `footer.showSocials` and
  socials on), quick links (mass, clinics, education, contact — enabled ones; `footer.showQuickLinks`), the admin
  note (`footer.noteAr/En`, `Key('footerNote')`), ©, and «تعرض البيانات المحفوظة مع التطبيق» while serving the seed.
  Defaults show phones, socials and quick links; phones and social icons wait for `settings/features`
  (`featuresReadyProvider`) so switched-off ones never flash.

## Feature toggles (`settings/features`, `lib/domain/features.dart`)

- 16 sections (`Sections.all`; the 16th, `media`, is not a page — it shows/hides all optional item images);
  **missing key = on**; before the doc loads and when it does not exist, everything is on.
- A switched-off section disappears from: home blocks/CTAs/directory, app-bar links, Services menu, drawer, footer
  links, cross-links (e.g. clinics ↔ public services), and the **assistant's grounding**. Its route renders
  `SectionUnavailable` («هذا القسم غير متاح حاليًا» + Back to home).
- Multi-section pages stay up while **any** of their sections is on (`routeSections`): `/about` (history, saints,
  priests, departedPriests) and `/contact` (contactInfo, socials, contactForm); the page hides the switched-off parts.
- `/` is never gated; unknown paths are always allowed by `routeEnabled`.
- **Prefix-aware (PR #11, `sectionsForPath`)**: detail sub-routes are gated by their parent section —
  `/clinics/*` (clinics), `/church-education/*` (meetings), `/church-activities/*` (activities), `/public-services/*`
  (services), `/about/priests/*` (priests or departedPriests), `/about/saints/*` (saints), `/about/milestones/*`
  (milestones); other sub-paths follow their top-level page. The routes exist since PR #13 (`ItemDetailPage`).
- `settings/features` also carries `pageHeaders` (per-page title / subtitle / intro overrides) and `footer`
  (FR-G-04 options) since PR #11 (model + rules; admin cards since PR #12; rendered since PR #13).
- Per-item visibility: `visible: false` items never reach public pages (`publicItems`).
- Gated pages wait for the first `settings/features` value (`featuresReadyProvider`) so switched-off content never
  flashes.
- Tests: `test/features_test.dart`, `test/feature_gate_test.dart`, `test/detail_pages_test.dart` (PR #13: routes,
  back navigation, detail gating/SEO/gallery/contacts, cards, page headers, footer).

## Business rules

### Next liturgy (`computeNextMass`, `lib/domain/schedule.dart`)
1. Convert *now* to Africa/Cairo (`CairoTime.fromInstant`; EET UTC+2 / EEST UTC+3 DST from the IANA database —
   never the device zone, never a hard-coded offset).
2. For each Cairo day, `occurrencesForDay` builds concrete occurrences:
   - A liturgy matches a day by one-off `date` (Cairo calendar date) or by `weekday`.
   - Occurrence = `start` … `end`; `end ≤ start` ⇒ crosses midnight (+24 h); no end ⇒ start + 120 min.
   - **Season replacement:** a seasonal liturgy (`seasonKey`) counts only if its occurrence **starts inside** an
     active season window with that key (`isSeasonActiveAt`: `active` flag on and instant within
     `[startsAt, endsAt]`). Then, by `Season.replacesRegular` (PR 1, BUG-01):
     - **Full override** (`true`: Holy Week, Pascha, Nativity; also any season doc without the field): regular
       liturgies are dropped if they start inside the window of a season that has at least one valid service that
       day (so morning masses before an 18:00 season start remain). Replacement is decided on **all** seasonal
       services (e.g. Holy Week Pascha hours suspend weekday masses), then filtered by type.
     - **Additive** (`false`: the Maximus and Moses revivals): the regular schedule stays. A regular `mass` is dropped
       only when the season also has a `mass` that day and the regular mass starts inside the window (e.g. the
       1 July feast liturgy `rev-moses-feast` supersedes Thursday's `thu-1`); a regular `vespers`/`praise` is dropped
       only when it overlaps in time one of the season's services that day (e.g. Saturday vespers 18:30 vs the 18:30
       revival service). Before PR 1 a revival erased every morning mass for 9 days and the next-mass card showed
       "no upcoming liturgies".
   - `effectiveLiturgiesForDay` simply returns `occurrencesForDay(…, dayOffset: 0)`'s liturgies, so the two can never
     disagree.
3. Default types `{'mass'}` (vespers/praise/other ignored unless `types` given).
4. "Happening now": any occurrence of yesterday (past midnight) or today with `start ≤ now < end`.
5. "Next": first occurrence with `start > now`, today first, then up to **7 days** ahead (`lookAheadDays`).
6. Card shows: active season pill, happening-now strip, day label (today / tomorrow / in N days) + weekday,
   countdown "starts in Xh Ym" (today only), name, both-digit times, place, audience, «مواعيد تقريبية…» if `sample`.
   Empty → «لا توجد قداسات قادمة خلال الأسبوع».
7. Refreshes every 30 s (`nowProvider`).

Tests: `test/domain_test.dart` "next mass" group (DST, midnight crossing, mid-day season start, inactive season, …),
"additive revival seasons" and "mass-schedule page lists" groups; `test/seed_test.dart` "next mass always resolves
on seed data" (**every day** 1 Nov 2026 → 1 Nov 2027, 366 days), "Holy Week 2027 dated services fall on their Cairo
day".

### Seasons (`seasons` collection)
Keys: `holy_week` (أسبوع الآلام / البصخة), `pascha` (عيد القيامة), `nativity` (عيد الميلاد), `revival_maximus`
(نهضة القديسين مكسيموس ودوماديوس), `revival_moses` (نهضة الأنبا موسى الأسود), `summer` (allowed key, no season seeded).
Seeded 2027 windows (Cairo): Nativity 6–7 Jan; revival Maximus 21–25 Jan; Holy Week 25 Apr 00:00 → 1 May 18:00;
Pascha 1 May 18:00 → 2 May 23:59; revival Moses 22 Jun → 1 Jul. Seasons must be re-dated each year (admin).
Admin field «يستبدل الجدول العادي» (`replacesRegular`, missing = on): keep it on for feasts/Holy Week, switch it off
for evening revivals.

### Coptic feasts used in content
- Sts Maximus & Domadius: **14 Tuba** (Maximus) and **17 Tuba** (Domadius) = **22 & 25 January** (one day later in a
  Gregorian leap year, e.g. 2028).
- St Moses the Black: **24 Paona** (martyrdom) = **1 July**.
- Nativity 7 Jan (eve liturgy 6 Jan night); Nativity Fast from 25 Nov; Palm Sunday 25 Apr 2027; Pascha 2 May 2027.
- Annual revivals: 5 days in January ending 25 Jan; ~10 days ~22 Jun → 1 Jul.

### Alerts (`visibleAlerts`, `lib/domain/rules.dart`)
Shown only when `active` and now ∈ `[startsAt, endsAt]` (open-ended if null); sorted by `priority` desc, then most
recent `startsAt`. Links: a single leading `/` = in-app route (`context.go`), `//…` or scheme = external.

### Clinics
`isClinicAvailableToday` (Cairo weekday ∈ days and active); `filterClinics` ordering as above; phones normalised for
`tel:` (`telLink`) and `wa.me` (`toInternationalDigits`: `0…` → `20…`, `+`/`00` stripped).

### Phones (`normalizeEgyptianPhone`)
Accepts Arabic-Indic/Persian digits, spaces, dashes, `+20`/`0020`/bare `20` prefixes. Valid: mobile `01[0125]` + 8
digits, Cairo `02` + 8, Alexandria `03` + 7, other governorates `0[4-9]` + 7–8, 5-digit hotlines `1xxxx`.
`isEgyptianMobile` gates WhatsApp buttons.

### Contact form (`validateContactForm`, `ContactRateLimiter`, `ContactForm`, rules)
- Name 2–80 (whitespace collapsed); phone (valid Egyptian) **or** email required; email RFC-ish ≤ 254; message 5–1000.
- Honeypot `Offstage` field: if filled, pretend success and send nothing.
- **Client throttle** (`ContactRateLimiter`, shared per session): ≥ 60 s between sends and ≤ 3 per hour → message
  «برجاء الانتظار N ثانية».
- **Server throttle** (rules): message + `meta/contact_rate {lastAt: serverTimestamp(), lastMsgId: <message id>}` in
  one batch; the rate doc may advance only every **10 s** globally and only together with a new message (SEC-01);
  rules re-validate every field; the public can never read messages.
- Outcomes: sent; **timeout** (15 s, PR 1 / BUG-06): «لم نتمكن من تأكيد الإرسال…» (`sendTimeoutRetry`), shown as an
  error and the **form keeps the visitor's text** (the queued batch may still be rejected by the server throttle, so
  delivery is never promised); unavailable (seed mode); failed.
- **Privacy notice + consent** (PR 3 of the review plan, FR-CT-06, Egyptian PDPL Law 151/2020): under the message
  field a notice (`privacyNotice`: name, contact details and message are read only by the church's authorized clergy
  and secretariat, solely to reply, never shared with anyone else; stored on Google Firebase, whose servers may be
  outside Egypt — disclosed after Codex review) and an **unticked** `CheckboxListTile` (`consentLabel`).
  `ContactFormInput.consented` (default `true` for non-UI callers; the form passes the box) → `ContactField.consent` /
  `ContactError.consentRequired` («برجاء الموافقة على إشعار الخصوصية لإرسال الرسالة») blocks sending and keeps the
  typed text. Consent is **not** written to Firestore (payload keys unchanged, rules untouched); the box is cleared
  after a successful send.
- Not implemented yet: retention clean-up (12 months).

### Time formatting (`time_format.dart`)
`formatTimeLatin("06:30")` → `06:30 AM`; `formatTimeArabic` → `٠٦:٣٠ ص` (ص/م); weekday names AR/EN (ISO index);
`formatDate` → `6 يناير 2027` (Arabic digits) / `6 Jan 2027`; `formatLooseDate` for priest dates.
