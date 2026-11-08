# Domain Layer

## Overview
The `lib/domain` package encapsulates the core domain models, calendar algorithms, liturgical calculation engines, rule validators, and business logic of the Church Portal application. In accordance with Golden Rule 2, this layer is built strictly as pure Dart without any dependencies on the Flutter UI framework (`package:flutter`) or Firebase client SDKs (`cloud_firestore`, `firebase_auth`, etc.).

Architecturally, `lib/domain` operates as the single source of truth for:
- **Temporal & Astronomical Foundations**: Africa/Cairo timezone authority, Coptic calendar conversions (Anno Martyrum), solar calculations (Alexandria sunset times), and liturgical feast computus.
- **Liturgical Operations & Services**: Mass schedules, weekly recurring versus dated special liturgies, seasonal suppression rules, and atomic season preset state planning.
- **Church Entities & Content Modeling**: Immutable data representations of altars, liturgies, meetings, clinics, priests, saints, milestones, alerts, and custom CMS categories and pages.
- **AI Assistant Context & Safety**: Grounding prompt generation for Gemini, token budget management, content redaction, out-of-scope intent detection, and device quota tracking.
- **Security, Validation & Telemetry Sanitization**: Egyptian phone and WhatsApp formatting, contact message validation, and aggressive PII scrubbing for Sentry error monitoring (ADR-034).
- **Reminders, Local Notifications & Mobile Lifecycle**: Perpetual weekly recurring reminder calculations, Android local notification scheduling plans, OEM battery diagnostic steps, and in-app APK update decision trees.

## Interface
There are no child subdirectories in `lib/domain`; all domain components are co-located within this directory.

