# Application Root (lib)

## Overview
The `lib` directory serves as the root blueprint and composition entry point of the application. It orchestrates initial application bootstrapping (`main.dart`), configures root widget composition and theme/locale binding (`app.dart`), defines declarative URL routing and deferred chunk boundaries (`router.dart`), and supplies platform Firebase configurations (`firebase_options.dart`). Child systems are partitioned into six architectural layers: configuration (`config`), core primitives and styling (`core`), data persistence (`data`), pure business domain (`domain`), reactive state (`state`), and user interface (`ui`).

## Local Interface & Direct File Contracts
- **Root Entry Point (`main.dart`)**:
  - [`main()`](file:///c:/Users/Kerollos/church-portal/lib/main.dart#L27): Application entry point wrapped in `ErrorReporting.run` for crash protection. Initializes URL path routing, bundled font licenses, Cairo timezone database, seed data, Firebase credentials, and native Android background WorkManager replenishment tasks before launching `ProviderScope`.

- **Root Widget (`app.dart`)**:
  - [`ChurchPortalApp`](file:///c:/Users/Kerollos/church-portal/lib/app.dart#L15): Top-level `ConsumerWidget` that binds Riverpod state to `MaterialApp.router`. Synchronizes active locale with document language attributes, manages dynamic liturgical occasion theme switching, informs the web splash screen when content has painted via post-frame callbacks, and mounts the notification planner on native targets.

- **Routing & Navigation (`router.dart`)**:
  - [`buildAppRouter(...)`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L132) / [`routerProvider`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L127): Central declarative router (`GoRouter`).
  - [`resolveLangSync(...)`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L80) / [`LangSync`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L63): Handles bidirectional query synchronization between the `?lang=` parameter and `localeProvider`.
  - [`isWebProvider`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L125): Detects web runtime vs native environments.
  - Enforces route feature gating ([`FeatureGate`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L42)), deferred code-splitting for `/admin`, `/ask`, `/notifications`, and `/readings/:date`, and tree-shakes administrative routes from native release APKs.

- **Firebase Platform Options (`firebase_options.dart`)**:
  - [`DefaultFirebaseOptions`](file:///c:/Users/Kerollos/church-portal/lib/firebase_options.dart#L13): Platform configuration selector providing `FirebaseOptions` for web and Android targets, while returning `null` on unconfigured platforms to trigger graceful offline seed fallback.

## Subdirectories & Boundaries
- [`config`](./config/README.md): Compile-time build configurations, telemetry credentials, and `--dart-define` bindings.
- [`core`](./core/README.md): Low-level platform adapters, DOM helpers, string localizations, and the "Golden Hour" theme system.
- [`data`](./data/README.md): Repositories, Firestore accessors, local notification dispatchers, media managers, and Sentry telemetry.
- [`domain`](./domain/README.md): Pure Dart domain entities, Cairo time conversions, liturgical calendar calculations, and scheduling algorithms.
- [`state`](./state/README.md): Riverpod state providers, stream listeners, notification planning, and background replenishment workers.
- [`ui`](./ui/README.md): Presentation widgets, responsive shells, deferred chunk loaders, and administrative screens.

## Invariants
- [`main.dart:main`](file:///c:/Users/Kerollos/church-portal/lib/main.dart#L27): Startup execution must remain inside `ErrorReporting.run` to guarantee Sentry captures unhandled initialization crashes.
- [`main.dart:_start`](file:///c:/Users/Kerollos/church-portal/lib/main.dart#L45-L54): Firebase unavailability must never crash startup; the app must seamlessly fall back to `SeedRepository` if Firebase configuration is missing or network connectivity fails.
- [`app.dart:_signalContentPainted`](file:///c:/Users/Kerollos/church-portal/lib/app.dart#L49-L56): `ContentReady.signal()` must only fire across two consecutive post-frame callbacks after `contentReadyProvider` turns true, ensuring the real home content is visually rendered before fading the loading screen.
- [`router.dart:buildAppRouter`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L247): The administrative dashboard (`/admin`) must be strictly excluded from production Android APKs via compile-time dead-code elimination (`kIsWeb || !const bool.fromEnvironment('dart.vm.product')`).
- [`router.dart:_page`](file:///c:/Users/Kerollos/church-portal/lib/router.dart#L42): Every public screen route must be encapsulated within a `FeatureGate` to prevent access to disabled church sections.

## Side Effects
- **Network I/O**: Live Firestore streams, App Check verification handshakes, Sentry error telemetry transmission, and external URL intent handling.
- **Background Tasks**: WorkManager periodic background replenishment job registration on Android.
- **Local Persistence**: Reading and writing client preferences and notifications in `localStorage` and `SharedPreferences`.
- **DOM & Web Window**: Manipulates `<html lang>`, `<link rel="canonical">`, and `<meta name="robots">`, and emits `app-content-ready` events.

## Verification
- Run: `flutter test`
