import 'package:timezone/timezone.dart' as tz;

import 'cairo_time.dart';
import 'models.dart';

/// A concrete liturgy occurrence on a given Cairo day.
class LiturgyOccurrence {
  final Liturgy liturgy;
  final tz.TZDateTime start;
  final tz.TZDateTime end;

  /// 0 = today, 1 = tomorrow, ...
  final int dayOffset;
  const LiturgyOccurrence(this.liturgy, this.start, this.end, this.dayOffset);

  bool isHappeningAt(DateTime instant) => !instant.isBefore(start) && instant.isBefore(end);

  @override
  String toString() => 'LiturgyOccurrence(${liturgy.id}, $start-$end, +$dayOffset)';
}

class NextMassResult {
  /// Liturgy currently in progress (now within [start, end)).
  final LiturgyOccurrence? happeningNow;

  /// Next liturgy whose start is after now (today, else tomorrow, else the
  /// next day that has one within a week).
  final LiturgyOccurrence? next;

  /// Seasons that are overriding the regular schedule right now.
  final List<Season> activeSeasons;
  const NextMassResult({this.happeningNow, this.next, this.activeSeasons = const []});

  bool get isEmpty => happeningNow == null && next == null;
}

/// Is [s] active at [instant]? (flag on and instant within [startsAt, endsAt]).
bool isSeasonActiveAt(Season s, DateTime instant) {
  if (!s.active) return false;
  if (s.startsAt != null && instant.isBefore(s.startsAt!)) return false;
  if (s.endsAt != null && instant.isAfter(s.endsAt!)) return false;
  return true;
}

/// Is [s] active at any moment during the Cairo calendar day starting at
/// [dayStart]?
bool isSeasonActiveOnDay(Season s, tz.TZDateTime dayStart) {
  if (!s.active) return false;
  final dayEnd = CairoTime.at(dayStart.year, dayStart.month, dayStart.day + 1);
  if (s.startsAt != null && !s.startsAt!.isBefore(dayEnd)) return false;
  if (s.endsAt != null && s.endsAt!.isBefore(dayStart)) return false;
  return true;
}

List<Season> activeSeasonsAt(Iterable<Season> seasons, DateTime instant) =>
    seasons.where((s) => isSeasonActiveAt(s, instant)).toList();

bool _matchesDay(Liturgy l, tz.TZDateTime day) {
  if (l.date != null) {
    final d = CairoTime.calendarDate(l.date!);
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }
  return l.weekday != null && l.weekday == day.weekday;
}

/// Effective liturgies for a Cairo day: if an active season has liturgies
/// for that day they REPLACE the regular ones; otherwise the regular
/// (seasonKey == null) liturgies apply. Sorted by start time then order.
List<Liturgy> effectiveLiturgiesForDay({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
  Set<String>? types,
}) {
  final dayStart = CairoTime.startOfDay(day);
  final activeKeys = seasons.where((s) => isSeasonActiveOnDay(s, dayStart)).map((s) => s.key).toSet();
  bool typeOk(Liturgy l) => types == null || types.contains(l.type);

  final seasonal = liturgies
      .where((l) => l.seasonKey != null && activeKeys.contains(l.seasonKey) && _matchesDay(l, dayStart))
      .toList();
  // Replacement is decided on ALL seasonal services for the day (so e.g. Holy
  // Week Pascha hours also suspend the regular weekday masses), then filtered.
  final chosen = seasonal.isNotEmpty
      ? seasonal.where(typeOk).toList()
      : liturgies.where((l) => l.seasonKey == null && _matchesDay(l, dayStart) && typeOk(l)).toList();
  chosen.sort((a, b) {
    final c = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return chosen;
}

LiturgyOccurrence? _occurrence(Liturgy l, tz.TZDateTime day, int dayOffset) {
  final s = l.startMinutes;
  if (s == null) return null;
  var e = l.endMinutes ?? (s + 120);
  if (e <= s) e += 24 * 60; // crosses midnight (e.g. Easter night liturgy)
  return LiturgyOccurrence(
    l,
    CairoTime.at(day.year, day.month, day.day, s),
    CairoTime.at(day.year, day.month, day.day, e),
    dayOffset,
  );
}

/// Concrete occurrences for a Cairo day, honouring each season's exact time
/// window: a seasonal service counts only if it starts inside its season's
/// [startsAt, endsAt], and it replaces only the regular services that start
/// inside that window (so e.g. morning masses before a season starting at
/// 18:00 keep the regular schedule). Sorted by start time then order.
List<LiturgyOccurrence> occurrencesForDay({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
  required int dayOffset,
  Set<String>? types,
}) {
  final dayStart = CairoTime.startOfDay(day);
  final active = seasons.where((s) => isSeasonActiveOnDay(s, dayStart)).toList();
  bool typeOk(Liturgy l) => types == null || types.contains(l.type);

  final seasonal = <LiturgyOccurrence>[];
  final replacing = <Season>{};
  for (final l in liturgies) {
    if (l.seasonKey == null || !_matchesDay(l, dayStart)) continue;
    final o = _occurrence(l, dayStart, dayOffset);
    if (o == null) continue;
    final windows = active.where((s) => s.key == l.seasonKey && isSeasonActiveAt(s, o.start)).toList();
    if (windows.isEmpty) continue;
    seasonal.add(o);
    // Replacement is decided on ALL seasonal services (so e.g. Holy Week
    // Pascha hours also suspend the regular weekday masses), then filtered.
    replacing.addAll(windows);
  }

  final result = <LiturgyOccurrence>[
    for (final o in seasonal)
      if (typeOk(o.liturgy)) o,
    for (final l in liturgies)
      if (l.seasonKey == null && _matchesDay(l, dayStart) && typeOk(l))
        if (_occurrence(l, dayStart, dayOffset) case final o?)
          if (!replacing.any((s) => isSeasonActiveAt(s, o.start))) o,
  ];
  result.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.liturgy.order.compareTo(b.liturgy.order);
  });
  return result;
}

