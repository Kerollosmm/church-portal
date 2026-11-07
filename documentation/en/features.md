# Master Feature Reference Guide

This document provides a comprehensive, feature-by-feature manual for all 31 capabilities of the Church Portal in English. It translates and unifies the individual feature guides found in [`documentation/features/`](../features/), detailing what visitors experience, how administrators manage each feature in `/admin`, the technical data models, and known limitations.

---

## Index of Features

1. [Home & Hero Section](#1-home--hero-section)
2. [Verse of the Day (Bilingual)](#2-verse-of-the-day-bilingual)
3. [Top Utility Bar, Coptic Calendar & Live Stream](#3-top-utility-bar-coptic-calendar--live-stream)
4. [Dynamic Occasion Themes](#4-dynamic-occasion-themes)
5. [Divine Liturgy Schedule & Holy Seasons](#5-divine-liturgy-schedule--holy-seasons)
6. [Programme Details (Speaker, Topic, PDF Notes)](#6-programme-details-speaker-topic-pdf-notes)
7. [Season Presets ("Prepare Season")](#7-season-presets-prepare-season)
8. [Church Education & Meetings](#8-church-education--meetings)
9. [Charity Medical Clinics](#9-charity-medical-clinics)
10. [About the Church: History, Altars, Priests & Saints](#10-about-the-church-history-altars-priests--saints)
11. [Historical Milestones ("Our Story")](#11-historical-milestones-our-story)
12. [Activities & Choirs](#12-activities--choirs)
13. [Public Parish Services](#13-public-parish-services)
14. [Urgent Alerts & Announcement Banner](#14-urgent-alerts--announcement-banner)
15. [Item Detail Pages](#15-item-detail-pages)
16. [Custom Sections (`/section/:slug`)](#16-custom-sections-sectionslug)
17. [Custom Page Builder (`/page/:slug`) & Donations](#17-custom-page-builder-pageslug--donations)
18. [Contact Form, Inbound Inbox & Anonymous Messages](#18-contact-form-inbound-inbox--anonymous-messages)
19. [Map, Transport & GPS Directions](#19-map-transport--gps-directions)
20. [Images & Inline Media Management](#20-images--inline-media-management)
21. [AI Assistant "Ask the Church" (`/ask`)](#21-ai-assistant-ask-the-church-ask)
22. [Administrative Dashboard (`/admin`)](#22-administrative-dashboard-admin)
23. [Section Feature Toggles](#23-section-feature-toggles)
24. [Custom Page Headers & Upgraded Footer](#24-custom-page-headers--upgraded-footer)
25. [Error Reporting & Sentry Observability](#25-error-reporting--sentry-observability)
26. [Search Engine Optimization (SEO)](#26-search-engine-optimization-seo)
27. [Bilingual Localization (Arabic / English)](#27-bilingual-localization-arabic--english)
28. [Progressive Web App (PWA) & Asset Caching](#28-progressive-web-app-pwa--asset-caching)
29. [Web Performance & PageSpeed Optimization](#29-web-performance--pagespeed-optimization)
30. [Accessibility & WCAG 2.2 AA Compliance](#30-accessibility--wcag-22-aa-compliance)
31. [Android Native Application & Play Integrity](#31-android-native-application--play-integrity)
32. [App Installation, Notification Preferences & Reminders](#32-app-installation-notification-preferences--reminders)

---

### 1. Home & Hero Section
- **Visitor Experience:** Immersive "Golden Hour" poster identity with authentic Coptic typography (Lalezar display titles, Aref Ruqaa verses). On modern browsers, a subtle looping ambient cloud and light-ray shimmer runs seamlessly. Features primary call-to-action buttons ("Mass times" and "About the church"), an arcade framing patron saints, and admin-orderable content blocks.
- **Admin Control (`/admin` → Sections & Home Page):** Customize hero title and subtitle in Arabic and English, toggle church address ribbon, toggle ambient motion/video, and rearrange or hide home blocks (Announcement banner, Urgent notices, Next-mass card, Quick contacts, Our story, Directory grid, Map).
- **Technical Implementation:** Rendered in `lib/ui/pages/home_page.dart`. On web, the ambient atmospheric shimmer runs as a hardware-accelerated CSS DOM overlay (`HeroAmbientLayer`) to maintain PageSpeed scores ≥ 90 without Flutter canvas repaints.
- **Season tint (ADR-050):** on an occasion theme (Marian blue, fasting ash, Easter red…) a still wash of the theme's colours lies over the golden painting; none on the default Golden hour or dark themes. Switch: `/admin` → theme card → "Season colour on the hero picture" (`heroSeasonTint`, default on). Ken Burns, haze and rays are unchanged.
- **Limits:** Video playback is intentionally disabled when the visitor has reduced-motion or data-saver preferences enabled.

### 2. Verse of the Day (Bilingual)
- **Visitor Experience:** Displays an inspiring Scripture passage integrated into the hero section with haloed typography. The verse automatically rotates daily at Cairo midnight across 366 curated public-domain verses. Switching the site to English displays the authentic World English Bible (British Edition) text with English book references (ADR-047).
- **Admin Control (`/admin` → Sections & Home Page):** Switch between daily rotating mode and a pinned fixed verse. When fixed verse is selected, administrators can provide custom Arabic text, English text, and references.
- **Technical Implementation:** Verses are bundled in `assets/verses/daily_verses.json` (Arabic Van Dyck + English WEB-BE). Resolved via `DailyVerseConfig` and `CairoTime.cairoDayOfYear()`.
- **Limits:** Editing the built-in 366-verse rotation pool requires editing `tool/gen_daily_verses.py` and recompiling the asset.

### 3. Top Utility Bar, Coptic Calendar & Live Stream
- **Visitor Experience:** A slim utility bar sits above the main navigation displaying the full Coptic liturgical date (e.g. «الأربعاء ٢٥ بابه ١٧٤٣ ش»). At 18:00 (or parish sunset), the liturgical day transitions to the Eve of the following day («ليلة الخميس»). During Holy Week the day's name replaces the weekday, computed from Coptic Easter (Palm Sunday, Holy Monday–Wednesday, Covenant Thursday, Good Friday, Joyous Saturday; e.g. «ليلة الجمعة العظيمة ٢٢ برموده ١٧٤٣ ش» / "Eve of Good Friday 22 Baramouda 1743 AM", ADR-051). When a live stream is active, a pulsing live indicator appears; English pages show the English live label or a generic "Live now", never the Arabic text (ADR-051).
- **Admin Control (`/admin` → Today & Live Stream):** Configure live stream status, broadcast URL (YouTube, Facebook, etc.), scheduled end time, custom live badge label, and toggle whether the compact badge hides on Home when the prominent banner is displayed.
- **Technical Implementation:** Powered by `lib/domain/coptic_calendar.dart` and `sun.dart` using astronomical calculations for Alexandria coordinates. Stored in `settings/features.today`.
- **Limits:** Does not calculate historical Coptic dates prior to 1 AM (Anno Martyrum).

### 4. Dynamic Occasion Themes
- **Visitor Experience:** The portal dynamically transforms its color palette to match the liturgical season. During Holy Week, the entire site shifts to somber charcoal black, ashen silver, and deep crimson. During the 50 Days of Resurrection, it shifts to brilliant ivory, Easter red, and radiant gold.
- **Admin Control (`/admin` → Sections & Home Page → Occasion Themes):** Enable or disable automatic season following, define custom date ranges, override accent colors with automated WCAG contrast validation, and select primary palettes.
- **Technical Implementation:** Implemented in `lib/core/theme.dart` and `lib/domain/occasions.dart`. Employs `ThemePalette` tokens (`context.pal.bar`, `ornament`, `notice`, `alert`).
- **Limits:** Hard-coded Material Purple is completely banned to respect liturgical solemnity.

### 5. Divine Liturgy Schedule & Holy Seasons
- **Visitor Experience:** Tabbed liturgy schedule (Friday, Sunday, Wednesday, Saturday, Other days) displaying bilingual times (Latin digits and Arabic-Indic numerals), celebrants, and halls. The "Next Liturgy" smart card highlights upcoming services within 7 days and displays a pulsing "Happening Now" status during services.
- **Admin Control (`/admin` → Liturgies & Seasons):** Full CRUD for regular liturgies, seasonal override liturgies, vespers, and praises. Assign halls, priests, and visibility.
- **Technical Implementation:** Schedule evaluation in `lib/domain/schedule.dart`. Active seasons take precedence over regular weekly schedules during their exact start and end windows (ADR-006).
- **Additive seasons & samples (ADR-050):** in a season that does not replace the regular schedule (fasts, revivals, the Holy 50 Days) a seasonal mass hides only the regular masses that overlap it in time; a seasonal service ticked "Replaces the day's regular masses (feast liturgy)" (`replacesDay`) hides every regular mass of its day. Hidden regular masses show "Not held today" on the weekly tab and the assistant reads the same list. A `sample` service never replaces or outranks a real one (any season), and a season's samples disappear once it has a real service. The "Happening now" box shows the end time ("Until 03:30 AM"). Seed placeholder text ("pending church confirmation") is treated as empty.
- **Full-override window and parallel wording (ADR-053):** a season that replaces the regular schedule (Holy Week, Pascha, Nativity) with both a start and an end replaces every regular service starting inside its window, also on a day where it has no service of its own (Good Friday no longer falls back to the weekly Divine Liturgy, with or without the seed sample docs); an open-ended one still replaces only on its service days. A sample of one season is left out of the season lists (and the assistant's weekly list) when a real service of another active season overlaps it on every matching weekday of its window. On the next-service card a parallel service that starts later is named with its time ("Then at 07:00 AM: Divine Liturgy — Main church (General)") instead of "At the same time". The seasonal switch subtitle now mentions fasts.
- **Season lists polish (ADR-054):** a sample service still listed in a season but not held on a given day, because another season's real service takes its time, shows "Not held 23 Jun" on its card on /mass-schedule (the assistant reads "(not on 2027-06-23: replaced by …)"). Seasons that ended before today are no longer listed on /mass-schedule or given to the assistant. The card's Arabic day label follows Arabic counts («بعد يومين», «بعد ٣ أيام», «بعد ١١ يومًا»). The next-service card no longer repeats a service already shown in the "Happening now" box. The active-season chip wraps into balanced lines (no lone last word). In «تجهيز الموسم», applying a season that replaces the weekly schedule for more than 3 days shows a warning in the confirmation ("this season will cancel every regular service for N days…"); the preset defaults are unchanged.
- **Seasonal empty state (ADR-055):** with "Liturgical seasons & feasts" switched on and no season in effect now (all ended or none started yet), /mass-schedule shows "No current seasons" and, when an enabled season starts later, "Next season: Nativity Fast — starts 25 Nov" (the year is added when it starts in another year). Upcoming seasons that already have services are still listed below. The wording is fixed in the app (Arabic and English), not an admin field.
- **Season keys (ADR-051):** `holy_week`, `pascha`, `nativity`, `epiphany`, `marian`, `fast` (general), `revival_maximus`, `revival_moses`, `summer`, plus `apostles`, `nayrouz` (Nayrouz through the Feast of the Cross), `kiahk` and `great_lent` (`lib/domain/season_keys.dart`, mirrored by `seasonKeyList()` in `firestore.rules`). The fasting keys use the fasting palette, Nayrouz the festive red one. An additive season can still replace the regular schedule on chosen days (`replaceDates`, e.g. the feast night), edited as date chips in the season form.

### 6. Programme Details (Speaker, Topic, PDF Notes)
- **Visitor Experience:** Liturgies, revivals, and spiritual meetings display rich programmatic details: guest speaker/bishop name, sermon topic, choir name, venue/hall, intended audience chips, and a direct link to download or view sermon PDF notes on Google Drive.
- **Admin Control (`/admin` → Content lists & Season Settings):** Input speaker, topic, choir, venue dropdown, audience target, and Google Drive attachment URL on any service or meeting document.
- **Technical Implementation:** Defined in `lib/domain/program.dart` as `ProgramInfo`. Validated against regex constraints in `firestore.rules`.

### 7. Season Presets ("Prepare Season")
- **Visitor Experience:** During major feasts or fasts, the site immediately adapts its banners, themes, seasonal verses, and program details without manual day-to-day reconfiguration.
- **Admin Control (`/admin` → Season Settings → "Prepare Season"):** A one-click administrative action that applies complete seasonal configurations (theme, announcement banner, seasonal verses, wedding booking suspension) in a single atomic transaction. Automatically reverts back when the season ends.
- **Technical Implementation:** Managed by `lib/domain/season_preset.dart`. Concurrency-safe writes executed via `AdminBackend.saveDocsFresh`.
- **ADR-051:** fasting seasons (general fast, Great Lent, Apostles' fast, Kiahk) hide wedding bookings by default; the live link's banner ends tonight (the season's last service tonight + 30 minutes, 23:59 if none; editable on the screen) instead of at the season end.

### 8. Church Education & Meetings
- **Visitor Experience:** Interactive timelines organized by age group (angels nursery, primary, preparatory, secondary, university, graduates, young professionals, family, women, seniors). Displays meeting days, times, church halls, and links to WhatsApp or Facebook groups.
- **Admin Control (`/admin` → Meetings):** Add or edit meeting details, assign age categories, reorder via drag-and-drop, toggle visibility, and upload cover images.
- **Technical Implementation:** Stored in the `meetings` collection. Filtered and sorted by the `order` attribute.

### 9. Charity Medical Clinics
- **Visitor Experience:** Dedicated healthcare portal with specialty filtering (dental, internal medicine, pediatrics, cardiology, etc.), "Available Today" badges calculated according to Africa/Cairo weekdays, direct phone call (`tel:`) buttons, and WhatsApp booking links.
- **Admin Control (`/admin` → Clinics):** Manage specialties, consulting physicians, consultation fees, active weekdays, and operational hours.
- **Technical Implementation:** Evaluated in `lib/domain/rules.dart`. Gated by `Sections.clinics`.

### 10. About the Church: History, Altars, Priests & Saints
- **Visitor Experience:** Detailed parish chronicle, consecrated altars, biographies of patron saints (Saints Maximus & Domadius, Strong St. Moses), and comprehensive directories of currently serving priests and departed parish fathers.
- **Admin Control (`/admin` → Church Info, Priests, Saints):** Edit founding history, manage priest ordinations, assign roles, upload portraits, and manage memorial entries.
- **Technical Implementation:** Backed by `settings/church`, `priests`, and `saints` collections.

### 11. Historical Milestones ("Our Story")
- **Visitor Experience:** A rich chronological timeline on the Home page highlighting pivotal events in parish history (laying the cornerstone, papal visits by Pope Shenouda III and Pope Tawadros II, consecrations). Since ADR-052 the same cards also appear on the About page as "Church milestones" («محطات الكنيسة»), after the history and altars; a milestone's Back link returns to About while they are listed there.
- **Admin Control (`/admin` → Milestones):** Add historical milestones with year stamps, narrative descriptions, display icons, and optional high-resolution photos. `/admin` → Sections & home page → under the milestones switch, "Also on the About page" (`settings/features.aboutMilestones`, default on); the Home block keeps its own home-layout switch.
- **Technical Implementation:** Stored in `milestones` collection. Rendered via the shared `MilestoneCard` (`lib/ui/widgets/milestone_card.dart`) on Home and About, both from the same `milestonesProvider` (no extra listener).

### 12. Activities & Choirs
- **Visitor Experience:** Directory of parish fellowship groups: St. Moses Scouts, St. Stephen Deacons School, David's Harp Hymns Institute, Bible Study fellowships, athletic clubs, and arts exhibitions.
- **Admin Control (`/admin` → Activities):** Manage activity rosters, age prerequisites, rehearsal times, and coordinator contact links.
- **Technical Implementation:** Stored in `activities` collection. Supports full detail pages.

### 13. Public Parish Services
- **Visitor Experience:** Public community resources: St. Mary Nursery, community employment services, St. Joseph Condolence & Event Halls, and the parish lending library.
- **Admin Control (`/admin` → Public Services):** Configure facility operational hours, booking contacts, requirements, and hall capacities.
- **Technical Implementation:** Backed by `facilities` collection.

### 14. Urgent Alerts & Announcement Banner
- **Visitor Experience:** High-priority banners for emergency announcements, schedule revisions, or urgent notices. Visitors can expand multi-alert feeds and click through to dedicated custom pages.
- **Admin Control (`/admin` → Alerts & Sections Editor):** Set banner text, urgency level (high/medium), active display date/time windows, and link destinations.
- **Technical Implementation:** Filtered in `lib/domain/rules.dart` to display only alerts where `startsAt <= now <= endsAt`.

### 15. Item Detail Pages
- **Visitor Experience:** Shareable deep-linked URLs for individual priests (`/priest/:slug`), saints (`/saint/:slug`), activities (`/activity/:slug`), and services (`/service/:slug`). Includes zoomable image galleries, key facts, add-to-calendar links, and social actions.
- **Admin Control (`/admin` → Doc Editor):** Enable or disable detail page creation per item. Configure multi-image galleries (up to 8 images) and custom metadata fields.
- **Technical Implementation:** Implemented in `lib/ui/pages/item_detail_page.dart`. Generates canonical URLs and dynamic Open Graph meta tags.

### 16. Custom Sections (`/section/:slug`)
- **Visitor Experience:** Dynamic dedicated sections (e.g., Youth Summer Trips, Spiritual Conventions) appearing seamlessly in the navigation bar and drawer menu.
- **Admin Control (`/admin` → Custom Sections):** Create custom sections with custom slugs, bilingual titles, menu visibility switches, and associated entries.
- **Technical Implementation:** Stored across `categories` and `entries` collections with prefix-aware route resolution.

### 17. Custom Page Builder (`/page/:slug`) & Donations
- **Visitor Experience:** Content-rich custom pages formatted with headings, text paragraphs, banners, external links, and official church donation information (Bank accounts, InstaPay handles, electronic wallets).
- **Admin Control (`/admin` → Custom Pages):** Visual block-based editor to assemble layouts without HTML knowledge.
- **Technical Implementation:** Stored in `pages` collection. Validated to prevent arbitrary script execution.

### 18. Contact Form, Inbound Inbox & Anonymous Messages
- **Visitor Experience:** Secure contact form supporting general inquiries, hall reservations (weddings/condolences), and anonymous spiritual suggestions or complaints with PDPL consent checkboxes.
- **Admin Control (`/admin` → Contact Messages):** Message inbox organized by category tabs. Admins can update booking statuses (New, Contacted, Confirmed, Declined), add internal staff notes, and call/email senders.
- **Technical Implementation:** Submissions written to `contact_messages` collection (create-only for public). Protected by honeypot fields and server-side rate throttling via `meta/contact_rate`.

### 19. Map, Transport & GPS Directions
- **Visitor Experience:** Interactive embedded Google Map highlighting the church sanctuary, landmark transport directions from Street 45 and El-Asafra station, and one-tap "Open in Maps" navigation buttons.
- **Admin Control (`/admin` → Church Info):** Update latitude/longitude coordinates, embedded map URL, and textual directions.
- **Technical Implementation:** Uses Flutter `HtmlElementView` iframe on web with fallback buttons for native maps applications.

### 20. Images & Inline Media Management
- **Visitor Experience:** Fast-loading, responsive WebP images across cards and galleries with smooth fade-in animations and placeholder fallbacks.
- **Admin Control (`/admin` → Doc Editor):** Direct browser image uploads (automatically resized to ≤ 800px and compressed to ~250 KB) or external HTTPS image URLs.
- **Technical Implementation:** Bypasses Google Cloud Storage billing constraints by storing base64 image strings in Firestore's `media/{id}` collection, fetched lazily by client widgets.

### 21. AI Assistant "Ask the Church" (`/ask`)
- **Visitor Experience:** Grounded conversational assistant answering visitor queries about liturgy times, meetings, priest contacts, and church directions in Arabic or English. Non-church or theological queries are politely declined or routed to St. Takla theological search.
- **Admin Control (`/admin` → AI Assistant):** Toggle assistant availability, specify Gemini model (defaults to `gemini-3.1-flash-lite`), adjust system persona prompts, define allowed topics, and configure per-device question caps, including which season kinds raise the daily cap ("Exceptional seasons" chips; default Holy Week, Pascha, Nativity, both revivals, Great Lent, Kiahk, Marian seasons — ADR-051).
- **ADR-051:** the prompt carries a "Church calendar" line (the Coptic liturgical date, rolling over at 18:00 / sunset, and the feast of the day from the already-loaded Katameros data or the computed feast list); the built-in greeting and suggestion chips skip sections switched off; the Arabic limit message uses Arabic-Indic digits.
- **Technical Implementation:** Built with Firebase AI Logic (Gemini API). Client requests are verified via reCAPTCHA Enterprise / Play Integrity App Check tokens.

### 22. Administrative Dashboard (`/admin`)
- **Visitor Experience:** Invisible to regular visitors and blocked from search engine indexing (`noindex`).
- **Admin Control:** Comprehensive management portal with responsive desktop sidebar and mobile navigation drawer. Provides audit timestamps (`updatedAt`, `updatedBy`) on every save.
- **Technical Implementation:** Authenticated via Firebase Auth. Protected by Firestore security rules checking role assignments in `admins/{uid}`.

### 23. Section Feature Toggles
- **Visitor Experience:** Instantaneous, graceful removal of disabled features from menus, drawers, footers, directory cards, and AI assistant grounding contexts without site downtime.
- **Admin Control (`/admin` → Sections & Home Page):** Independent on/off toggles for all 15 major portal sections.
- **Technical Implementation:** Managed in `settings/features` and resolved reactively via Riverpod `featuresProvider`.

### 24. Custom Page Headers & Upgraded Footer
- **Visitor Experience:** Atmospheric page headers with custom liturgical sub-titles, and a comprehensive footer featuring parish contact details, social links, quick directory, and copyright data.
- **Admin Control (`/admin` → Page Headers & Footer):** Customize header intro text per route and toggle footer quick-link visibility.
- **Technical Implementation:** Configured in `settings/features.pageHeaders` and `settings/features.footer`.

### 25. Error Reporting & Sentry Observability
- **Visitor Experience:** Seamless error recovery; uncaught exceptions render friendly fallback cards without crashing the browser session.
- **Admin Control (`/admin` → Error Reporting):** Master toggle to enable or disable Sentry telemetry; diagnostic "Send Test Error" trigger for owners.
- **Technical Implementation:** Integrated via `sentry_flutter` with client-side PII scrubbing stripping visitor names, emails, phones, and assistant queries.

### 26. Search Engine Optimization (SEO)
- **Visitor Experience:** Rich link previews with parish branding and accurate titles when shared on WhatsApp, Facebook, or iMessage.
- **Admin Control:** Content edits automatically reflect in item-level meta descriptions and titles.
- **Technical Implementation:** Static canonical tags, Open Graph tags, verified `Church` JSON-LD structured data in `web/index.html`, and automated Firestore `sitemap.xml` builds.

### 27. Bilingual Localization (Arabic / English)
- **Visitor Experience:** Fully responsive layout switching seamlessly between right-to-left (RTL) Arabic and left-to-right (LTR) English via the top navigation toggle.
- **Admin Control:** Admin dashboard supports bilingual input for titles, descriptions, and content fields.
- **Technical Implementation:** Implemented in `lib/core/l10n.dart`. User preference is persisted in browser `localStorage` and synchronized via URL parameter (`?lang=en`).

### 28. Progressive Web App (PWA) & Asset Caching
- **Visitor Experience:** Installable as a home-screen web app on Android, iOS, and desktop with official parish seal icons; falls back gracefully to bundled seed data if Firebase is unreachable.
- **Technical Implementation:** Configured via `web/manifest.json` and optimized cache-control headers on Firebase Hosting. Note: The web app shell is served with `no-cache` to ensure instantaneous deployment rollouts; full offline service-worker shell caching without an initial network fetch is an open task.

### 29. Web Performance & PageSpeed Optimization
- **Visitor Experience:** Instantaneous initial paint (≤ 0.8s) and smooth 60fps scrolling across mobile and desktop devices.
- **Technical Implementation:** Employs static HTML loading shells, CSS-animated ambient layers, font fingerprinting, and deferred JavaScript execution to achieve 90+ PageSpeed ratings.

### 30. Accessibility & WCAG 2.2 AA Compliance
- **Visitor Experience:** Full compatibility with screen readers (TalkBack, VoiceOver), high-contrast text modes, large text scaling (up to 200%), and keyboard navigation.
- **Technical Implementation:** Strict adherence to 48dp minimum touch targets, automated color luminance contrast verification, and explicit accessibility semantic labels.

### 31. Android Native Application & Play Integrity
- **Visitor Experience:** Native Android APK installable on mobile devices with adaptive launch icons and hardware back-button navigation.
- **Technical Implementation:** Built with Flutter Android embedding. Release builds currently use debug signing; setting up a dedicated release keystore and registering its SHA-256 for Google Play Integrity App Check is an open operational task.

### 32. App Installation, Notification Preferences & Reminders
- **Visitor Experience:**
  - **Install banner (`InstallBanner`):** phone browsers only (Android and iOS/iPadOS), 4 s after the content arrives; hidden on desktop, in the installed app / standalone mode, on `/admin` and while the menu drawer is open. Android: with an APK link, «تحميل التطبيق» (version • size) downloads it and opens the 5-step sideload guide (browser warning, open the file, allow this source once, Play Protect, open) with a safety box; optional «هاتف قديم؟» link for the 32-bit APK. Without an APK link the browser's own install prompt is used when available, else a two-step sheet (⋮ → Install app / Add to Home screen). iPhone/iPad: a 3-step Add-to-Home-Screen sheet, never a notification prompt. «لاحقًا» hides it for `installRemindDays` (default 3 days), ✕ for `installReshowDays` (default 30 days, 0 = never); stored on the device. After `appinstalled` it stays hidden for that browser session; on Chrome Android `getInstalledRelatedApps()` clears that flag if the app was uninstalled.
  - **Notification preferences (`/notifications`, own web chunk):** explainer, permission state (granted / blocked how-to / unsupported / in-app browser / iPhone install-first with the iOS 16.4 requirement / iOS older than 16.4), per-type switches filtered by platform (web: announcements, seasons, reminders; daily verse, Katameros and feasts are on Home), unsubscribe-all. The «تفعيل الإشعارات» button stays disabled with "coming soon" until a delivery path ships (PR D), whatever the VAPID key. Quiet hours are stored in the visitor's prefs (22:00–07:00) but have no UI in this PR.
  - **Reminders («ذكّرني»):** on liturgy / next-service / today's event cards and meeting / clinic detail pages, when `push` is on and `reminders` is offered. The sheet shows the occurrence in Cairo time, the admin's leads (past ones disabled; the default falls back to the longest still-valid lead; save disabled when none is left), «هذه المرة فقط» / «كل مرة» for weekly items. A «كل مرة» reminder never expires: it rolls forward weekly at the same Cairo wall time. «تذكيراتي» on `/notifications` lists them by next fire time; swipe or button to cancel; «مسح المنتهية»; max 30 per device. A storage failure is reported in the sheet instead of a false success. Nothing is delivered yet (PR B / PR D).
- **Admin Control (`/admin` → «التطبيق والإشعارات» / "App & notifications"):**
  - **Install banner:** `installPrompt` (on/off), `installTitleAr/En`, `installBodyAr/En`, `installAndroidUrl` and `installAndroidUrl32` (https URL or a root-relative path on our Hosting), `installApkVersion`, `installApkBuild`, `installApkSizeMb`, `installApkSize32Mb`, `installReshowDays` (default 30), `installRemindDays` (default 3).
  - **Notifications:** `push` (master switch, default off: hides `/notifications`, the drawer link and every «ذكّرني»), `pushVapidKey` (used from PR D), `pushTypes` (offered types; an explicitly empty list offers none), `reminderLeads` (up to 4 of 0/5/10/15/30/60/120/180/1440; default 0/15/60/1440), `reminderDefaultLead` (default 60; must be one of the leads — the form refuses otherwise). No admin quiet-hours fields.
- **Technical Implementation:** `lib/domain/app_install.dart`, `push.dart`, `reminders.dart`; `ReminderStore` (device only). The notifications page, the reminder sheet + «تذكيراتي», and the install guides are deferred imports with their own string tables, so `main.dart.js` carries only the banner and the «ذكّرني» button. `settings/features` is public to read and admin-only to write; the rules check the 18 ADR-057 fields only when a key outside the legacy list changes, so other saves (worst-case page headers, hero videos, day events) stay under Firestore's 1,000-expression cap.
- **Limits:** no delivery yet (PR B Android alarms, PR D web push); same-tab stale "installed" flag on browsers without `getInstalledRelatedApps()` until the tab closes; recurring reminders are weekly on one weekday.
