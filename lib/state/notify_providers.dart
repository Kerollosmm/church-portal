// Notification state, scheduling provider, and background replenishment (ADR-058 / PR B).

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../core/motion_env.dart';
import '../data/local_notifications.dart';
import '../data/push_messaging.dart';
import '../data/readings_store.dart';
import '../domain/cairo_time.dart';
import '../domain/daily_verse.dart';
import '../domain/features.dart';
import '../domain/models.dart';
import '../domain/notify_plan.dart';
import '../domain/readings.dart';
import '../domain/reminders.dart';
import '../domain/schedule.dart';
import '../domain/season_verses.dart';
import '../domain/today.dart';
import 'providers.dart';

/// SharedPreferences key for the local notification plan JSON list.
const notifyPlanStorageKey = 'church_portal_notify_plan';

/// SharedPreferences key for the planner inputs snapshot JSON.
const notifySnapshotStorageKey = 'church_portal_notify_snapshot';

/// SharedPreferences key for recording the last background replenishment timestamp.
const notifyDiagLastReplenishKey = 'church_portal_diag_last_replenish';

/// Unique Workmanager job name for unmetered 7-day readings prefetch.
const readingsPrefetchUniqueName = 'church_portal_readings_prefetch';

/// Workmanager task name dispatched to prefetch upcoming Katameros readings.
const readingsPrefetchTaskName = 'readingsPrefetch';

/// Daily verse configuration provider derived from [featuresProvider].
final dailyVerseConfigProvider = Provider<DailyVerseConfig>((ref) {
  return ref.watch(featuresProvider.select((f) => f.dailyVerse));
});

/// Local notification manager instance provider (overridable in tests).
final localNotifierProvider = Provider<LocalNotifier>((ref) {
  return LocalNotifier();
});

/// Notification planner provider coordinating debounced re-planning.
final notifyPlannerProvider = Provider<NotifyPlanner>((ref) {
  final planner = NotifyPlanner(ref);
  ref.onDispose(planner.dispose);
  return planner;
});

/// FCM topic subscription updater (overridable in tests).
final topicSyncProvider = Provider<Future<bool> Function(PushPrefs prefs, String lang)>(
  (ref) => PushMessaging.updateSubscriptions,
);

