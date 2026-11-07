import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_updater.dart';
import '../domain/app_update.dart';

import '../core/content_ready.dart';
import '../core/install_env.dart';
import '../core/locale_storage.dart';
import '../core/push_env.dart';
import '../data/admin_repository.dart';
import '../data/content_repository.dart';
import '../data/firebase_bootstrap.dart';
import '../data/media_repository.dart';
import '../data/reminder_store.dart';
import '../data/synaxarium_source.dart';
import '../domain/assistant_settings.dart';
import '../domain/cairo_time.dart';
import '../domain/contact_categories.dart';
import '../domain/coptic_calendar.dart';
import '../domain/custom_content.dart';
import '../domain/daily_verse.dart';
import '../domain/features.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
import '../domain/schedule.dart' show activeSeasonsAt;
import '../domain/today.dart';

/// Overridden in main() after bootstrapping.
final firebaseStatusProvider = Provider<FirebaseStatus>((ref) => FirebaseStatus.unavailable);
final repositoryProvider = Provider<ContentRepository>((ref) => throw UnimplementedError('override in main'));
final adminRepositoryProvider = Provider<AdminRepository?>((ref) => null);

/// Reads (public) and uploads (admin) optional item images; null when
/// Firebase is unavailable (inline images then show their placeholder).
final mediaRepositoryProvider = Provider<MediaRepository?>((ref) => null);

final settingsProvider = StreamProvider<ChurchSettings>((ref) => ref.watch(repositoryProvider).settings());

/// Raw `settings/features` stream (one doc, streamed and cached by Firestore).
final featuresStreamProvider = StreamProvider<FeatureSettings>((ref) => ref.watch(repositoryProvider).features());

/// Current feature toggles. Until the doc arrives, everything is on (the
/// bundled defaults), so the first paint never blanks the page.
///
/// After an applied season preset's season has ended, the switches it changed
/// read their saved values ([FeatureSettings.effectiveAt], ADR-042). The clock
/// is watched through a bool, so this rebuilds once at the season end, not on
/// every tick.
final featuresProvider = Provider<FeatureSettings>((ref) {
  final f = ref.watch(featuresStreamProvider).value ?? FeatureSettings.defaults;
  final p = f.seasonPreset;
  if (p == null || p.endsAt == null) return f;
  final ended = ref.watch(nowProvider.select((n) => p.expiredAt(n.value ?? DateTime.now())));
  return ended ? f.effectiveAt(p.endsAt!) : f;
});

/// False until `settings/features` (or its seed fallback) has arrived, so
/// gated pages wait one cached read instead of flashing switched-off content.
final featuresReadyProvider = Provider<bool>((ref) {
  final f = ref.watch(featuresStreamProvider);
  return f.hasValue || f.hasError;
});

/// True once the first page content has arrived: settings/church, the
/// section switches and layout (settings/features) and the bundled verse list
/// of the home hero — live values or their fallbacks. Until then the HTML
/// loading screen stays up (ADR-038), so visitors never see the defaults
/// flash before the real data.
final contentReadyProvider = Provider<bool>((ref) => firstContentArrived(
      settings: ref.watch(settingsProvider),
      featuresReady: ref.watch(featuresReadyProvider),
      verses: ref.watch(dailyVersesProvider),
    ));

/// [contentReadyProvider]'s rule: every input has a value (or failed, which
/// shows its fallback / error state and must not hold the page).
@visibleForTesting
bool firstContentArrived({
  required AsyncValue<ChurchSettings> settings,
  required bool featuresReady,
  required AsyncValue<List<Verse>> verses,
}) =>
    (settings.hasValue || settings.hasError) && featuresReady && (verses.hasValue || verses.hasError);

/// The admin's error-report switch (ADR-034): null until `settings/features`
/// (or its seed fallback) has arrived; a failed stream means the default (on).
///
/// On Firestore, the bundled seed's copy (served while the seeding check cannot
/// answer, or when the doc is missing) does not count: the switch stays
/// unknown, so early events wait for the stored value (or the gate's
/// patience) instead of being let through by the seed's default (CodeRabbit).
final errorReportingSwitchProvider = Provider<bool?>((ref) {
  final repo = ref.watch(repositoryProvider);
  return errorReportingSwitch(ref.watch(featuresStreamProvider),
      seedCopy: repo is FirestoreRepository ? repo.seed.features : null);
});

