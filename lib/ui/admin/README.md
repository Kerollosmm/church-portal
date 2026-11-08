# admin

## Overview
The `admin` package implements the authenticated back-office management console located at the hidden `/admin` route. It provides administrative controls, content management, and configuration editors for all church operations (liturgies, activities, education, clinics, media, settings, and seasonal themes). Built on pure schema descriptors (`admin_schema.dart`) and pure validation rules (`admin_validators.dart`), it bridges user input with Cloud Firestore persistence, enforcing strict Firestore security rule expression limits, atomic updates, and bilingual Arabic/English localization.

## Interface
- `admin_page.dart`:
  - `AdminPage`: Top-level authenticated entry point widget managing authentication state check, language switcher, and responsive dashboard navigation.
  - `LanguageToggle`: Bilingual toggle button switching the admin workspace between Arabic (RTL) and English (LTR).
  - `AdminDest`: Value object representing an administrative navigation destination (tab label, icon, and screen builder).
  - `AdminDashboard`: Responsive administration dashboard scaffold managing navigation rail, drawer, and tab content switching.
- `admin_schema.dart`:
  - `FieldType`: Enumeration defining schema field types (`string`, `multiline`, `integer`, `decimal`, `boolean`, `time`, `date`, `dateTime`, `looseDate`, `url`, `phone`, `select`, `image`, `imageList`, `list`, `blocks`, `options`).
  - `FieldGroup`: Visual grouping categories for form fields (`basic`, `program`, `details`, `media`, `contacts`).
  - `FieldDef`: Metadata descriptor defining validation patterns, constraints, field groups, and row dependencies.
  - `CollectionDef`: Configuration model defining schemas, sort orders, search keys, and access controls for managed collections.
  - `DocDef`: Configuration model defining singleton configuration documents (`settings/church`, `settings/assistant`, `settings/features`).
  - `seasonKeys`: Immutable array of all recognized liturgical season identifiers.
  - `imageCollections`: List of collection names permitted to store and render images.
  - `adminCollections`: Master schema registry defining all administrative collections.
  - `churchInfoDoc`: Singleton schema definition for church contact details, address, and priest directory.
  - `assistantSettingsDoc`: Singleton schema definition for AI assistant system prompts, feature switches, and safety limits.
  - `todaySettingsDoc`: Singleton schema definition for live streaming banner, strip toggles, and today's featured liturgical events.
  - `seasonSettingsDoc`: Singleton schema definition for seasonal theme overlays, color palettes, and header banners.
  - `appSettingsDoc`: Singleton schema definition for APK updates, app version requirements, and notification intervals.
- `admin_screens.dart`:
  - `OverviewScreen`: High-level metrics dashboard displaying content collection summaries and quick action links.
  - `ChurchInfoScreen`: Dedicated administrative form for church metadata, geographic coordinates, and social media links.
  - `MessagesScreen`: Message reader and triage viewer for incoming contact form submissions.
  - `AdminsScreen`: Administrator roster listing authorized email accounts and permission levels.
- `admin_validators.dart`:
  - `isCalendarDate(int y, int m, int d)`: Pure date validation verifying calendar existence, leap years, and month boundaries.
  - `isValidDate(String v)`: String date validator checking strict `YYYY-MM-DD` calendar format.
  - `isValidDateTime(String v)`: String timestamp validator checking strict `YYYY-MM-DD HH:mm` format.
  - `formatPickedTime(int hour, int minute)`: Clamps and zero-pads hours and minutes into `HH:mm`.
  - `formatPickedDate(int year, int month, int day)`: Formats year, month, and day into zero-padded `YYYY-MM-DD`.
  - `formatPickedDateTime(int year, int month, int day, int hour, int minute)`: Combines calendar date and Cairo time into `YYYY-MM-DD HH:mm`.
  - `parseFieldTime(String raw)`: Parses time strings (including Arabic-Indic numerals) into `(int, int)?`.
  - `parseFieldDateTime(String raw)`: Parses datetime strings into `(int, int, int, int, int)?`.
  - `isValidLooseDate(String v)`: Validates loose year/month/day dates (`YYYY`, `YYYY-MM`, `YYYY-MM-DD`).
  - `isValidUrl(String v, {bool allowPath = false})`: Validates http/https URLs and optional internal deep link paths.
  - `normalizePhoneInput(String v)`: Normalizes phone input by stripping whitespace and punctuation and converting Eastern digits.
  - `isValidPhone(String v)`: Validates phone numbers to ensure 5–15 valid digits.
  - `validateFieldValue(FieldDef f, String? raw)`: Validates raw input strings against field schema constraints, returning localization error keys or null.
  - `parseFieldValue(FieldDef f, String raw)`: Parses raw validated strings into stored Firestore scalar or instant representations.
  - `two(int n)`: Utility helper padding an integer with a leading zero.
  - `fmtDateTime(DateTime v)`: Formats a UTC instant into Cairo wall-time `YYYY-MM-DD HH:mm`.
  - `fmtDate(DateTime v)`: Formats a UTC instant into Cairo calendar date `YYYY-MM-DD`.
  - `validateRowAnyOf(FieldDef list, Map<String, String> row)`: Enforces at least one required subfield is populated in list rows.
  - `validateRowOrder(FieldDef list, Map<String, String> row)`: Validates that list row end dates do not precede start dates.
  - `validateRowUnique(FieldDef list, List<String> values, int index)`: Validates uniqueness of designated row keys across repeated rows.
  - `validateDocument(CollectionDef? def, Map<String, dynamic> data)`: Comprehensive document-level semantic validator (e.g. midnight praise rules, reminder leads, image HTTPS blocks).
  - `sameValue(Object? a, Object? b)`: Deep structural equality comparator across maps, lists, dates, and primitive types.
  - `isEchoOfEditor(Map<String, dynamic>? shown, Map<String, dynamic>? next, Map<String, dynamic> editorValues)`: Checks if a remote Firestore update is an echo of the editor's pending write, preserving scroll and form focus (BUG-12).
  - `changedFields(Map<String, dynamic> initial, Map<String, dynamic> current)`: Extracts delta fields to ensure concurrent edits from other admins are preserved.
  - `searchableText(Map<String, dynamic> data)`: Generates lower-case normalized search text for collection filtering.
  - `separatelySavedKeys`: Constant list of heavy fields (`['gallery', 'extraFields', 'blocks', 'dayEvents']`) separated during saves.
  - `splitSavePayload(Map<String, dynamic> payload)`: Splits document update payloads into sequential batches to comply with Firestore's 1,000 expression limit.
  - `timeRe`, `dateTimeRe`, `dateRe`: Regular expressions for datetime pattern matching.
