// Notification state, scheduling provider, and background replenishment (ADR-058 / PR B).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../data/local_notifications.dart';
import '../domain/cairo_time.dart';
import '../domain/daily_verse.dart';
import '../domain/features.dart';
import '../domain/models.dart';
import '../domain/notify_plan.dart';
import '../domain/readings.dart';
import '../domain/reminders.dart';
import '../domain/schedule.dart';
import 'providers.dart';

/// SharedPreferences key for the local notification plan JSON list.
const notifyPlanStorageKey = 'church_portal_notify_plan';

/// SharedPreferences key for the planner inputs snapshot JSON.
const notifySnapshotStorageKey = 'church_portal_notify_snapshot';

/// SharedPreferences key for recording the last background replenishment timestamp.
const notifyDiagLastReplenishKey = 'church_portal_diag_last_replenish';

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
        'features': features.toMap(),
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
  List<PlannedNotification> _currentPlan = const [];
  bool _isPlanning = false;
  bool _needsAnotherReplan = false;

  NotifyPlanner(this.ref) {
    _listen();
  }

  List<PlannedNotification> get currentPlan => _currentPlan;
  bool get hasActiveDebounce => _debounceTimer?.isActive ?? false;

  void _listen() {
    ref.listen<PushPrefs>(pushPrefsProvider, (prev, next) => scheduleReplan());
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

      final sp = prefs ?? await SharedPreferences.getInstance();
      final cachedReadings = loadCachedReadingsFromStorage(sp, cNow);

      final plan = planNotifications(
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
      );

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
    _debounceTimer?.cancel();
  }
}

/// WorkManager top-level callback dispatcher for background notification replenishment.
@pragma('vm:entry-point')
void notificationReplenishCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return await executeReplenishmentTask();
  });
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

  final localNotifier = notifier ?? LocalNotifier();
  final exactAllowed = await localNotifier.canScheduleExactAlarms();

  final newPlan = planNotifications(
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
  );

  await localNotifier.schedulePlan(newPlan, lang: snapshot.pushPrefs.lang);

  final planJson = jsonEncode(newPlan.map((n) => n.toJson()).toList());
  await sp.setString(notifyPlanStorageKey, planJson);
  await sp.setString(notifyDiagLastReplenishKey, effectiveNow.toIso8601String());

  return true;
}