/// [errorReportingSwitchProvider]'s rule: the stored value, null while loading
/// or while [f] is only the bundled [seedCopy], true (default) on error.
@visibleForTesting
bool? errorReportingSwitch(AsyncValue<FeatureSettings> f, {FeatureSettings? seedCopy}) {
  if (f.hasValue) {
    final v = f.value!;
    if (seedCopy != null && identical(v, seedCopy)) return null;
    return v.errorReporting;
  }
  if (f.hasError) return true;
  return null;
}

/// True once `settings/features` holds the stored doc, not the bundled seed
/// copy (ADR-046). On a cold, slow load the seeding check can time out and the
/// seed's defaults (every today switch on) are served first; blocks driven by
/// the today switches wait for this so they never flash and then vanish when
/// the stored doc (e.g. `topEvent: false`) arrives. Reads the existing
/// features stream: no new listener. Off Firestore (seed mode, tests) the
/// seed IS the content, so it counts; a failed stream shows the defaults.
///
/// The bundled copy is accepted after [featuresSeedPatience] (Seer review on
/// PR #39): the repository turns a failed stream or a database it cannot
/// reach into that copy, so offline (no cache) or on a failed stream the
/// card still comes back with its defaults instead of never showing. The
/// cold-load flicker had the stored doc ~12 s after the seed copy.
final featuresLiveProvider = Provider<bool>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo is! FirestoreRepository) return true;
  final f = ref.watch(featuresStreamProvider);
  if (featuresLive(f, seedCopy: repo.seed.features)) return true;
  // Only the seed copy so far: start (or read) the patience timer.
  return f.hasValue && ref.watch(_seedPatienceProvider);
});

/// How long the top event waits for the stored `settings/features` once the
/// bundled copy is all there is (ADR-046).
const featuresSeedPatience = Duration(seconds: 30);

/// False until [featuresSeedPatience] after it is first read.
final _seedPatienceProvider = NotifierProvider<_SeedPatience, bool>(_SeedPatience.new);

class _SeedPatience extends Notifier<bool> {
  @override
  bool build() {
    final t = Timer(featuresSeedPatience, () => state = true);
    ref.onDispose(t.cancel);
    return false;
  }
}

/// [featuresLiveProvider]'s rule on Firestore (the same `identical` test as
/// [errorReportingSwitch]): false while loading or while [f] is the bundled
/// [seedCopy]; true for a stored doc or a failed stream.
@visibleForTesting
bool featuresLive(AsyncValue<FeatureSettings> f, {required FeatureSettings seedCopy}) {
  if (f.hasValue) return !identical(f.value, seedCopy);
  return f.hasError;
}

/// Public lists: items an admin hid are dropped, the rest sorted by `order`.
Stream<List<T>> _public<T extends Hideable>(Stream<List<T>> s) => s.map(publicItems);

final alertsProvider = StreamProvider<List<Alert>>((ref) => _public(ref.watch(repositoryProvider).alerts()));
final seasonsProvider = StreamProvider<List<Season>>((ref) => ref.watch(repositoryProvider).seasons());
final liturgiesProvider = StreamProvider<List<Liturgy>>((ref) => _public(ref.watch(repositoryProvider).liturgies()));
final meetingsProvider = StreamProvider<List<Meeting>>((ref) => _public(ref.watch(repositoryProvider).meetings()));
final activitiesProvider = StreamProvider<List<Activity>>((ref) => _public(ref.watch(repositoryProvider).activities()));
final clinicsProvider = StreamProvider<List<Clinic>>((ref) => _public(ref.watch(repositoryProvider).clinics()));
final facilitiesProvider = StreamProvider<List<Facility>>((ref) => _public(ref.watch(repositoryProvider).facilities()));
final priestsProvider = StreamProvider<List<Priest>>((ref) => _public(ref.watch(repositoryProvider).priests()));
final milestonesProvider = StreamProvider<List<Milestone>>((ref) => _public(ref.watch(repositoryProvider).milestones()));
final saintsProvider = StreamProvider<List<Saint>>((ref) => _public(ref.watch(repositoryProvider).saints()));

/// Admin-defined categories (ADR-027): public ones (visible, usable slug,
/// unique), sorted by `order`.
final categoriesProvider =
    StreamProvider<List<CustomCategory>>((ref) => ref.watch(repositoryProvider).categories().map(publicCategories));

/// Every category item (filtered per category by [entriesOf]).
final entriesProvider = StreamProvider<List<CategoryEntry>>((ref) => ref.watch(repositoryProvider).entries());

/// Public custom pages (visible, usable slug, unique), sorted by `order`.
final customPagesProvider =
    StreamProvider<List<CustomPage>>((ref) => ref.watch(repositoryProvider).pages().map(publicPages));