### 1. Temporal & Liturgical Engine
- [`cairo_time.dart:CairoTime`](file:///c:/Users/Kerollos/church-portal/lib/domain/cairo_time.dart#L12-L68): Central timezone authority for Africa/Cairo. Key operations: `now()`, `today()`, `fromInstant(DateTime)`, `calendarDate(DateTime)`, `ensureInitialized()`.
- [`coptic_calendar.dart:CopticDate`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L15-L87): Coptic calendar representation supporting leap year calculations, month lengths, Anno Martyrum year tracking, and bidirectional Gregorian translation (`toGregorian()`, `fromGregorian()`).
- [`coptic_calendar.dart:DayStartModes`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L93-L98): Controls whether liturgical days flip at midnight or at local sunset (vespers start).
- [`coptic_calendar.dart:LiturgicalDay`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L104-L143): Cohesive pairing of civil Gregorian date and Coptic date context.
- [`coptic_calendar.dart:holyWeekDayName`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L182-L200), [`dayStartMinutes`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L206-L215), [`dayStartOn`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_calendar.dart#L217-L225): Liturgical boundary helpers.
- [`coptic_feasts.dart:FeastRank`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_feasts.dart#L8-L15) & [`coptic_feasts.dart:CopticFeast`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_feasts.dart#L18-L47): Liturgical feast ranking model (`majorLord`, `minorLord`, `apostolic`, `virgin`, `saints`).
- [`coptic_feasts.dart:copticFeastsOn`](file:///c:/Users/Kerollos/church-portal/lib/domain/coptic_feasts.dart#L56-L125): Computes active fixed and movable feasts for any Gregorian date via Coptic and Easter computus.
- [`sun.dart:sunsetUtc`](file:///c:/Users/Kerollos/church-portal/lib/domain/sun.dart#L26-L63) & [`sun.dart:sunsetLocalMinutes`](file:///c:/Users/Kerollos/church-portal/lib/domain/sun.dart#L65-L72): Deterministic NOAA solar equations for church coordinates (`churchLat` = 31.2565, `churchLng` = 30.0125).
- [`time_format.dart:formatTimeLatin`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L12-L29), [`formatTimeArabic`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L31-L47), [`formatRangeLatin`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L49-L50), [`formatRangeArabic`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L52-L53), [`weekdayName`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L55-L66), [`formatDate`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L68-L80), [`formatDayMonth`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L82-L83), [`formatLooseDate`](file:///c:/Users/Kerollos/church-portal/lib/domain/time_format.dart#L85-L101): Pure string and date formatting utilities.

### 2. Church Schedule, Liturgies & Seasons
- [`models.dart:Liturgy`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L112-L177): Core liturgy model supporting altars, recurrences, seasonal tags, dates, and times (`parseHm`).
- [`models.dart:Season`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L82-L110): Liturgical season definition with range boundaries, liturgical color, fast indicators, and suppression keys.
- [`models.dart:Altar`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L42-L58), [`Meeting`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L179-L219), [`Activity`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L221-L260), [`Clinic`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L262-L300), [`Facility`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L302-L336), [`Priest`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L338-L380), [`Milestone`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L382-L417), [`Saint`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L419-L459), [`Alert`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L60-L80), [`ChurchSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/models.dart#L48-L58): Immutable domain entities.
- [`schedule.dart:LiturgyOccurrence`](file:///c:/Users/Kerollos/church-portal/lib/domain/schedule.dart#L12-L73): Resolved liturgy event on a specific day; provides status queries (`isHappeningAt`, `alsoRunning`, `shownInNowBox`).
- [`schedule.dart:NextMassResult`](file:///c:/Users/Kerollos/church-portal/lib/domain/schedule.dart#L75-L83): Resolved pair of active mass and next upcoming service relative to an instant.
- [`schedule.dart:ScheduleTab`](file:///c:/Users/Kerollos/church-portal/lib/domain/schedule.dart#L180-L188): Day-filter groupings (`friday`, `sunday`, `wednesday`, `saturday`, `other`).
- Schedule filtering & resolution functions in [`schedule.dart`](file:///c:/Users/Kerollos/church-portal/lib/domain/schedule.dart):
  - `isSeasonActiveAt(Season, DateTime)` & `isSeasonActiveOnDay(Season, TZDateTime)`: Range checks.
  - `activeSeasonsAt(Iterable<Season>, DateTime)` & `nextUpcomingSeason(Iterable<Season>, DateTime)`: Current and pending seasons.
  - `regularLiturgiesForTab(Iterable<Liturgy>, ScheduleTab)`: Tabbed regular liturgy filtering.
  - `vespersAndPraise(Iterable<Liturgy>, {DateTime? now})`: Filters evening incense and praise services.
  - `upcomingSpecialLiturgies(Iterable<Liturgy>, DateTime)`: Gathers forward-looking dated masses.
  - `undatedSuppressedOn(Season, Liturgy, Iterable<Liturgy>, TZDateTime)`: Identifies regular weekly services suppressed by dated feast services.
  - `liturgyInSeason(Liturgy, Season, Iterable<Liturgy>, [Iterable<Season>])`: Assigns liturgies to liturgical seasons.
  - `parallelServices(Iterable<Liturgy>, [ProgramOptions?])`: Flags overlapping or concurrent masses.
- [`season_keys.dart:SeasonKeys`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_keys.dart#L8-L76): Canonical season identifier strings (`copticNewYear`, `holyCrossFeast`, `nativityFast`, `nativityFeast`, `jonahFast`, `greatLent`, `holyWeek`, `resurrectionFeast`, `holyFiftyDays`, `apostlesFast`, `stMaryFast`, `regular`).
- [`season_preset.dart:SeasonPreset`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_preset.dart#L36-L74), [`PresetOption`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_preset.dart#L12-L21), [`PresetRequest`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_preset.dart#L76-L86), [`PresetWrites`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_preset.dart#L106-L121): Reversible pre-season orchestration logic (`presetProblem`, `presetLiveEnd`, `planRestore`, `planSyncEnd`).
- [`season_verses.dart:SeasonVerses`](file:///c:/Users/Kerollos/church-portal/lib/domain/season_verses.dart#L8-L78): Season-specific scripture rotations (`versesFor`, `activeSet`).
- [`program.dart:ProgramInfo`](file:///c:/Users/Kerollos/church-portal/lib/domain/program.dart#L60-L109), [`ProgramOptions`](file:///c:/Users/Kerollos/church-portal/lib/domain/program.dart#L35-L58), [`ProgramOption`](file:///c:/Users/Kerollos/church-portal/lib/domain/program.dart#L12-L33): Service speaker, topic, choir, venue hall, and external PDF metadata.

### 3. Today, Synaxarium & Readings
- [`today.dart:TodaySettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L24-L64): Settings for the home page "Today" strip (`copticStrip`, `showLiturgicalDay`, `showFastBanner`, `showLiveStream`, `showReadings`).
- [`today.dart:DayEvent`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L66-L132): Dynamic church events displayed in the today banner.
- [`today.dart:SynaxariumData`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L156-L200) & [`today.dart:SynaxariumDay`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L134-L154): Coptic Synaxarium daily commemorations.
- [`today.dart:TopEvent`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L210-L248) & [`today.dart:TopEventKind`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L202-L208): Evaluates the most significant daily event (feast, synaxarium, or scheduled event).
- [`today.dart:isLiveUrl`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L330-L338) & [`programmeServiceAt`](file:///c:/Users/Kerollos/church-portal/lib/domain/today.dart#L340-L368): Resolves live stream status and ongoing services.
- [`readings.dart:DayReadings`](file:///c:/Users/Kerollos/church-portal/lib/domain/readings.dart#L8-L38), [`ReadingsSection`](file:///c:/Users/Kerollos/church-portal/lib/domain/readings.dart#L40-L68), [`ReadingItem`](file:///c:/Users/Kerollos/church-portal/lib/domain/readings.dart#L70-L115): Katameros liturgical readings structure (Vespers, Matins, Liturgy: Pauline, Catholic, Acts, Synaxarium, Psalm, Gospel).
- [`daily_verse.dart:Verse`](file:///c:/Users/Kerollos/church-portal/lib/domain/daily_verse.dart#L12-L37) & [`daily_verse.dart:DailyVerseConfig`](file:///c:/Users/Kerollos/church-portal/lib/domain/daily_verse.dart#L39-L74): Verse of the day rotation engine (`cairoDayOfYear`, `verseForDate`, `resolveDailyVerse`).

### 4. Visual Themes & Media Boundaries
- [`occasion_theme.dart:ThemePalette`](file:///c:/Users/Kerollos/church-portal/lib/domain/occasion_theme.dart#L18-L68): Mathematical color palette definition with APCA/WCAG contrast compliance helpers (`contrastRatio`, `relativeLuminance`, `ensureContrast`, `blendOver`).
- [`occasion_theme.dart:SeasonThemes`](file:///c:/Users/Kerollos/church-portal/lib/domain/occasion_theme.dart#L250-L320), [`ThemePresets`](file:///c:/Users/Kerollos/church-portal/lib/domain/occasion_theme.dart#L160-L220), [`OccasionConfig`](file:///c:/Users/Kerollos/church-portal/lib/domain/occasion_theme.dart#L322-L375): Theme mapping for church liturgical seasons and dynamic Easter computus ranges (`orthodoxEaster`).
- [`occasion_theme.dart:isVioletPurple`](file:///c:/Users/Kerollos/church-portal/lib/domain/occasion_theme.dart#L120-L135): Enforces church color discipline by detecting and barring prohibited purple/violet tones.
- [`image_style.dart:ImageStyles`](file:///c:/Users/Kerollos/church-portal/lib/domain/image_style.dart#L8-L28): Framing styles for optional entity imagery (`avatar`, `cover`, `card`).
- [`media.dart:MediaLimits`](file:///c:/Users/Kerollos/church-portal/lib/domain/media.dart#L12-L24) & [`media.dart:MediaImage`](file:///c:/Users/Kerollos/church-portal/lib/domain/media.dart#L38-L105): Inline byte limits for Spark hosting, validation (`isValidImageUrl`, `validateMediaBytes`), and orphan tracking (`orphanedDocMediaIds`).

### 5. AI Assistant Subsystem
- [`assistant_context.dart:buildAssistantInstruction`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_context.dart#L20-L132): Constructs the complete Gemini grounding system prompt from live church settings, models, and today's events, strictly respecting enabled feature toggles and token budgets.
- [`assistant_context.dart:churchCalendarLine`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_context.dart#L240-L260): Summarizes current liturgical date and fast status for grounding.
- [`assistant_conversation.dart:AssistantConversation`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_conversation.dart#L88-L158): Pure conversation manager tracking turn history, pending prompts, and response streams.
- [`assistant_conversation.dart:AssistantRateLimiter`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_conversation.dart#L45-L68): Sliding-window rate limiter preventing query flooding.
- [`assistant_conversation.dart:looksArabic`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_conversation.dart#L160-L168), [`isModelUnavailableError`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_conversation.dart#L170-L178), [`isOutOfScopeReply`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_conversation.dart#L190-L205): Text and error classification rules.
- [`assistant_quota.dart:DailyUsage`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_quota.dart#L15-L35), [`AssistantUsageStore`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_quota.dart#L37-L45), [`MemoryUsageStore`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_quota.dart#L47-L62): Daily question quota counting keyed to `cairoDayKey`.
- [`assistant_settings.dart:AssistantSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_settings.dart#L38-L165) & [`AssistantLimits`](file:///c:/Users/Kerollos/church-portal/lib/domain/assistant_settings.dart#L12-L36): Admin configuration for assistant behavior, seasonal limits, and model fallback chains.
- [`simple_markdown.dart:parseSimpleMarkdown`](file:///c:/Users/Kerollos/church-portal/lib/domain/simple_markdown.dart#L56-L125), [`MdBlock`](file:///c:/Users/Kerollos/church-portal/lib/domain/simple_markdown.dart#L32-L52), [`MdInline`](file:///c:/Users/Kerollos/church-portal/lib/domain/simple_markdown.dart#L18-L30): Sanitized, safe markdown parser tailored for assistant text formatting.
- [`pending_text.dart:hasPendingPlaceholder`](file:///c:/Users/Kerollos/church-portal/lib/domain/pending_text.dart#L32-L33) & [`pending_text.dart:stripPendingPlaceholders`](file:///c:/Users/Kerollos/church-portal/lib/domain/pending_text.dart#L35-L65): Strips unconfirmed data markers from public text and AI grounding prompts.

### 6. Features, CMS & Routing
- [`features.dart:Sections`](file:///c:/Users/Kerollos/church-portal/lib/domain/features.dart#L15-L78), [`HomeBlocks`](file:///c:/Users/Kerollos/church-portal/lib/domain/features.dart#L80-L135), [`FeatureSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/features.dart#L172-L360): Central feature switchboard controlling public visibility (`enabled`, `sectionsForPath`, `normalizeHomeOrder`).
- [`custom_content.dart:CustomCategory`](file:///c:/Users/Kerollos/church-portal/lib/domain/custom_content.dart#L22-L75), [`CategoryEntry`](file:///c:/Users/Kerollos/church-portal/lib/domain/custom_content.dart#L77-L125), [`CustomPage`](file:///c:/Users/Kerollos/church-portal/lib/domain/custom_content.dart#L160-L215), [`PageBlock`](file:///c:/Users/Kerollos/church-portal/lib/domain/custom_content.dart#L135-L158): Dynamic CMS categories, items, and page block representations.
- [`item_detail.dart:DetailKind`](file:///c:/Users/Kerollos/church-portal/lib/domain/item_detail.dart#L12-L35) & [`DetailState`](file:///c:/Users/Kerollos/church-portal/lib/domain/item_detail.dart#L50-L75): Gating rules, route patterns, and social link visibility for entity detail views (`detailPathFor`, `absoluteDetailUrl`).
- [`sitemap.dart:SitemapContent`](file:///c:/Users/Kerollos/church-portal/lib/domain/sitemap.dart#L12-L45) & [`sitemapXml`](file:///c:/Users/Kerollos/church-portal/lib/domain/sitemap.dart#L60-L95): XML sitemap generator filtering exclusively for public, enabled paths.

### 7. Contact Rules, Privacy & Diagnostics
- [`rules.dart:ContactFormInput`](file:///c:/Users/Kerollos/church-portal/lib/domain/rules.dart#L90-L115), [`ContactValidation`](file:///c:/Users/Kerollos/church-portal/lib/domain/rules.dart#L117-L135), [`ContactRateLimiter`](file:///c:/Users/Kerollos/church-portal/lib/domain/rules.dart#L155-L180): Contact validation, required consent flags, and in-memory rate limiting.
- Phone & clinic helpers in [`rules.dart`](file:///c:/Users/Kerollos/church-portal/lib/domain/rules.dart):
  - `normalizeEgyptianPhone`, `isValidEgyptianPhone`, `isEgyptianMobile`: E.164 normalization.
  - `whatsappLink` & `telLink`: Safe URI synthesis.
  - `isClinicAvailableToday` & `filterClinics`: Clinic weekday schedule filtering.
  - `isAlertVisible` & `visibleAlerts`: Date and visibility gating for alerts.
- [`contact_categories.dart:ContactCategory`](file:///c:/Users/Kerollos/church-portal/lib/domain/contact_categories.dart#L55-L105) & [`ContactSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/contact_categories.dart#L107-L165): Contact categorization, inbox grouping (`inboxBoxOf`), and subtype metadata.
- [`error_privacy.dart:redact`](file:///c:/Users/Kerollos/church-portal/lib/domain/error_privacy.dart#L35-L75), [`scrubText`](file:///c:/Users/Kerollos/church-portal/lib/domain/error_privacy.dart#L25-L33), [`scrubEventJson`](file:///c:/Users/Kerollos/church-portal/lib/domain/error_privacy.dart#L120-L160): Sentry PII redaction engine stripping sensitive keys, form contents, and user query strings.
- [`oem_guide.dart:OemBrand`](file:///c:/Users/Kerollos/church-portal/lib/domain/oem_guide.dart#L12-L30) & [`oemStepsForBrand`](file:///c:/Users/Kerollos/church-portal/lib/domain/oem_guide.dart#L55-L120): Android background execution battery-saving instructions across brands (Xiaomi, Samsung, Huawei, Oppo, Vivo).

### 8. Reminders, Notifications & Platform Lifecycle
- [`reminders.dart:Reminder`](file:///c:/Users/Kerollos/church-portal/lib/domain/reminders.dart#L30-L95), [`EventKey`](file:///c:/Users/Kerollos/church-portal/lib/domain/reminders.dart#L12-L28), [`ReconciledReminders`](file:///c:/Users/Kerollos/church-portal/lib/domain/reminders.dart#L115-L145): Event reminder scheduling, expiration checks (`isExpired`), and future fire time resolution (`nextFireTime`).
- [`notify_plan.dart:PlannedNotification`](file:///c:/Users/Kerollos/church-portal/lib/domain/notify_plan.dart#L50-L115) & [`notificationIdFor`](file:///c:/Users/Kerollos/church-portal/lib/domain/notify_plan.dart#L120-L135): Android local notification planning, recurrence interval computation, and 31-bit stable integer ID hashing.
- [`push.dart:PushSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/push.dart#L55-L95), [`PushPrefs`](file:///c:/Users/Kerollos/church-portal/lib/domain/push.dart#L110-L145), [`QuietHours`](file:///c:/Users/Kerollos/church-portal/lib/domain/push.dart#L97-L108): Notification topic configs, channel routing (`channelOf`, `isLocalOwned`), and quiet hours gating.
- [`app_install.dart:InstallSettings`](file:///c:/Users/Kerollos/church-portal/lib/domain/app_install.dart#L40-L75) & [`InstallOsInfo`](file:///c:/Users/Kerollos/church-portal/lib/domain/app_install.dart#L18-L32): Client OS detection, PWA / APK install link resolution, and iOS push compatibility gating (`iosTooOldForPush`).
- [`app_update.dart:UpdateManifest`](file:///c:/Users/Kerollos/church-portal/lib/domain/app_update.dart#L25-L65) & [`UpdateDecision`](file:///c:/Users/Kerollos/church-portal/lib/domain/app_update.dart#L67-L95): In-app Android APK update evaluation, version comparison, and SHA-256 integrity validation.

## Invariants
- **Pure Dart Isolation (Golden Rule 2)**: The package must never import `package:flutter/*` or Firebase SDKs (`cloud_firestore`, `firebase_auth`, `firebase_core`). All classes must be completely runnable and testable under the standalone Dart VM.
- **Africa/Cairo Time Authority (Golden Rule 2)**: All civil, astronomical, and liturgical time logic must evaluate through `CairoTime` (`Africa/Cairo`). UTC conversions and local device clocks must not dictate schedule calculations. Weekdays follow ISO 8601 (1 = Monday ... 7 = Sunday). Time strings strictly adhere to 24-hour `"HH:mm"`.
- **Feature Toggle Exclusion (Golden Rule 6)**: When a feature or section is toggled off in `FeatureSettings`, it must be excluded across the entire application domain—including navigation links, home blocks, drawer, footer, assistant grounding, and sitemaps.
- **Ecclesiastical Data Integrity (Golden Rule 1)**: Church data must never be fabricated. Placeholder markers indicating unconfirmed facts («— في انتظار تأكيد الكنيسة.») must be scrubbed from public outputs and AI contexts via `pending_text.dart:stripPendingPlaceholders`.
- **Perpetual Recurring Reminders (Golden Rule 2)**: Recurring reminders (`Reminder.recurring`) never expire and must perpetually advance forward weekly in Cairo time; notification lead times must clamp strictly to valid future intervals.
- **Zero-PII Telemetry Protection (Golden Rule 10 & ADR-034)**: User form contents, phone numbers, email addresses, query strings, and assistant chat bodies must be aggressively redacted by `error_privacy.dart` before error reports reach external services.
- **Liturgical Service Suppression**: A recurring undated liturgy that conflicts with a dated special mass or active season is suppressed via `schedule.dart:undatedSuppressedOn` to eliminate double-booking.
- **WCAG APCA & Color Discipline**: Occasion theme palettes must satisfy contrast minimums (`kBodyContrast` >= 4.5:1, `kNonTextContrast` >= 3.0:1) via `occasion_theme.dart:ensureContrast`. Purple and violet shades are strictly forbidden on ecclesiastical grounds (`isVioletPurple`).
- **Image Optionality (Golden Rule 9)**: Images are strictly optional across all entities. Missing images must never trigger errors, break serialization, or cause layout shifts.

## Side Effects
- **Disk & Network I/O**: None. `lib/domain` performs no disk writes, file system queries, HTTP requests, or database transactions.
- **External Side Effects**: None.
- **In-Memory Mutable State**:
  - `AssistantRateLimiter` (`assistant_conversation.dart`): In-memory timestamp sliding-window queue for client-side chat rate limiting.
  - `ContactRateLimiter` (`rules.dart`): In-memory timestamp sliding-window queue for contact form submission throttling.
  - `MemoryUsageStore` (`assistant_quota.dart`): In-memory key-value test store for device question counting.
  - All domain model instances (`Liturgy`, `Season`, `Meeting`, `Activity`, `Priest`, etc.) are immutable value objects.

## Verification
- Run: `flutter test`
