# Core Component Package

## Overview
The `lib/core` package delivers foundational platform abstractions, cross-platform hardware/browser environment bridges, localization routines, theme construction, and document lifecycle primitives. It isolates platform-specific implementations (Web JavaScript interop via `package:web` vs. native IO via `dart:io` and `shared_preferences`) behind unified synchronous interfaces to support seamless web and Android execution.

## Interface
- **Application Readiness & Idle Timing (`content_ready.dart`)**:
  - [`ContentReady`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L13): Coordinates removal of the web static loading screen and defers heavy decorations until the browser thread is idle.
  - [`ContentReady.signalled`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L20): Boolean indicator whether content readiness has been dispatched.
  - [`ContentReady.whenIdle`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L24): `Future<void>` completing after `signal()` when browser scheduling reports idle.
  - [`ContentReady.maxWait`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L37): Upper time limit duration (12 seconds) for idle completion.
  - [`ContentReady.signal()`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L40): Idempotent trigger notifying `web/index.html` to fade out its loading overlay.

- **Document Metadata & Language Sync (`document_lang.dart`)**:
  - [`setDocumentLanguage(String languageCode)`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L7): Updates `<html lang="...">` on web DOM.
  - [`kCanonicalOrigin`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L10): Production canonical origin (`'https://maximos-domadios-church.web.app'`).
  - [`canonicalUrlForPath(String path)`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L15): Canonicalizes application route paths by removing query strings, fragments, and trailing slashes.
  - [`DocumentHeadSpec`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L30): Immutable model encapsulating canonical link URL and robots `noindex` flag.
  - [`routeHeadSpec({required String path, required bool indexable})`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L42): Constructs a `DocumentHeadSpec` enforcing indexability rules.
  - [`setDocumentRouteMeta({required String path, required bool indexable})`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L53): Syncs `<link rel="canonical">` and `<meta name="robots">` on web.
  - [`debugOnRouteMeta`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L49): Test hook for inspecting document head changes in non-web unit tests.

