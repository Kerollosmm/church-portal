# data

## Overview
The `lib/data` layer manages all local persistence, remote networking, platform service integration, and data access layers for the Church Portal application. It encapsulates interactions with Cloud Firestore, Firebase Authentication, Firebase App Check, Gemini AI logic, Sentry error telemetry, Android system services (local notifications, APK updates), and offline-first caches (bundled seed JSON, SharedPreferences). It guarantees offline functionality through seed fallbacks, cache-first strategies, and idempotent background sync.

## Interface
- [image_codec](./image_codec/README.md) - Platform-specific WebP/image decoding

### Admin & Content Repositories
- [`AdminDoc`](admin_repository.dart#L7): Represents a Firestore admin document with id, normalized data, and audit metadata (`updatedAt`, `updatedBy`).
- [`AdminRoles`](admin_repository.dart#L17): Role definitions for `owner` and `editor`.
- [`AdminBackend`](admin_repository.dart#L26): Abstract interface for admin CRUD operations, reordering, and role assignments.
- [`AdminRepository`](admin_repository.dart#L79): Concrete Firestore implementation of `AdminBackend` with Firebase Auth management (`signIn`, `signOut`, `sendPasswordReset`).
- [`ContentRepository`](content_repository.dart#L20): Abstract contract for public content streaming and contact message submission.
- [`SeedRepository`](content_repository.dart#L60): Offline/unconfigured fallback content repository backed by `SeedData`.
- [`FirestoreRepository`](content_repository.dart#L453): Live Firestore content repository with fallback guards.
- [`ContactUnavailableException`](content_repository.dart#L14): Thrown when contact submission is attempted without live Firebase.
- [`SeedGate`](content_repository.dart#L138): Seeding marker tracker detecting if `settings/church` exists in Firestore (probing `Source.cache` first and triggering a background `Source.server` refresh).
- [`guardSeeded`](content_repository.dart#L205): Stream wrapper preventing stranded fallbacks while awaiting seeding confirmation.
- [`settleFirst`](content_repository.dart#L406): Stream combinator delaying empty cache reads for custom content (`customPatience` 8 s) while settling non-empty cache reads faster (`1.5 s` in PR 6F-1; `isOffline` `0 ms` hook prepared for PR 6F-2).
- [`watchWithFallback`](stream_watchdog.dart#L15): Bounded stream watchdog for `liturgies`, `seasons`, `settings`, and `features` falling back to `Source.cache` (plus optional `refreshServer`), seed (`settings`/`features` only), or `onMissError` (time-sensitive `liturgies`/`seasons`) on listener stall while keeping the live stream subscribed.
- [`normalizeFirestoreValue`](content_repository.dart#L113), [`normalizeDoc`](content_repository.dart#L120): Normalizes Firestore `Timestamp` objects into UTC `DateTime` values.
- [`LiveReading`](content_repository.dart#L365): Typed record describing a snapshot's value, provisional cache status, and change flag.
- [`SeedData`](seed_data.dart#L10): Typed parser and static loader over bundled `assets/seed/seed.json`.

### Media & Image Processing
- [`EncodedImage`](media_repository.dart#L21): Holds compressed image bytes, MIME type, width, and height.
- [`MediaRepository`](media_repository.dart#L31): Abstract contract for loading, uploading, and deleting media files.
- [`FirestoreMediaRepository`](media_repository.dart#L46): Spark-plan implementation storing base64 image data inline in Firestore `media/{id}` (`Source.cache` first on `load`).
- [`ReadOnlyMediaRepository`](media_repository.dart#L128): Spark-plan read-only public media loader (`Source.cache` first on `load`; `upload`/`delete` throw `UnsupportedError`).
- [`UrlImageCache`](url_image_cache.dart#L1): Conditional remote URL image disk cache (`url_image_cache_io.dart` on native with async disk I/O, 30-entry memory LRU, 25 s streaming timeout, 5 MB max single image, 0-byte/decode cleanup, amortized 50 MB LRU eviction; `url_image_cache_stub.dart` on web).
- [`MediaCache`](media_repository.dart#L172): In-memory LRU cache of inline image bytes (default capacity 60).
- [`decodeMediaDoc`](media_repository.dart#L83): Extracts and decodes base64 bytes from a `media/{id}` document map.
- [`createPublicMediaRepository`](media_repository.dart#L151): Factory returning read-only `ReadOnlyMediaRepository` for public startup without Firebase Auth.
- [`createMediaRepository`](media_repository.dart#L155): Factory returning writable `FirestoreMediaRepository` for `/admin`.
- [`ImageTooLargeException`](media_repository.dart#L158), [`ImageDecodeException`](media_repository.dart#L164): Exceptions for image processing errors.
- [`DecodedImage`](image_processing.dart#L13): Abstract decoded image interface for resizing and re-encoding.
- [`decodeImage`](image_processing.dart#L23): Conditional decoder forwarding to the platform codec.
- [`compressDecoded`](image_processing.dart#L31): Multi-pass downscaling and quality reduction targeting <= 250 KB.
- [`prepareUpload`](image_processing.dart#L45): Complete picked image validation, decoding, and compression pipeline.
- [`maxInputBytes`](image_processing.dart#L26): Input guard constant limiting uploads to 25 MB before decoding.

### Application Lifecycle, Firebase & Telemetry
- [`FirebaseStatus`](firebase_bootstrap.dart#L10): Status record reporting Firebase availability, App Check configuration state, and errors.
- [`isAppCheckConfigured`](firebase_bootstrap.dart#L20): Pure build/platform check matching `selectAppCheckPlan(...).activate` without importing `firebase_app_check`.
- [`kFirestoreCacheSizeBytes`](firebase_bootstrap.dart#L28): Default 40 MB web Firestore cache threshold (`kNativeFirestoreCacheSizeBytes` = 100 MB on native).
- [`firestoreSettings`](firebase_bootstrap.dart#L39): Platform Firestore `Settings` builder; enables `WebPersistentMultipleTabManager` on web (`isWeb == true`) and 100 MB cache on native (`isWeb == false`).
- [`bootstrapFirebase`](firebase_bootstrap.dart#L47): Safe Firebase core initialization with platform offline Firestore cache (40 MB multi-tab on web per ADR-078; 100 MB native per ADR-091).
- [`AppCheckPlan`](app_check_providers.dart#L12): Chosen provider plan across web, Android, Apple, and debug targets.
- [`selectAppCheckPlan`](app_check_providers.dart#L45): Provider selection algorithm based on platform and debug configuration.
- [`ensureAppCheckActivated`](app_check_providers.dart#L83): Lazy activation of App Check on first assistant request (deferred with `/ask`).
- [`ErrorReportingGate`](error_reporting.dart#L22): Reactive gate synchronizing error reporting with the admin feature switch.
- [`ErrorReporting`](error_reporting.dart#L143): Global telemetry entry point managing Sentry lifecycle and breadcrumbs.
- [`scrubEvent`](error_reporting.dart#L71), [`scrubBreadcrumb`](error_reporting.dart#L119): Sanitizers eliminating PII, query params, and sensitive contexts.
- [`installSentryJsGate`](sentry_js_gate.dart#L4): Browser-level gate ensuring web window errors adhere to admin switch and PII scrubbing.

### AI Assistant & Device Local Stores
- [`FirebaseAssistantModel`](assistant_model.dart#L12): Stateless Gemini client communicating with Firebase AI Logic.
- [`PrefsUsageStore`](assistant_usage_store.dart#L8): Daily quota tracker persisting usage in `SharedPreferences`.
- [`ReadingsStore`](readings_store.dart#L12): Katameros daily readings cache and static hosting fetcher (8 s HTTP timeout, Cairo 7-day `prefetchUpcomingDays`, automatic pruning).
- [`ReminderStore`](reminder_store.dart#L25): Local storage manager for event reminders enforcing a 30-item device cap.
- [`remindersStorageKey`](reminder_store.dart#L6): Storage key `church_portal_reminders`.
- [`maxDeviceReminders`](reminder_store.dart#L9): Constant device limit (30).
- [`ReminderPutResult`](reminder_store.dart#L12): Outcome enum (`ok`, `full`, `storageError`).
- [`SynaxariumSource`](synaxarium_source.dart#L17): Fetches and caches daily `/data/today.json` commemorations.

### Android Native System Services
- [`AppUpdater`](app_updater.dart#L14): Cross-platform entry point for in-app APK updates.
- [`PlatformAppUpdater`](app_updater_io.dart#L31): Android implementation managing manifest checks, resumable downloads, SHA-256 integrity verification, signature matching, and package installer intents.
- [`createPlatformAppUpdater`](app_updater.dart#L24): Factory returning platform updater implementation.
- [`LocalNotifier`](local_notifications.dart#L56): Cross-platform interface for local notifications.
- [`LocalNotifierImpl`](local_notifications_io.dart#L15): Android implementation utilizing `FlutterLocalNotificationsPlugin` for scheduled and instant notifications across 6 channels.
- [`LocalNotifierStub`](local_notifications_stub.dart#L10): No-op stub for web/desktop.
- [`createLocalNotifier`](local_notifications.dart#L59): Factory creating platform notification provider.
- [`NotificationChannels`](local_notifications.dart#L22): Canonical channel definitions (`verse`, `readings`, `feasts`, `reminders`, `announcements`, `seasons`).
- [`resolveChannelId`](local_notifications.dart#L34): Channel identifier resolver with fallback to reminders.
- [`notificationColor`](local_notifications.dart#L14), [`notificationSmallIcon`](local_notifications.dart#L19): Brand color (`#6E1C1C`) and monochrome seal icon constants.

## Invariants
- `[admin_repository.dart:AdminRepository]`: All document mutations automatically stamp server timestamp `updatedAt` and actor identifier `updatedBy`.
- `[admin_repository.dart:AdminRepository._merge]`: Updates use `SetOptions(mergeFields: stamped.keys.toList())` to replace top-level maps completely instead of recursive deep merging, ensuring removed keys (e.g. headers, links) are pruned.
- `[admin_repository.dart:AdminRepository.sendPasswordReset]`: Never reveals whether an email account exists (returns `true` even on `user-not-found`).
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