/// Contact-form categories (ADR-028); code defaults until / unless stored.
final contactSettingsProvider =
    StreamProvider<ContactSettings>((ref) => ref.watch(repositoryProvider).contactSettings());

/// Assistant settings (ADR-029); code defaults until / unless stored.
final assistantSettingsProvider =
    StreamProvider<AssistantSettings>((ref) => ref.watch(repositoryProvider).assistantSettings());

/// The bundled verse-of-the-day list (assets/verses/daily_verses.json).
/// Read as bytes and decoded here (no `compute` isolate) so it also works in
/// widget tests, where it is usually overridden.
final dailyVersesProvider = FutureProvider<List<Verse>>((ref) async {
  final data = await rootBundle.load(dailyVersesAsset);
  return parseDailyVerses(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
});

/// Ticks every 30 s so time-based UI (next mass, "available today") stays fresh.
final nowProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Whether the assistant entry points should be shown.
final assistantVisibleProvider = Provider<bool>((ref) {
  final fb = ref.watch(firebaseStatusProvider);
  final s = ref.watch(settingsProvider).value;
  if (!ref.watch(featuresProvider).enabled(Sections.assistant)) return false;
  // Firebase AI Logic is App Check-enforced: without an active App Check
  // provider (e.g. no reCAPTCHA site key) requests would fail, so hide it.
  return fb.available && fb.appCheckActive && (s?.assistantEnabled ?? false);
});

/// Selected language. Two kinds of change, kept apart so the router can sync
/// `?lang=` in the right direction (see `resolveLangSync` in router.dart):
/// - [toggle]/[set] are the visitor's choice: the URL is rewritten to match.
/// - [syncFromUrl] follows the URL (deep link, browser Back/Forward): the URL
///   is left as it is.
class LocaleNotifier extends Notifier<Locale> {
  bool _userChange = false;

  @override
  Locale build() => initialLocale(Uri.base, ref.read(languageStoreProvider).read());

  /// Startup language (plan PR 3, 3.3): an explicit `?lang=` in the URL
  /// (shareable links) → the visitor's saved choice → Arabic.
  static Locale initialLocale(Uri uri, String? saved) {
    final code = switch (uri.queryParameters['lang']) {
      'en' => 'en',
      'ar' => 'ar',
      _ => saved == 'en' ? 'en' : 'ar',
    };
    return Locale(code);
  }

  void toggle() => set(state.languageCode == 'ar' ? const Locale('en') : const Locale('ar'));

  /// The visitor's choice: rewrites `?lang=` and is remembered for next visit.
  void set(Locale l) {
    if (l == state) return;
    _userChange = true;
    state = l;
    ref.read(languageStoreProvider).write(l.languageCode);
  }

  /// The URL asked for [l]; the URL already says so, nothing to rewrite.
  void syncFromUrl(Locale l) {
    if (l != state) state = l;
  }

  /// True once after [toggle]/[set]: the next redirect writes `?lang=`.
  bool consumeUserChange() {
    final v = _userChange;
    _userChange = false;
    return v;
  }
}

/// Where the language choice is remembered (overridden in tests).
final languageStoreProvider = Provider<LanguageStore>((ref) => const PlatformLanguageStore());

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

/// The theme in force (ADR-025).
@immutable
class ActiveTheme {
  final String key;
  final ThemeSource source;
  final ThemePalette palette;
  const ActiveTheme(this.key, this.source, this.palette);

  @override
  bool operator ==(Object other) =>
      other is ActiveTheme && other.key == key && other.source == source && other.palette == palette;

  @override
  int get hashCode => Object.hash(key, source, palette);
}

/// Resolves `settings/features` (selected theme, admin ranges, the active
/// church season, Coptic Easter on the Cairo calendar day, colour edits)
/// into the theme in force (ADR-025, ADR-043). Equal values do not notify,
/// so the app rebuilds its theme only when the theme actually changes.
///
/// The active season comes from the `seasons` list (the same stream the
/// home page's next-service card and /mass-schedule already hold) and, until
/// that list has loaded, from the applied season preset in
/// `settings/features.seasonPreset` (no extra read), so a Holy Week visit
/// paints dark from the first frame. Followed only while
/// `occasions.followSeason` is on.
final activeThemeProvider = Provider<ActiveTheme>((ref) {
  final f = ref.watch(featuresProvider);
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final c = CairoTime.fromInstant(now);
  final keys = f.occasions.followSeason ? ref.watch(activeSeasonKeysProvider).split(',') : const <String>[];
  final r = f.themeOn(DateTime.utc(c.year, c.month, c.day), activeSeasonKeys: keys);
  return ActiveTheme(r.theme, r.source, f.occasions.paletteFor(r.theme));
});

/// Keys of the church seasons active now (ADR-043), sorted and joined by
/// ',' (a String compares by value, so the clock tick does not notify):
/// from the loaded seasons list, else from the season preset in force.
final activeSeasonKeysProvider = Provider<String>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final seasons = ref.watch(seasonsProvider);
  if (seasons.hasValue) {
    return ({for (final s in activeSeasonsAt(seasons.value!, now)) s.key}.toList()..sort()).join(',');
  }
  final p = ref.watch(featuresStreamProvider).value?.seasonPreset;
  return p != null && p.seasonKey.isNotEmpty && p.seasonRunningAt(now) ? p.seasonKey : '';
});