/// Next-mass smart card logic (see SPEC "Business rules").
///
/// [now] is any instant; it is converted to Africa/Cairo. By default only
/// `type == 'mass'` is considered; pass [types] to include vespers etc.
NextMassResult computeNextMass({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required DateTime now,
  Set<String> types = const {'mass'},
  int lookAheadDays = 7,
}) {
  final cairoNow = CairoTime.fromInstant(now);
  final today = CairoTime.startOfDay(cairoNow);
  LiturgyOccurrence? happening;
  LiturgyOccurrence? next;

  // Yesterday's occurrences may still be running past midnight.
  final yesterday = CairoTime.at(today.year, today.month, today.day - 1);
  for (final o in occurrencesForDay(
      liturgies: liturgies, seasons: seasons, day: yesterday, dayOffset: -1, types: types)) {
    if (o.isHappeningAt(cairoNow)) happening ??= o;
  }

  for (var offset = 0; offset <= lookAheadDays && next == null; offset++) {
    final day = CairoTime.at(today.year, today.month, today.day + offset);
    for (final o in occurrencesForDay(
        liturgies: liturgies, seasons: seasons, day: day, dayOffset: offset, types: types)) {
      if (offset == 0 && o.isHappeningAt(cairoNow)) {
        happening ??= o;
        continue;
      }
      if (o.start.isAfter(cairoNow)) {
        next = o;
        break;
      }
    }
  }
  return NextMassResult(
    happeningNow: happening,
    next: next,
    activeSeasons: activeSeasonsAt(seasons, cairoNow),
  );
}

/// Day tabs on the mass-schedule page.
enum ScheduleTab { friday, sunday, wednesday, saturday, other }

const Map<ScheduleTab, Set<int>> scheduleTabWeekdays = {
  ScheduleTab.friday: {5},
  ScheduleTab.sunday: {7},
  ScheduleTab.wednesday: {3},
  ScheduleTab.saturday: {6},
  ScheduleTab.other: {1, 2, 4},
};

/// Regular liturgies for a tab (weekly schedule, no seasonal overrides),
/// excluding vespers/praise which have their own section.
List<Liturgy> regularLiturgiesForTab(Iterable<Liturgy> all, ScheduleTab tab) {
  final days = scheduleTabWeekdays[tab]!;
  final list = all
      .where((l) =>
          l.seasonKey == null &&
          l.date == null &&
          l.weekday != null &&
          days.contains(l.weekday) &&
          l.type != 'vespers' &&
          l.type != 'praise')
      .toList();
  list.sort((a, b) {
    final w = (a.weekday ?? 0).compareTo(b.weekday ?? 0);
    if (w != 0) return w;
    final c = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return list;
}

/// Regular vespers & praise services.
List<Liturgy> vespersAndPraise(Iterable<Liturgy> all) {
  final list = all.where((l) => l.seasonKey == null && (l.type == 'vespers' || l.type == 'praise')).toList();
  list.sort((a, b) {
    final w = (a.weekday ?? 0).compareTo(b.weekday ?? 0);
    if (w != 0) return w;
    return (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
  });
  return list;
}

/// Seasonal liturgies grouped by season key, seasons sorted by start date.
Map<Season, List<Liturgy>> seasonalSchedule(Iterable<Season> seasons, Iterable<Liturgy> all) {
  final sorted = seasons.toList()
    ..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
  final map = <Season, List<Liturgy>>{};
  for (final s in sorted) {
    final ls = all.where((l) => l.seasonKey == s.key).toList()
      ..sort((a, b) {
        final da = a.date ?? DateTime(2000, 1, a.weekday ?? 0);
        final db = b.date ?? DateTime(2000, 1, b.weekday ?? 0);
        final c = da.compareTo(db);
        return c != 0 ? c : (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
      });
    if (ls.isNotEmpty) map[s] = ls;
  }
  return map;
}