/// Loads the currently stored plan from SharedPreferences.
Future<List<PlannedNotification>> loadStoredPlan({SharedPreferences? prefs}) async {
  final sp = prefs ?? await SharedPreferences.getInstance();
  final raw = sp.getString(notifyPlanStorageKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map>()
        .map((m) => PlannedNotification.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Computes liturgy occurrences for up to 60 days in Cairo time.
List<LiturgyOccurrence> computeLiturgyOccurrences(
  List<Liturgy> liturgies,
  List<Season> seasons,
  tz.TZDateTime cNow,
) {
  final list = <LiturgyOccurrence>[];
  for (var d = 0; d < 60; d++) {
    list.addAll(occurrencesForDay(
      liturgies: liturgies,
      seasons: seasons,
      day: CairoTime.at(cNow.year, cNow.month, cNow.day + d),
      dayOffset: d,
    ));
  }
  return list;
}

/// Computes meeting occurrences for up to 60 days in Cairo time.
List<MeetingOccurrence> computeMeetingOccurrences(
  List<Meeting> meetings,
  tz.TZDateTime cNow,
) {
  final list = <MeetingOccurrence>[];
  for (final m in meetings) {
    for (var d = 0; d < 60; d++) {
      final targetDay = CairoTime.at(cNow.year, cNow.month, cNow.day + d);
      if (m.weekday != null && m.weekday == targetDay.weekday) {
        final sMin = parseHm(m.start) ?? 0;
        final eMin = parseHm(m.end) ?? (sMin + 60);
        list.add(MeetingOccurrence(
          m,
          CairoTime.at(targetDay.year, targetDay.month, targetDay.day, sMin),
          CairoTime.at(targetDay.year, targetDay.month, targetDay.day, eMin),
          d,
        ));
      }
    }
  }
  return list;
}

/// Reads cached readings for the rolling 9-day window from storage.
Map<String, DayReadings> loadCachedReadingsFromStorage(
  SharedPreferences sp,
  tz.TZDateTime cNow,
) {
  final cached = <String, DayReadings>{};
  for (var d = 0; d < 9; d++) {
    final dayDate = CairoTime.at(cNow.year, cNow.month, cNow.day + d);
    final iso = isoDate(dayDate);
    final raw = sp.getString('church_portal_readings_$iso');
    if (raw != null && raw.isNotEmpty) {
      try {
        cached[iso] = DayReadings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }
  return cached;
}

/// Serialized snapshot of planner inputs used by background replenishment workers.
class PlannerSnapshot {
  final DateTime savedAt;
  final PushPrefs pushPrefs;
  final FeatureSettings features;
  final List<Reminder> reminders;
  final DailyVerseConfig verseConfig;
  final List<Verse> verses;
  final List<Liturgy> liturgies;
  final List<Meeting> meetings;
  final List<Season> seasons;

  PlannerSnapshot({
    required this.savedAt,
    required this.pushPrefs,
    required this.features,
    required this.reminders,
    required this.verseConfig,
    required this.verses,
    required this.liturgies,
    required this.meetings,
    required this.seasons,
  });

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'pushPrefs': pushPrefs.toJson(),
        'features': snapshotFeaturesMap(features),
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'verseConfig': verseConfig.toMap(),
        'verses': verses
            .map((v) => {
                  'textAr': v.textAr,
                  'refAr': v.refAr,
                  'refEn': v.refEn,
                  'textEn': v.textEn,
                })
            .toList(),
        'liturgies': liturgies.map(_liturgyToMap).toList(),
        'meetings': meetings.map(_meetingToMap).toList(),
        'seasons': seasons.map(_seasonToMap).toList(),
      };

  factory PlannerSnapshot.fromJson(Map<String, dynamic> json) {
    final pushPrefsJson = json['pushPrefs'];
    final pushPrefsMap = pushPrefsJson is Map ? Map<String, dynamic>.from(pushPrefsJson) : null;

    final featuresJson = json['features'];
    final featuresMap = featuresJson is Map ? Map<String, dynamic>.from(featuresJson) : null;

    return PlannerSnapshot(
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      pushPrefs: PushPrefs.fromJson(pushPrefsMap),
      features: featuresMap != null ? FeatureSettings.fromMap(featuresMap) : FeatureSettings.defaults,
      reminders: (json['reminders'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Reminder.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      verseConfig: DailyVerseConfig.fromMap(json['verseConfig']),
      verses: (json['verses'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Verse(
                textAr: m['textAr'] as String? ?? '',
                refAr: m['refAr'] as String? ?? '',
                refEn: m['refEn'] as String? ?? '',
                textEn: m['textEn'] as String? ?? '',
              ))
          .toList(),
      liturgies: (json['liturgies'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Liturgy.fromMap(m['id'] as String? ?? '', Map<String, dynamic>.from(m)))
          .toList(),
      meetings: (json['meetings'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Meeting.fromMap(m['id'] as String? ?? '', Map<String, dynamic>.from(m)))
          .toList(),
      seasons: (json['seasons'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Season.fromMap(m['id'] as String? ?? '', Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

/// `FeatureSettings.toMap()` is the admin-editor map and omits the push keys, `dayEvents` and
/// `seasonVerses`;
/// the background worker needs both, or it would plan types the admin withdrew and lose the
/// times of day-event reminders. Written in the Firestore shape so `FeatureSettings.fromMap`
/// reads them back unchanged.
Map<String, dynamic> snapshotFeaturesMap(FeatureSettings f) => {
      ...f.toMap(),
      'push': f.pushSettings.enabled,
      'pushTypes': f.pushSettings.offered.map((t) => t.name).toList(),
      'reminderLeads': f.pushSettings.reminderLeads,
      'reminderDefaultLead': f.pushSettings.defaultLead,
      'reminderSources': f.pushSettings.reminderSources.toList()..sort(),
      'dayEvents': _dayEventsForSnapshot(f.dayEvents),
      'seasonVerses': [
        for (final e in f.seasonVerses.bySeason.entries)
          for (final v in e.value) [e.key, v.textAr, v.refAr, v.textEn, v.refEn].join(SeasonVerses.sep),
      ],
    };

/// Day events keep their stored id and fields.
List<Map<String, dynamic>?> _dayEventsForSnapshot(List<DayEvent> events) {
  final out = <Map<String, dynamic>?>[];
  for (final e in events) {
    final map = {
      'id': e.id,
      'date': e.date != null ? isoDate(e.date!) : null,
      'endDate': e.endDate != null ? isoDate(e.endDate!) : null,
      'start': e.start,
      'end': e.end,
      'titleAr': e.titleAr,
      'titleEn': e.titleEn,
      'link': e.link,
      'visible': e.visible,
    };
    out.add(map);
  }
  return out;
}

Map<String, dynamic> _liturgyToMap(Liturgy l) => {
      'id': l.id,
      'type': l.type,
      'nameAr': l.nameAr,
      'nameEn': l.nameEn,
      'weekday': l.weekday,
      'date': l.date?.toIso8601String(),
      'start': l.start,
      'end': l.end,
      'placeAr': l.placeAr,
      'placeEn': l.placeEn,
      'seasonKey': l.seasonKey,
      'order': l.order,
      'sample': l.sample,
      'replacesDay': l.replacesDay,
    };

Map<String, dynamic> _meetingToMap(Meeting m) => {
      'id': m.id,
      'stage': m.stage,
      'nameAr': m.nameAr,
      'nameEn': m.nameEn,
      'weekday': m.weekday,
      'start': m.start,
      'end': m.end,
      'hallAr': m.hallAr,
      'hallEn': m.hallEn,
      'notes': m.notes,
      'sample': m.sample,
    };

Map<String, dynamic> _seasonToMap(Season s) => {
      'id': s.id,
      'key': s.key,
      'nameAr': s.nameAr,
      'nameEn': s.nameEn,
      'startsAt': s.startsAt?.toIso8601String(),
      'endsAt': s.endsAt?.toIso8601String(),
      'active': s.active,
      'replacesRegular': s.replacesRegular,
      'replaceDates': s.replaceDates,
    };

/// Saves a snapshot of inputs into SharedPreferences.
Future<void> savePlannerSnapshot({
  required SharedPreferences prefs,
  required DateTime now,
  required PushPrefs pushPrefs,
  required FeatureSettings features,
  required List<Reminder> reminders,
  required DailyVerseConfig verseConfig,
  required List<Verse> verses,
  required List<Liturgy> liturgies,
  required List<Meeting> meetings,
  required List<Season> seasons,
}) async {
  final snapshot = PlannerSnapshot(
    savedAt: now,
    pushPrefs: pushPrefs,
    features: features,
    reminders: reminders,
    verseConfig: verseConfig,
    verses: verses,
    liturgies: liturgies,
    meetings: meetings,
    seasons: seasons,
  );
  await prefs.setString(notifySnapshotStorageKey, jsonEncode(snapshot.toJson()));
}

/// Loads the stored planner snapshot from SharedPreferences.
Future<PlannerSnapshot?> loadPlannerSnapshot({SharedPreferences? prefs}) async {
  final sp = prefs ?? await SharedPreferences.getInstance();
  final raw = sp.getString(notifySnapshotStorageKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return PlannerSnapshot.fromJson(map);
  } catch (_) {
    return null;
  }
}

/// Manages debounced local notification re-planning in the foreground app.
class NotifyPlanner {
  final Ref ref;
  Timer? _debounceTimer;
  AppLifecycleListener? _lifecycleListener;
  List<PlannedNotification> _currentPlan = const [];
  bool _isPlanning = false;
  bool _needsAnotherReplan = false;
  bool _disposed = false;
  bool _pendingTopicSync = false;
  bool _retryingTopicSync = false;
  bool _retryPendingReconnect = false;
  Future<void>? _inFlightTopicSync;
  ({PushPrefs prefs, String lang})? _queuedTopicSync;

  NotifyPlanner(this.ref) {
    _listen();
    _syncSubscriptions();
    if (!kIsWeb) {
      try {
        _lifecycleListener = AppLifecycleListener(
          onResume: () {
            if (!MotionEnv.isTest && defaultTargetPlatform == TargetPlatform.iOS) {
              scheduleReplan(Duration.zero);
            }
            unawaited(_retryPendingTopicSync());
          },
        );
      } catch (_) {}
    }
  }

  List<PlannedNotification> get currentPlan => _currentPlan;
  bool get hasActiveDebounce => _debounceTimer?.isActive ?? false;
  @visibleForTesting
  bool get hasPendingTopicSyncInMemory => _pendingTopicSync;

  void _syncSubscriptions() {
    final prefs = ref.read(pushPrefsProvider);
    final lang = ref.read(localeProvider).languageCode;
    unawaited(_runTopicSync(prefs, lang));
  }

  Future<void> _runTopicSync(PushPrefs prefs, String lang) async {
    if (_disposed) return;
    if (_inFlightTopicSync != null) {
      _queuedTopicSync = (prefs: prefs, lang: lang);
      return _inFlightTopicSync!;
    }
    Future<void> run() async {
      var current = (prefs: prefs, lang: lang);
      while (!_disposed) {
        var ok = false;
        try {
          ok = await ref.read(topicSyncProvider)(current.prefs, current.lang);
        } catch (_) {
          ok = false;
        }
        _pendingTopicSync = !ok;
        if (ok) {
          _retryPendingReconnect = false;
        }
        final next = _queuedTopicSync;
        _queuedTopicSync = null;
        if (next != null) {
          current = next;
          continue;
        }
        if (!ok && _retryPendingReconnect) {
          _retryPendingReconnect = false;
          current = (
            prefs: ref.read(pushPrefsProvider),
            lang: ref.read(localeProvider).languageCode,
          );
          continue;
        }
        break;
      }
    }

    final future = run();
    _inFlightTopicSync = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightTopicSync, future)) {
        _inFlightTopicSync = null;
      }
    }
  }

  Future<void> _retryPendingTopicSync() async {
    if (_disposed) return;
    if (_inFlightTopicSync != null) {
      _retryPendingReconnect = true;
      return;
    }
    if (_retryingTopicSync) return;
    _retryingTopicSync = true;
    try {
      final hasPending = _pendingTopicSync || await PushMessaging.hasPendingTopicSync();
      if (!hasPending || _disposed) return;
      final prefs = ref.read(pushPrefsProvider);
      final lang = ref.read(localeProvider).languageCode;
      await _runTopicSync(prefs, lang);
    } finally {
      _retryingTopicSync = false;
    }
  }

  void _listen() {
    ref.listen<PushPrefs>(pushPrefsProvider, (prev, next) {
      scheduleReplan();
      final lang = ref.read(localeProvider).languageCode;
      unawaited(_runTopicSync(next, lang));
    });
    ref.listen<Locale>(localeProvider, (prev, next) {
      final prefs = ref.read(pushPrefsProvider);
      if (prefs.lang != next.languageCode) {
        Future.microtask(() {
          if (!_disposed) {
            ref.read(pushPrefsProvider.notifier).setLang(next.languageCode);
          }
        });
      }
      unawaited(_runTopicSync(prefs, next.languageCode));
    });
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOnline = prev?.value;
      final isOnline = next.value;
      if (wasOnline == false && isOnline == true) {
        unawaited(_retryPendingTopicSync());
      }
    });
    ref.listen<FeatureSettings>(featuresProvider, (prev, next) => scheduleReplan());
    ref.listen<AsyncValue<List<Liturgy>>>(liturgiesProvider, (prev, next) => scheduleReplan());
    ref.listen<List<Reminder>>(userRemindersProvider, (prev, next) => scheduleReplan());
    ref.listen<DailyVerseConfig>(dailyVerseConfigProvider, (prev, next) => scheduleReplan());
    ref.listen<AsyncValue<List<Verse>>>(dailyVersesProvider, (prev, next) => scheduleReplan());
    ref.listen<AsyncValue<List<Meeting>>>(meetingsProvider, (prev, next) => scheduleReplan());
    ref.listen<AsyncValue<List<Season>>>(seasonsProvider, (prev, next) => scheduleReplan());
  }

  /// Triggers a re-planning cycle after [delay] (defaults to 2 seconds debounce).
  void scheduleReplan([Duration delay = const Duration(seconds: 2)]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      replan();
    });
  }

  /// Executes plan generation immediately, updates notifications, and stores snapshots.
  Future<List<PlannedNotification>> replan({
    DateTime? now,
    SharedPreferences? prefs,
  }) async {
    _debounceTimer?.cancel();
    if (_isPlanning) {
      _needsAnotherReplan = true;
      return _currentPlan;
    }
    _isPlanning = true;

    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await sp.remove(notifyPlanStorageKey);
        _currentPlan = const [];
        return const [];
      }

      final effectiveNow = now ?? DateTime.now();
      CairoTime.ensureInitialized();
      final cNow = CairoTime.fromInstant(effectiveNow);

      final pushPrefs = ref.read(pushPrefsProvider);
      final features = ref.read(featuresProvider);
      final reminders = ref.read(userRemindersProvider);
      final verseConfig = ref.read(dailyVerseConfigProvider);
      final verses = ref.read(dailyVersesProvider).value ?? const [];
      final liturgies = ref.read(liturgiesProvider).value ?? const [];
      final meetings = ref.read(meetingsProvider).value ?? const [];
      final seasons = ref.read(seasonsProvider).value ?? const [];
      final notifier = ref.read(localNotifierProvider);

      final exactAllowed = await notifier.canScheduleExactAlarms();

      final liturgyOccurrences = computeLiturgyOccurrences(liturgies, seasons, cNow);
      final meetingOccurrences = computeMeetingOccurrences(meetings, cNow);

      final cachedReadings = loadCachedReadingsFromStorage(sp, cNow);

      final rawPlan = planNotifications(
        now: effectiveNow,
        prefs: pushPrefs,
        features: features,
        reminders: reminders,
        verseConfig: verseConfig,
        verses: verses,
        liturgies: liturgyOccurrences,
        meetings: meetingOccurrences,
        dayEvents: features.dayEvents,
        cachedReadings: cachedReadings,
        computedFeasts: const [],
        exactAlarmsAllowed: exactAllowed,
        seasons: seasons,
      );
      final plan = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? capPlanForPlatform(rawPlan, now: effectiveNow, maxPending: iosPendingNotificationCap)
          : rawPlan;

      await notifier.schedulePlan(plan, lang: pushPrefs.lang);

      final planJson = jsonEncode(plan.map((n) => n.toJson()).toList());
      await sp.setString(notifyPlanStorageKey, planJson);

      await savePlannerSnapshot(
        prefs: sp,
        now: effectiveNow,
        pushPrefs: pushPrefs,
        features: features,
        reminders: reminders,
        verseConfig: verseConfig,
        verses: verses,
        liturgies: liturgies,
        meetings: meetings,
        seasons: seasons,
      );

      _currentPlan = plan;
      return plan;
    } finally {
      _isPlanning = false;
      if (_needsAnotherReplan) {
        _needsAnotherReplan = false;
        scheduleReplan(Duration.zero);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _lifecycleListener?.dispose();
  }
}

/// WorkManager top-level callback dispatcher for background replenishment and
/// unmetered 7-day readings prefetch.
@pragma('vm:entry-point')
void notificationReplenishCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == readingsPrefetchTaskName) {
      return await executeReadingsPrefetchTask();
    }
    return await executeReplenishmentTask();
  });
}

/// Prefetches the next 7 Cairo days of Katameros readings and prunes days
/// older than yesterday in Africa/Cairo time.
Future<bool> executeReadingsPrefetchTask({
  DateTime? now,
  ReadingsStore? store,
}) async {
  CairoTime.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return true;
  }
  final target = store ?? ReadingsStore();
  await target.prefetchUpcomingDays(todayCairo: now);
  return true;
}

/// Executes daily replenishment check and re-schedules local notifications if needed.
Future<bool> executeReplenishmentTask({
  DateTime? now,
  SharedPreferences? prefs,
  LocalNotifier? notifier,
}) async {
  CairoTime.ensureInitialized();
  final effectiveNow = now ?? DateTime.now();
  final sp = prefs ?? await SharedPreferences.getInstance();
  // «آخر تشغيل في الخلفية» (diagnostic, PR B §3.6): stamped on every run, not only when the
  // window needed refilling, so a healthy worker never shows as stale.
  await sp.setString(notifyDiagLastReplenishKey, effectiveNow.toIso8601String());

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return true;
  }

  final currentPlan = await loadStoredPlan(prefs: sp);

  // If we still have >= 4 future days scheduled, no replenishment is needed.
  if (!needsReplenishment(currentPlan, effectiveNow, minRemainingDays: 4)) {
    return true;
  }

  final snapshot = await loadPlannerSnapshot(prefs: sp);
  if (snapshot == null) {
    return true;
  }

  final cNow = CairoTime.fromInstant(effectiveNow);
  final liturgyOccurrences = computeLiturgyOccurrences(snapshot.liturgies, snapshot.seasons, cNow);
  final meetingOccurrences = computeMeetingOccurrences(snapshot.meetings, cNow);
  final cachedReadings = loadCachedReadingsFromStorage(sp, cNow);

  // The worker runs in its own isolate: the plugin there has not been initialised yet.
  final localNotifier = notifier ?? LocalNotifier();
  if (notifier == null) await localNotifier.initialize();
  final exactAllowed = await localNotifier.canScheduleExactAlarms();

  final rawPlan = planNotifications(
    now: effectiveNow,
    prefs: snapshot.pushPrefs,
    features: snapshot.features,
    reminders: snapshot.reminders,
    verseConfig: snapshot.verseConfig,
    verses: snapshot.verses,
    liturgies: liturgyOccurrences,
    meetings: meetingOccurrences,
    dayEvents: snapshot.features.dayEvents,
    cachedReadings: cachedReadings,
    computedFeasts: const [],
    exactAlarmsAllowed: exactAllowed,
    seasons: snapshot.seasons,
  );
  final newPlan = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      ? capPlanForPlatform(rawPlan, now: effectiveNow, maxPending: iosPendingNotificationCap)
      : rawPlan;

  await localNotifier.schedulePlan(newPlan, lang: snapshot.pushPrefs.lang);

  final planJson = jsonEncode(newPlan.map((n) => n.toJson()).toList());
  await sp.setString(notifyPlanStorageKey, planJson);

  return true;
}
