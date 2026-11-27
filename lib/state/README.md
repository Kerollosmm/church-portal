# State Component Package

## Overview
The `lib/state` package manages global application state using Flutter Riverpod. It orchestrates real-time Firestore content streams, handles fallback states during offline/cold starts, synchronizes user localization and theme selections, computes the liturgical "Today" layer, manages client-side reminders and push subscriptions, and coordinates local notification scheduling both in the foreground and via background WorkManager workers.

## Interface
- **Repository & Infrastructure Providers (`providers.dart`)**:
  - [`firebaseStatusProvider`](providers.dart#L36): Current availability status of Firebase and App Check.
  - [`repositoryProvider`](providers.dart#L37): Primary `ContentRepository` (overridden in `main.dart` with `FirestoreRepository` or `SeedRepository`).
  - [`mediaRepositoryProvider`](providers.dart#L42): Optional `MediaRepository` for public inline image loading (`ReadOnlyMediaRepository`); writable `adminRepositoryProvider` lives inside deferred `lib/ui/admin/admin_page.dart`.

- **Settings & Feature Toggle Providers (`providers.dart`)**:
  - [`settingsProvider`](providers.dart#L44): Stream provider for global `ChurchSettings`.
  - [`featuresStreamProvider`](providers.dart#L47): Stream provider for raw `FeatureSettings` document.
  - [`featuresProvider`](providers.dart#L56): Active `FeatureSettings` provider accounting for automatic season preset expiration.
  - [`featuresReadyProvider`](providers.dart#L66): Indicates whether features have been fetched or failed.
  - [`contentReadyProvider`](providers.dart#L76): Evaluates whether initial content has arrived to hide the web loading splash.
  - [`firstContentArrived(...)`](providers.dart#L85): Pure evaluation helper for content loading states.
  - [`errorReportingSwitchProvider`](providers.dart#L99): Admin error reporting flag (null while unconfirmed on Firestore).
  - [`featuresLiveProvider`](providers.dart#L131): Enforces waiting for live stored features or bounded by 30-second patience timeout.

- **Content Collections & Real-Time Streams (`providers.dart`)**:
  - [`alertsProvider`](providers.dart#L168), [`seasonsProvider`](providers.dart#L169), [`liturgiesProvider`](providers.dart#L170), [`meetingsProvider`](providers.dart#L171), [`activitiesProvider`](providers.dart#L172), [`facilitiesProvider`](providers.dart#L174), [`priestsProvider`](providers.dart#L175), [`milestonesProvider`](providers.dart#L176), [`saintsProvider`](providers.dart#L177): Filtered public content streams.
  - [`categoriesProvider`](providers.dart#L181), [`entriesProvider`](providers.dart#L185), [`customPagesProvider`](providers.dart#L188): Dynamic custom CMS content providers.
  - [`dailyVersesProvider`](providers.dart#L202): Bundled daily verses asset loader.
  - [`nowProvider`](providers.dart#L208): Periodic 30-second clock stream.
  - [`assistantVisibleProvider`](providers.dart#L214): Evaluates visibility for AI assistant entrypoints.

- **Locale & Theme Notifiers (`providers.dart`)**:
  - [`LocaleNotifier`](providers.dart#L228) / [`localeProvider`](providers.dart#L271): State notifier managing language transitions (`ar`/`en`) and URL sync state.
  - [`ActiveTheme`](providers.dart#L275) / [`activeThemeProvider`](providers.dart#L300): Computes the active liturgical theme and palette.
  - [`activeSeasonKeysProvider`](providers.dart#L312): Active liturgical season keys joined by comma.

- **Liturgical "Today" Providers (`providers.dart`)**:
  - [`todaySettingsProvider`](providers.dart#L327): Top-level settings for the today layer.
  - [`liturgicalDayProvider`](providers.dart#L331): Calculates active liturgical day (rolling at sunset/18:00 Cairo time).
  - [`synaxariumProvider`](providers.dart#L342): Reads Synaxarium commemoration data when page is idle.
  - [`topEventProvider`](providers.dart#L351): Computes prioritized hero event for the home screen.

- **Install, Notifications & Reminders State (`providers.dart`)**:
  - [`installSettingsProvider`](providers.dart#L376), [`pushSettingsProvider`](providers.dart#L380): Configuration providers for PWA install and notifications.
  - [`pushPermissionProvider`](providers.dart#L394): Browser push permission state string.
  - [`pushPrefsProvider`](providers.dart#L402) / [`PushPrefsNotifier`](providers.dart#L404): Visitor notification category preferences notifier.
  - [`userRemindersProvider`](providers.dart#L460) / [`UserRemindersNotifier`](providers.dart#L462): Visitor mass/event reminders state manager.
  - [`appUpdaterProvider`](providers.dart#L494), [`updateDecisionProvider`](providers.dart#L508): Android in-app APK update evaluation provider.

- **Notification Planning & Replenishment (`notify_providers.dart`)**:
  - Storage constants: [`notifyPlanStorageKey`](notify_providers.dart#L25), [`notifySnapshotStorageKey`](notify_providers.dart#L28), [`notifyDiagLastReplenishKey`](notify_providers.dart#L31).
  - [`dailyVerseConfigProvider`](notify_providers.dart#L34): Daily verse settings selector.
  - [`localNotifierProvider`](notify_providers.dart#L39): Provider for `LocalNotifier` scheduling engine.
  - [`notifyPlannerProvider`](notify_providers.dart#L44) / [`NotifyPlanner`](notify_providers.dart#L342): Foreground planner coordinating 2-second debounced re-planning when settings, reminders, liturgies, or verses update.
  - [`loadStoredPlan(...)`](notify_providers.dart#L51): Reads persisted notification plan.
  - [`computeLiturgyOccurrences(...)`](notify_providers.dart#L67), [`computeMeetingOccurrences(...)`](notify_providers.dart#L85): Expands schedule occurrences up to 60 days ahead in Cairo time.
  - [`PlannerSnapshot`](notify_providers.dart#L128): Serialized state snapshot supporting background replenishment.
  - [`savePlannerSnapshot(...)`](notify_providers.dart#L302), [`loadPlannerSnapshot(...)`](notify_providers.dart#L329): Serialization helpers for planner inputs.
  - [`notificationReplenishCallbackDispatcher()`](notify_providers.dart#L502): Background WorkManager entry point dispatching notification replenishment and `readingsPrefetch`.
  - [`executeReplenishmentTask(...)`](notify_providers.dart#L524): Executes background verification and replenishment of scheduled notifications.
  - [`executeReadingsPrefetchTask(...)`](notify_providers.dart#L510): Executes unmetered 7-day Cairo Katameros readings prefetch and pruning.

## Invariants
- [`providers.dart:repositoryProvider`](providers.dart#L37): Must be overridden at root `ProviderScope` during application startup (`main()`); accessing the default provider throws `UnimplementedError`.
- [`providers.dart:featuresProvider`](providers.dart#L56): Never returns null or blocks UI rendering; defaults to `FeatureSettings.defaults` until Firestore streams emit data.
- [`providers.dart:featuresLiveProvider`](providers.dart#L131): Guarantees that cold-boot cached seed defaults are not treated as live administrative settings until the live doc arrives or the 30-second `featuresSeedPatience` expires.
- [`providers.dart:PushPrefsNotifier._update`](providers.dart#L444): When updating user notification preferences, choices for categories temporarily withdrawn by an administrator are preserved in storage (`keepUnoffered: true`) to avoid dropping user subscriptions if restored later.
- [`notify_providers.dart:NotifyPlanner.scheduleReplan`](notify_providers.dart#L368): Multi-source changes must be debounced by 2 seconds and executed sequentially (`_isPlanning` lock with `_needsAnotherReplan`) to prevent concurrent notification collisions.
- [`notify_providers.dart:executeReplenishmentTask`](notify_providers.dart#L469): Background workers must ensure `CairoTime.ensureInitialized()` and initialize a local `LocalNotifier` instance within their isolated thread before invoking scheduling routines.

## Side Effects
- **Network & Firestore Listeners**: Connects real-time streams to Cloud Firestore documents and collections.
- **Local Notification Rescheduling**: Directly modifies system notification queues via `LocalNotifier.schedulePlan` on Android.
- **Local Storage Mutations**: Writes JSON configurations to `localStorage` or `SharedPreferences` for keys `church_portal_push`, `church_portal_reminders`, `church_portal_notify_plan`, `church_portal_notify_snapshot`, and diagnostic timestamps.
- **WorkManager Invocations**: Executes scheduled background tasks in independent Dart VM entrypoints.

## Verification
- Run: `flutter test`