- `assistant_admin.dart`:
  - `AssistantAdminScreen`: Administration interface for AI assistant settings, prompt templates, and system switches.
  - `AssistantSwitches`: Switch matrix controlling AI model enablement, context injection, and rate limiting.
- `collection_list.dart`:
  - `ListFilter`: Filter enumeration for collection listing (`all`, `visible`, `hidden`, `unconfirmed`).
  - `CollectionListScreen`: Searchable, filterable list table for browsing and managing collection items.
- `contact_admin.dart`:
  - `ContactCategoriesScreen`: Department routing and phone directory management screen.
- `doc_editor.dart`:
  - `ImageBytesPicker`: Typedef for asynchronous image file byte loader.
  - `DocEditor`: Dynamic form editor generating input controls from `FieldDef` descriptors.
  - `DocEditorState`: State manager for document form validation, dirty tracking, image uploads, and multi-step payload saving.
- `features_editor.dart`:
  - `FeaturesScreen`: Management screen for global feature toggles and navigation sections.
  - `FeaturesEditor`: Configuration form for `settings/features`.
  - `FeaturesEditorState`: State handler managing feature toggle mutations.
- `occasion_editor.dart`:
  - `OccasionThemeEditor`: Visual seasonal theme editor for previewing and customizing church banner artwork and color schemes.
- `season_preset_admin.dart`:
  - `SeasonPresetScreen`: Administrative screen for selecting, previewing, and activating liturgical season presets.
- Subdirectories: None

## Invariants
- `[admin_validators.dart:validateFieldValue]`: Inputs must pass schema type constraints, regex patterns, and range boundaries before save triggers.
- `[admin_validators.dart:splitSavePayload]`: Heavy payload fields (`gallery`, `extraFields`, `blocks`, `dayEvents`) must be saved in sequential requests separate from the base document to stay within the 1,000 expression budget of `firestore.rules` (ADR-020, ADR-044).
- `[admin_validators.dart:isEchoOfEditor]`: Incoming Firestore snapshots must not remount or reset scroll position if changes are an echo of the current editor's save (BUG-12).
- `[admin_validators.dart:changedFields]`: Document saves must only transmit keys that differ from initial load state to prevent clobbering concurrent administrator edits.
- `[admin_validators.dart:validateDocument]`: Liturgy entries are allowed to cross midnight (e.g. midnight praise), but all other events must enforce that end time/date is after start time/date.
- `[admin_validators.dart:parseFieldValue]`: All time values must be normalized to Cairo wall-time strings (`HH:mm`), and dates to `YYYY-MM-DD` or UTC instants.
- `[admin_page.dart:AdminPage]`: Unauthenticated users must be intercepted by `_AdminCheck` and prevented from accessing dashboard tabs.

## Side Effects
- `[doc_editor.dart:DocEditorState]`: Mutates documents in Cloud Firestore collections and writes uploaded image bytes into the `media/{id}` collection on the Spark plan.
- `[admin_page.dart:_LoginFormState]`: Invokes Firebase Authentication sign-in (`signInWithEmailAndPassword`) and sign-out.
- `[messages_screen.dart:_MessagesScreenState]`: Updates message document status flags (`read`, `archived`) in Firestore.
- `[features_editor.dart:FeaturesEditorState]`: Overwrites global feature flags in `settings/features`.
- `[season_preset_admin.dart:_SeasonPresetScreenState]`: Replaces seasonal configuration fields in `settings/features` when applying liturgical presets.

## Verification
- Run: `flutter test`