// ------------------------- today layer (ADR-039 / ADR-040) -------------------------
// Everything below reads settings/features (already streamed for every
// visit) and the bundled / hosted data: no extra Firestore listener or read.

/// "Today" settings (top-level keys of settings/features).
final todaySettingsProvider = Provider<TodaySettings>((ref) => ref.watch(featuresProvider.select((f) => f.today)));

/// The liturgical day now (rolls at 18:00 by default; equal values do not
/// notify, so it changes at most twice a day).
final liturgicalDayProvider = Provider<LiturgicalDay>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final s = ref.watch(settingsProvider).value;
  return ref.watch(todaySettingsProvider).liturgicalDay(now, lat: s?.lat, lng: s?.lng);
});

/// Reads /data/today.json (overridden in tests).
final synaxariumSourceProvider = Provider<SynaxariumSource>((ref) => SynaxariumSource());

/// The Katameros commemoration (/data/today.json), loaded after the page is
/// complete and idle; empty in seed mode (no Firebase: offline or tests).
final synaxariumProvider = FutureProvider<SynaxariumData>((ref) async {
  if (!ref.watch(repositoryProvider).isLive) return SynaxariumData.empty;
  final date = ref.watch(liturgicalDayProvider.select((d) => d.date));
  await ContentReady.whenIdle;
  return ref.read(synaxariumSourceProvider).load(date);
});

/// The home page's top event (church event > today's programme service >
/// Katameros > computed feasts; ADR-040, ADR-045).
final topEventProvider = Provider<TopEvent?>((ref) {
  // Only on the stored today switches, never the seed's defaults (ADR-046).
  if (!ref.watch(featuresLiveProvider)) return null;
  final f = ref.watch(featuresProvider);
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final s = ref.watch(settingsProvider).value;
  // The programme-service step reads the liturgies / seasons listeners only
  // while Home already holds them for the next-service card (+0 listeners,
  // ADR-045); otherwise it is skipped.
  final services = f.today.topEvent && f.today.topEventServices && f.visibleHomeBlocks.contains(HomeBlocks.nextMass);
  return resolveTopEvent(
    now: now,
    settings: f.today,
    events: f.dayEvents,
    liturgies: services ? (ref.watch(liturgiesProvider).value ?? const []) : const [],
    seasons: services ? (ref.watch(seasonsProvider).value ?? const []) : const [],
    synaxarium: ref.watch(synaxariumProvider).value ?? SynaxariumData.empty,
    lat: s?.lat,
    lng: s?.lng,
  );
});

// ------------------- App Install & Push Notifications (ADR-057) -------------------

/// App install banner settings (ADR-057).
final installSettingsProvider = Provider<InstallSettings>((ref) {
  return ref.watch(featuresProvider.select((f) => f.install));
});

/// Push notifications settings (ADR-057).
final pushSettingsProvider = Provider<PushSettings>((ref) {
  return ref.watch(featuresProvider.select((f) => f.pushSettings));
});

/// Install environment provider (overridable in tests).
final installEnvProvider = Provider<InstallEnv>((ref) => const PlatformInstallEnv());

/// Push environment provider (overridable in tests).
final pushEnvProvider = Provider<PushEnv>((ref) => const PlatformPushEnv());

/// The browser's notification permission ('default' / 'granted' /
/// 'denied'). Invalidated after a permission request: the value is re-read,
/// and a changed string (e.g. 'default' -> 'denied') rebuilds its readers.
final pushPermissionProvider = Provider<String>((ref) => ref.watch(pushEnvProvider).permission);

/// Device reminder store provider (overridable in tests).
final reminderStoreProvider = Provider<ReminderStore>((ref) {
  return ReminderStore(env: ref.watch(installEnvProvider));
});