- **Client Environment & Storage (`install_env.dart`)**:
  - [`initInstallStore()`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env.dart#L7): Preloads native SharedPreferences prior to initial widget build.
  - [`installStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env.dart#L10): Storage key constant (`'church_portal_install'`).
  - [`InstallEnv`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env.dart#L13): Abstract environment facade defining user agent, display mode, installation prompts, and synchronous JSON storage.
  - [`PlatformInstallEnv`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env.dart#L38): Concrete default implementation linking to web JS interop or native IO storage.

- **Localization & String Translation (`l10n.dart`)**:
  - [`registerStrings(Map<String, List<String>> table)`](file:///c:/Users/Kerollos/church-portal/lib/core/l10n.dart#L796): Dynamically registers localization tables for deferred chunk loading.
  - [`L10nX`](file:///c:/Users/Kerollos/church-portal/lib/core/l10n.dart#L800): `BuildContext` extension providing:
    - `isAr`: Locale check for Arabic (`'ar'`).
    - `tr(String key, [Map<String, String> args])`: Parameterized translation lookup with placeholder replacement.
    - `inDays(int n)`: Arabic grammar-aware day count formatting.
    - `dayCount(int n)`: Arabic plural-aware duration string formatter.
    - `trOrNull(String key)`: Safe lookup returning null if missing.
    - `pick(String ar, String en)`: Bilingual selector returning the active language variant.

- **External Launchers & Mapping (`launch.dart`)**:
  - [`openUrl(String url)`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L6): Cross-platform external URL launcher (normalizes schemeless URLs).
  - [`callPhone(String number)`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L21): Dispatches `tel:` telephony URIs.
  - [`openWhatsApp(String number, {String? text})`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L23): Opens WhatsApp conversation with pre-filled message text.
  - [`mapsSearchUrl(ChurchSettings s)`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L26): Generates Google Maps search URL.
  - [`mapsDirectionsUrl(ChurchSettings s)`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L33): Generates turn-by-turn navigation URL.
  - [`mapsEmbedUrl(ChurchSettings s, {String lang = 'ar'})`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart#L42): Generates iframe embed URL for maps with locale parameter.

- **Locale Storage Persistence (`locale_storage.dart`)**:
  - [`initLanguageStore()`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage.dart#L6): Preloads native SharedPreferences language preference.
  - [`languageStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage.dart#L9): Constant key (`'church_portal_lang'`).
  - [`LanguageStore`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage.dart#L14): Abstract persistent storage for chosen language.
  - [`PlatformLanguageStore`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage.dart#L25): Platform-bound language storage (`localStorage` on web, SharedPreferences cache on Android).

- **Motion & Data Saver Environment (`motion_env.dart`)**:
  - [`MotionEnv`](file:///c:/Users/Kerollos/church-portal/lib/core/motion_env.dart#L4): System inspection utility.
  - [`MotionEnv.isTest`](file:///c:/Users/Kerollos/church-portal/lib/core/motion_env.dart#L9): Returns true under `flutter test` via `FLUTTER_TEST` environment variable.
  - [`MotionEnv.saveData`](file:///c:/Users/Kerollos/church-portal/lib/core/motion_env.dart#L13): Checks `navigator.connection.saveData` to inhibit bandwidth-heavy video loops.

- **Push Capabilities Environment (`push_env.dart`)**:
  - [`pushStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/core/push_env.dart#L5): Constant key (`'church_portal_push'`).
  - [`PushEnv`](file:///c:/Users/Kerollos/church-portal/lib/core/push_env.dart#L8): Abstraction over browser push notifications.
  - [`PlatformPushEnv`](file:///c:/Users/Kerollos/church-portal/lib/core/push_env.dart#L17): Concrete environment checking `Notification`, `serviceWorker`, and `PushManager` support.

- **Design System & Theme Engine (`theme.dart`)**:
  - [`AppColors`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L16): "Golden Hour" design tokens (`burgundy`, `cream`, `gold`, `goldLight`, `parchment`, `ink`, `muted`, `night`, etc.).
  - [`AppFonts`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L79): Font families (`IBM Plex Sans Arabic`, `Lalezar`, `Aref Ruqaa`).
  - [`Space`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L112): 8-point geometric spacing tokens (`xs: 4` to `xxl: 32`, `grid: 16`, `card: 16`).
  - [`kPanelRadius`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L108): Standard card corner radius (20 px).
  - [`OccasionColors`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L137): `ThemeExtension<OccasionColors>` managing dynamic liturgical color tokens, accessible switch tracks, and seasonal art filters.
  - [`OccasionColorsContext`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L281): Extension exposing `context.pal`.
  - [`readableOn(Color fg, List<Color> grounds)`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L288): Contrast normalization helper ensuring WCAG 4.5:1 text readability.
  - [`sceneArt(BuildContext context, Widget child)`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L292): Applies greyscale/dimming matrix during solemn liturgical seasons (Holy Week).
  - [`buildTheme(...)`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L309): Generates full Material 3 `ThemeData` enforcing typography and contrast guarantees.

## Invariants
- [`content_ready.dart:ContentReady.signal`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready.dart#L40): Signal dispatch is strictly idempotent; subsequent invocations return immediately without re-dispatching DOM events.
- [`document_lang.dart:routeHeadSpec`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang.dart#L42): A canonical URL and `<meta name="robots" content="noindex">` are mutually exclusive; indexable routes receive canonical links without `noindex`, whereas non-indexable routes receive `noindex` and null canonical link.
- [`motion_env.dart:MotionEnv.isTest`](file:///c:/Users/Kerollos/church-portal/lib/core/motion_env.dart#L9): Under test execution (`FLUTTER_TEST`), ambient animation loops and video controllers must halt to guarantee `WidgetTester.pumpAndSettle()` convergence.
- [`install_env.dart:initInstallStore`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env.dart#L7): Native disk stores must be initialized asynchronously prior to `runApp` so downstream synchronous `readJson` operations never block UI frames.
- [`theme.dart:OccasionColors`](file:///c:/Users/Kerollos/church-portal/lib/core/theme.dart#L137): Switch thumb, track, and text elements must enforce WCAG contrast minimums (≥3:1 non-text, ≥4.5:1 body text) regardless of dynamic admin palette selections.

## Side Effects
- **DOM Manipulations**: Mutates `<html lang>`, `<link rel="canonical">`, and `<meta name="robots">` in `web.document` ([`document_lang_web.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/document_lang_web.dart)). Dispatches custom `app-content-ready` window events ([`content_ready_web.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/content_ready_web.dart)).
- **Web Storage Access**: Synchronously reads and writes browser `localStorage` and `sessionStorage` ([`install_env_web.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env_web.dart), [`locale_storage_web.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage_web.dart)).
- **Native Disk I/O**: Reads and asynchronously flushes preferences to disk via `SharedPreferences` ([`install_env_io.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/install_env_io.dart), [`locale_storage_io.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/locale_storage_io.dart)).
- **External Application Launches**: Invokes `url_launcher` launching system browsers, phone dialer intents, and WhatsApp messaging protocols ([`launch.dart`](file:///c:/Users/Kerollos/church-portal/lib/core/launch.dart)).

## Verification
- Run: `flutter test`
