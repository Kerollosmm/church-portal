# data

## Overview
The `lib/data` layer manages all local persistence, remote networking, platform service integration, and data access layers for the Church Portal application. It encapsulates interactions with Cloud Firestore, Firebase Authentication, Firebase App Check, Gemini AI logic, Sentry error telemetry, Android system services (local notifications, APK updates), and offline-first caches (bundled seed JSON, SharedPreferences). It guarantees offline functionality through seed fallbacks, cache-first strategies, and idempotent background sync.

## Interface
- [image_codec](./image_codec/README.md) - Platform-specific WebP/image decoding

### Admin & Content Repositories
- [`AdminDoc`](file:///c:/Users/Kerollos/church-portal/lib/data/admin_repository.dart#L7): Represents a Firestore admin document with id, normalized data, and audit metadata (`updatedAt`, `updatedBy`).
- [`AdminRoles`](file:///c:/Users/Kerollos/church-portal/lib/data/admin_repository.dart#L17): Role definitions for `owner` and `editor`.
- [`AdminBackend`](file:///c:/Users/Kerollos/church-portal/lib/data/admin_repository.dart#L26): Abstract interface for admin CRUD operations, reordering, and role assignments.
- [`AdminRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/admin_repository.dart#L79): Concrete Firestore implementation of `AdminBackend` with Firebase Auth management (`signIn`, `signOut`, `sendPasswordReset`, `adminRole`, `roleChanges`).
- [`ContentRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L20): Abstract contract for public content streaming and contact message submission.
- [`SeedRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L60): Offline/unconfigured fallback content repository backed by `SeedData`.
- [`FirestoreRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L453): Live Firestore content repository with fallback guards.
- [`ContactUnavailableException`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L14): Thrown when contact submission is attempted without live Firebase.
- [`SeedGate`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L138): Seeding marker tracker detecting if `settings/church` exists in Firestore.
- [`guardSeeded`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L205): Stream wrapper preventing stranded fallbacks while awaiting seeding confirmation.
- [`settleFirst`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L378): Stream combinator delaying provisional cache reads for custom content until confirmed by server.
- [`normalizeFirestoreValue`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L113), [`normalizeDoc`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L120): Normalizes Firestore `Timestamp` objects into UTC `DateTime` values.
- [`LiveReading`](file:///c:/Users/Kerollos/church-portal/lib/data/content_repository.dart#L365): Typed record describing a snapshot's value, provisional cache status, and change flag.
- [`SeedData`](file:///c:/Users/Kerollos/church-portal/lib/data/seed_data.dart#L10): Typed parser and static loader over bundled `assets/seed/seed.json`.

### Media & Image Processing
- [`EncodedImage`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L21): Holds compressed image bytes, MIME type, width, and height.
- [`MediaRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L31): Abstract contract for loading, uploading, and deleting media files.
- [`FirestoreMediaRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L46): Spark-plan implementation storing base64 image data inline in Firestore `media/{id}`.
- [`StorageMediaRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L106): Blaze-plan Cloud Storage repository stub.
- [`MediaCache`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L143): In-memory LRU cache of inline image bytes (default capacity 60).
- [`decodeMediaDoc`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L83): Extracts and decodes base64 bytes from a `media/{id}` document map.
- [`createMediaRepository`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L126): Factory selecting between Firestore inline and Storage media backends.
- [`ImageTooLargeException`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L129), [`ImageDecodeException`](file:///c:/Users/Kerollos/church-portal/lib/data/media_repository.dart#L135): Exceptions for image processing errors.
- [`DecodedImage`](file:///c:/Users/Kerollos/church-portal/lib/data/image_processing.dart#L13): Abstract decoded image interface for resizing and re-encoding.
- [`decodeImage`](file:///c:/Users/Kerollos/church-portal/lib/data/image_processing.dart#L23): Conditional decoder forwarding to the platform codec.
- [`compressDecoded`](file:///c:/Users/Kerollos/church-portal/lib/data/image_processing.dart#L31): Multi-pass downscaling and quality reduction targeting <= 250 KB.
- [`prepareUpload`](file:///c:/Users/Kerollos/church-portal/lib/data/image_processing.dart#L45): Complete picked image validation, decoding, and compression pipeline.
- [`maxInputBytes`](file:///c:/Users/Kerollos/church-portal/lib/data/image_processing.dart#L26): Input guard constant limiting uploads to 25 MB before decoding.

### Application Lifecycle, Firebase & Telemetry
- [`FirebaseStatus`](file:///c:/Users/Kerollos/church-portal/lib/data/firebase_bootstrap.dart#L12): Status record reporting Firebase availability, App Check state, and errors.
- [`bootstrapFirebase`](file:///c:/Users/Kerollos/church-portal/lib/data/firebase_bootstrap.dart#L22): Safe Firebase core initialization with 40 MB offline Firestore cache.
- [`ensureAppCheckActivated`](file:///c:/Users/Kerollos/church-portal/lib/data/firebase_bootstrap.dart#L58): Lazy activation of App Check on first assistant request.
- [`AppCheckPlan`](file:///c:/Users/Kerollos/church-portal/lib/data/app_check_providers.dart#L8): Chosen provider plan across web, Android, Apple, and debug targets.
- [`selectAppCheckPlan`](file:///c:/Users/Kerollos/church-portal/lib/data/app_check_providers.dart#L41): Provider selection algorithm based on platform and debug configuration.
- [`ErrorReportingGate`](file:///c:/Users/Kerollos/church-portal/lib/data/error_reporting.dart#L22): Reactive gate synchronizing error reporting with the admin feature switch.
- [`ErrorReporting`](file:///c:/Users/Kerollos/church-portal/lib/data/error_reporting.dart#L143): Global telemetry entry point managing Sentry lifecycle and breadcrumbs.
- [`scrubEvent`](file:///c:/Users/Kerollos/church-portal/lib/data/error_reporting.dart#L71), [`scrubBreadcrumb`](file:///c:/Users/Kerollos/church-portal/lib/data/error_reporting.dart#L119): Sanitizers eliminating PII, query params, and sensitive contexts.
- [`installSentryJsGate`](file:///c:/Users/Kerollos/church-portal/lib/data/sentry_js_gate.dart#L4): Browser-level gate ensuring web window errors adhere to admin switch and PII scrubbing.

### AI Assistant & Device Local Stores
- [`FirebaseAssistantModel`](file:///c:/Users/Kerollos/church-portal/lib/data/assistant_model.dart#L12): Stateless Gemini client communicating with Firebase AI Logic.
- [`PrefsUsageStore`](file:///c:/Users/Kerollos/church-portal/lib/data/assistant_usage_store.dart#L8): Daily quota tracker persisting usage in `SharedPreferences`.
- [`ReadingsStore`](file:///c:/Users/Kerollos/church-portal/lib/data/readings_store.dart#L12): Katameros daily readings cache and static hosting fetcher with automatic pruning.
- [`ReminderStore`](file:///c:/Users/Kerollos/church-portal/lib/data/reminder_store.dart#L25): Local storage manager for event reminders enforcing a 30-item device cap.
- [`remindersStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/data/reminder_store.dart#L6): Storage key `church_portal_reminders`.
- [`maxDeviceReminders`](file:///c:/Users/Kerollos/church-portal/lib/data/reminder_store.dart#L9): Constant device limit (30).
- [`ReminderPutResult`](file:///c:/Users/Kerollos/church-portal/lib/data/reminder_store.dart#L12): Outcome enum (`ok`, `full`, `storageError`).
- [`SynaxariumSource`](file:///c:/Users/Kerollos/church-portal/lib/data/synaxarium_source.dart#L17): Fetches and caches daily `/data/today.json` commemorations.

### Android Native System Services
- [`AppUpdater`](file:///c:/Users/Kerollos/church-portal/lib/data/app_updater.dart#L14): Cross-platform entry point for in-app APK updates.
- [`PlatformAppUpdater`](file:///c:/Users/Kerollos/church-portal/lib/data/app_updater_io.dart#L31): Android implementation managing manifest checks, resumable downloads, SHA-256 integrity verification, signature matching, and package installer intents.
- [`createPlatformAppUpdater`](file:///c:/Users/Kerollos/church-portal/lib/data/app_updater.dart#L24): Factory returning platform updater implementation.
- [`LocalNotifier`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L56): Cross-platform interface for local notifications.
- [`LocalNotifierImpl`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications_io.dart#L15): Android implementation utilizing `FlutterLocalNotificationsPlugin` for scheduled and instant notifications across 6 channels.
- [`LocalNotifierStub`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications_stub.dart#L10): No-op stub for web/desktop.
- [`createLocalNotifier`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L59): Factory creating platform notification provider.
- [`NotificationChannels`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L22): Canonical channel definitions (`verse`, `readings`, `feasts`, `reminders`, `announcements`, `seasons`).
- [`resolveChannelId`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L34): Channel identifier resolver with fallback to reminders.
- [`notificationColor`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L14), [`notificationSmallIcon`](file:///c:/Users/Kerollos/church-portal/lib/data/local_notifications.dart#L19): Brand color (`#6E1C1C`) and monochrome seal icon constants.

## Invariants
- `[admin_repository.dart:AdminRepository]`: All document mutations automatically stamp server timestamp `updatedAt` and actor identifier `updatedBy`.
- `[admin_repository.dart:AdminRepository._merge]`: Updates use `SetOptions(mergeFields: stamped.keys.toList())` to replace top-level maps completely instead of recursive deep merging, ensuring removed keys (e.g. headers, links) are pruned.
- `[admin_repository.dart:AdminRepository.sendPasswordReset]`: Never reveals whether an email account exists (returns `true` even on `user-not-found`).
- `[admin_repository.dart:AdminRepository.roleChanges]`: Discards cache-only missing snapshots so that a cold cache does not flash "not admin".
- `[content_repository.dart:guardSeeded]`: Prevents unseeded Firestore streams from stranding empty lists; serves bundled seed fallback until `settings/church` existence is proven by `SeedGate`.
- `[content_repository.dart:settleFirst]`: Holds back provisional cache readings for custom collections (`categories`, `entries`, `pages`) up to `customPatience` (8 seconds) to prevent false "not found" screens.
- `[content_repository.dart:FirestoreRepository.submitContact]`: Batches public contact message submission with a write to `meta/contact_rate` containing `lastMsgId` to enforce server-side security rule rate limits.
- `[error_reporting.dart:ErrorReporting.beforeSend]`: Privacy-first enforcement: all user identity, request query strings, form fields, and UI interaction breadcrumbs are scrubbed before transmission. If `settings/features.errorReporting` is toggled off, events are dropped and SDK closed.
- `[firebase_bootstrap.dart:bootstrapFirebase]`: Initialization never throws uncaught exceptions; any configuration or network failure falls back cleanly to offline seed data.
- `[firebase_bootstrap.dart:ensureAppCheckActivated]`: App Check activation is deferred until first assistant usage (ADR-037) to prevent loading heavy reCAPTCHA Enterprise bundles on initial page render.
- `[image_processing.dart:prepareUpload]`: Refuses images exceeding 25 MB (`maxInputBytes`) before decoding to protect against memory exhaustion; enforces max compressed threshold <= 700 KB.
- `[media_repository.dart:FirestoreMediaRepository.upload]`: Spark-plan inline images are stored as Base64 in Firestore `media/{id}` and must not exceed `MediaLimits.maxBytes` (700 KB).
- `[reminder_store.dart:ReminderStore.put]`: Enforces strict maximum of 30 stored reminders per device (`maxDeviceReminders`); rejects additions exceeding capacity with `ReminderPutResult.full`.
- `[reminder_store.dart:ReminderStore.clearExpired]`: Recurring reminders («كل مرة») never expire and are retained indefinitely across time boundaries.
- `[seed_data.dart:SeedData]`: `settings` and `features` properties are initialized once (`late final`) to maintain identical object references for identity equality (`identical`) checks in downstream providers.
- `[app_updater_io.dart:PlatformAppUpdater.downloadUpdate]`: Verifies both file byte length and SHA-256 checksum against `UpdateManifest`; mismatches delete partial downloads and throw `UpdateIntegrityException`.
- `[app_updater_io.dart:PlatformAppUpdater.installDownloadedUpdate]`: Fails closed: signature certificate must match the installed app's certificate via native package manager checks, otherwise throws `UpdateSignatureException`.
- `[local_notifications_io.dart:LocalNotifierImpl.schedulePlan]`: Schedules notifications in `Africa/Cairo` wall-clock time; cancels previous pending requests before re-applying plan; falls back to `inexactAllowWhileIdle` if exact alarm permissions are denied.
- `[readings_store.dart:ReadingsStore.getReadings]`: Memory cache is checked before SharedPreferences, followed by HTTP fetch from Hosting; prunes cached dates strictly older than yesterday.
- `[synaxarium_source.dart:SynaxariumSource.load]`: Limits remote HTTP requests to at most one GET per day by caching `/data/today.json` in local preferences.

## Side Effects
- `[admin_repository.dart:AdminRepository]`: Network mutations and real-time snapshot listeners against Cloud Firestore and Firebase Authentication.
- `[content_repository.dart:FirestoreRepository]`: Real-time streaming subscriptions to Firestore collections, batched message submissions, and `ErrorReporting.capture` on stream errors.
- `[media_repository.dart:FirestoreMediaRepository]`: Firestore document creation, base64 payload storage, and deletion in `media` collection; in-memory caching in `MediaCache`.
- `[error_reporting.dart:ErrorReporting]`: Network error dispatches to Sentry DSN; JavaScript interop modification of global `window.Sentry` on Web.
- `[app_updater_io.dart:PlatformAppUpdater]`: HTTP streaming downloads, file system write/delete in updates cache, SharedPreferences persistence of dismissed builds, and Android platform intent triggers.
- `[local_notifications_io.dart:LocalNotifierImpl]`: Invokes platform channels for Android notification channels creation, exact alarm scheduling, and permission dialogs.
- `[reminder_store.dart:ReminderStore]`, `[readings_store.dart:ReadingsStore]`, `[synaxarium_source.dart:SynaxariumSource]`, `[assistant_usage_store.dart:PrefsUsageStore]`: Local disk reads, writes, and key evictions in device SharedPreferences/localStorage.

## Verification
- Run: `flutter test`