/// Push preferences state notifier and provider.
final pushPrefsProvider = NotifierProvider<PushPrefsNotifier, PushPrefs>(PushPrefsNotifier.new);

class PushPrefsNotifier extends Notifier<PushPrefs> {
  @override
  PushPrefs build() {
    final env = ref.watch(installEnvProvider);
    final pushSettings = ref.watch(pushSettingsProvider);
    return PushPrefs.fromJson(env.readJson(pushStorageKey), offered: pushSettings.offered);
  }

  void toggleType(NotifyType type) {
    final nextTypes = Set<NotifyType>.of(state.types);
    if (nextTypes.contains(type)) {
      nextTypes.remove(type);
    } else {
      nextTypes.add(type);
    }
    _update(state.copyWith(types: nextTypes, updatedAt: DateTime.now().toUtc()));
  }

  void setAllTypes(Set<NotifyType> types) {
    _update(state.copyWith(types: types, updatedAt: DateTime.now().toUtc()));
  }

  void firstOptIn() {
    final offered = ref.read(pushSettingsProvider).offered;
    final defaultTypes = PushPrefs.firstOptInTypes.where(offered.contains).toSet();
    _update(state.copyWith(types: defaultTypes, updatedAt: DateTime.now().toUtc()));
  }

  /// Unsubscribe from everything, including types not offered right now.
  void clearAll() {
    _update(state.copyWith(types: const {}, updatedAt: DateTime.now().toUtc()), keepUnoffered: false);
  }

  void setLang(String lang) {
    _update(state.copyWith(lang: lang, updatedAt: DateTime.now().toUtc()));
  }

  /// Publishes [next] and stores it. The state only holds offered types, so
  /// with [keepUnoffered] the stored choices for types an admin has hidden
  /// for now are carried over, and come back when the type is offered again.
  void _update(PushPrefs next, {bool keepUnoffered = true}) {
    state = next;
    try {
      final env = ref.read(installEnvProvider);
      var stored = next;
      if (keepUnoffered) {
        final offered = ref.read(pushSettingsProvider).offered;
        final hidden = PushPrefs.fromJson(env.readJson(pushStorageKey)).types.where((t) => !offered.contains(t));
        if (hidden.isNotEmpty) stored = next.copyWith(types: {...next.types, ...hidden});
      }
      env.writeJson(pushStorageKey, stored.toJson());
    } catch (_) {}
  }
}

/// User's device reminders notifier and provider.
final userRemindersProvider = NotifierProvider<UserRemindersNotifier, List<Reminder>>(UserRemindersNotifier.new);

class UserRemindersNotifier extends Notifier<List<Reminder>> {
  @override
  List<Reminder> build() {
    final store = ref.watch(reminderStoreProvider);
    return store.load();
  }

  ReminderPutResult put(Reminder reminder, {Reminder? replacing}) {
    final store = ref.read(reminderStoreProvider);
    final result = store.put(reminder, replacing: replacing);
    if (result == ReminderPutResult.ok) {
      state = store.load();
    }
    return result;
  }

  void remove(String eventKey, {String? occurrence}) {
    final store = ref.read(reminderStoreProvider);
    store.remove(eventKey, occurrence: occurrence);
    state = store.load();
  }

  void clearExpired(DateTime now) {
    final store = ref.read(reminderStoreProvider);
    store.clearExpired(now);
    state = store.load();
  }
}

// ------------------- In-App Updates (ADR-058 / PR B §3.3) -------------------

/// In-app updater service provider (IO on Android / stub on web).
final appUpdaterProvider = Provider<AppUpdater>((ref) => AppUpdater());

/// Current installed application build number (defaults to 1).
final currentAppBuildProvider = FutureProvider<int>((ref) async {
  if (kIsWeb) return 1;
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 1;
  } catch (_) {
    return 1;
  }
});

/// Evaluates whether an in-app update is available for the current Android client.
final updateDecisionProvider = FutureProvider<UpdateDecision?>((ref) async {
  if (kIsWeb) return null;
  final updater = ref.watch(appUpdaterProvider);
  if (!updater.isSupported) return null;

  final installSettings = ref.watch(installSettingsProvider);
  final installApkBuild = installSettings.apkBuild;
  final currentBuild = await ref.watch(currentAppBuildProvider.future);

  if (installApkBuild <= currentBuild) return null;

  return updater.checkForUpdate(
    currentBuild: currentBuild,
    installApkBuild: installApkBuild,
  );
});

