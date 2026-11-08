# State Component Package

## Overview
The `lib/state` package manages global application state using Flutter Riverpod. It orchestrates real-time Firestore content streams, handles fallback states during offline/cold starts, synchronizes user localization and theme selections, computes the liturgical "Today" layer, manages client-side reminders and push subscriptions, and coordinates local notification scheduling both in the foreground and via background WorkManager workers.

## Interface
- **Repository & Infrastructure Providers (`providers.dart`)**:
  - [`firebaseStatusProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L36): Current availability status of Firebase and App Check.
  - [`repositoryProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L37): Primary `ContentRepository` (overridden in `main.dart` with `FirestoreRepository` or `SeedRepository`).
  - [`adminRepositoryProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L38): Optional `AdminRepository` for administrative operations.
  - [`mediaRepositoryProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L42): Optional `MediaRepository` for inline or storage media uploads.

- **Settings & Feature Toggle Providers (`providers.dart`)**:
  - [`settingsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L44): Stream provider for global `ChurchSettings`.
  - [`featuresStreamProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L47): Stream provider for raw `FeatureSettings` document.
  - [`featuresProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L56): Active `FeatureSettings` provider accounting for automatic season preset expiration.
  - [`featuresReadyProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L66): Indicates whether features have been fetched or failed.
  - [`contentReadyProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L76): Evaluates whether initial content has arrived to hide the web loading splash.
  - [`firstContentArrived(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L85): Pure evaluation helper for content loading states.
  - [`errorReportingSwitchProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L99): Admin error reporting flag (null while unconfirmed on Firestore).
  - [`featuresLiveProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L131): Enforces waiting for live stored features or bounded by 30-second patience timeout.

- **Content Collections & Real-Time Streams (`providers.dart`)**:
  - [`alertsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L168), [`seasonsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L169), [`liturgiesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L170), [`meetingsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L171), [`activitiesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L172), [`clinicsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L173), [`facilitiesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L174), [`priestsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L175), [`milestonesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L176), [`saintsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L177): Filtered public content streams.
  - [`categoriesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L181), [`entriesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L185), [`customPagesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L188): Dynamic custom CMS content providers.
  - [`dailyVersesProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L202): Bundled daily verses asset loader.
  - [`nowProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L208): Periodic 30-second clock stream.
  - [`assistantVisibleProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L214): Evaluates visibility for AI assistant entrypoints.

- **Locale & Theme Notifiers (`providers.dart`)**:
  - [`LocaleNotifier`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L228) / [`localeProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L271): State notifier managing language transitions (`ar`/`en`) and URL sync state.
  - [`ActiveTheme`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L275) / [`activeThemeProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L300): Computes the active liturgical theme and palette.
  - [`activeSeasonKeysProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L312): Active liturgical season keys joined by comma.

- **Liturgical "Today" Providers (`providers.dart`)**:
  - [`todaySettingsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L327): Top-level settings for the today layer.
  - [`liturgicalDayProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L331): Calculates active liturgical day (rolling at sunset/18:00 Cairo time).
  - [`synaxariumProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L342): Reads Synaxarium commemoration data when page is idle.
  - [`topEventProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L351): Computes prioritized hero event for the home screen.

- **Install, Notifications & Reminders State (`providers.dart`)**:
  - [`installSettingsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L376), [`pushSettingsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L380): Configuration providers for PWA install and notifications.
  - [`pushPermissionProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L394): Browser push permission state string.
  - [`pushPrefsProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L402) / [`PushPrefsNotifier`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L404): Visitor notification category preferences notifier.
  - [`userRemindersProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L460) / [`UserRemindersNotifier`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L462): Visitor mass/event reminders state manager.
  - [`appUpdaterProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L494), [`updateDecisionProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L508): Android in-app APK update evaluation provider.

- **Notification Planning & Replenishment (`notify_providers.dart`)**:
  - Storage constants: [`notifyPlanStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L25), [`notifySnapshotStorageKey`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L28), [`notifyDiagLastReplenishKey`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L31).
  - [`dailyVerseConfigProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L34): Daily verse settings selector.
  - [`localNotifierProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L39): Provider for `LocalNotifier` scheduling engine.
  - [`notifyPlannerProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L44) / [`NotifyPlanner`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L342): Foreground planner coordinating 2-second debounced re-planning when settings, reminders, liturgies, or verses update.
  - [`loadStoredPlan(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L51): Reads persisted notification plan.
  - [`computeLiturgyOccurrences(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L67), [`computeMeetingOccurrences(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L85): Expands schedule occurrences up to 60 days ahead in Cairo time.
  - [`PlannerSnapshot`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L128): Serialized state snapshot supporting background replenishment.
  - [`savePlannerSnapshot(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L302), [`loadPlannerSnapshot(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L329): Serialization helpers for planner inputs.
  - [`notificationReplenishCallbackDispatcher()`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L462): Background WorkManager entry point.
  - [`executeReplenishmentTask(...)`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L469): Executes background verification and replenishment of scheduled notifications.

## Invariants
- [`providers.dart:repositoryProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L37): Must be overridden at root `ProviderScope` during application startup (`main()`); accessing the default provider throws `UnimplementedError`.
- [`providers.dart:featuresProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L56): Never returns null or blocks UI rendering; defaults to `FeatureSettings.defaults` until Firestore streams emit data.
- [`providers.dart:featuresLiveProvider`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L131): Guarantees that cold-boot cached seed defaults are not treated as live administrative settings until the live doc arrives or the 30-second `featuresSeedPatience` expires.
- [`providers.dart:PushPrefsNotifier._update`](file:///c:/Users/Kerollos/church-portal/lib/state/providers.dart#L444): When updating user notification preferences, choices for categories temporarily withdrawn by an administrator are preserved in storage (`keepUnoffered: true`) to avoid dropping user subscriptions if restored later.
- [`notify_providers.dart:NotifyPlanner.scheduleReplan`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L368): Multi-source changes must be debounced by 2 seconds and executed sequentially (`_isPlanning` lock with `_needsAnotherReplan`) to prevent concurrent notification collisions.
- [`notify_providers.dart:executeReplenishmentTask`](file:///c:/Users/Kerollos/church-portal/lib/state/notify_providers.dart#L469): Background workers must ensure `CairoTime.ensureInitialized()` and initialize a local `LocalNotifier` instance within their isolated thread before invoking scheduling routines.

## Side Effects
- **Network & Firestore Listeners**: Connects real-time streams to Cloud Firestore documents and collections.
- **Local Notification Rescheduling**: Directly modifies system notification queues via `LocalNotifier.schedulePlan` on Android.
- **Local Storage Mutations**: Writes JSON configurations to `localStorage` or `SharedPreferences` for keys `church_portal_push`, `church_portal_reminders`, `church_portal_notify_plan`, `church_portal_notify_snapshot`, and diagnostic timestamps.
- **WorkManager Invocations**: Executes scheduled background tasks in independent Dart VM entrypoints.

## Verification
- Run: `flutter test`
